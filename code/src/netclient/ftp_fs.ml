(* $Id$ *)

(* TODO:
   - error code translation
   - mkdir flags
   - TVFS: NLST returns paths (apply basename)
   - readdir "/" -> "NLST "
   - Raises Not_found if URL not found
 *)

open Printf
open Ftp_client

class type ftp_stream_fs =
object
  inherit Netfs.stream_fs

  method last_ftp_state : Ftp_client.ftp_state
  method close : unit -> unit
end


let ftp_syn =
  Hashtbl.find Neturl.common_url_syntax "ftp"

let ftp_schemes =
  let ht = Hashtbl.create 5 in
  Hashtbl.add ht "ftp" ftp_syn;
  ht


class ftp_fs ?(config_client = fun _ -> ())
             ?tmp_directory
             ?tmp_prefix
             ?(get_password = fun () -> "")
             ?(get_account = fun () -> "")
	     ?(keep_open = false)
             base_url_s : ftp_stream_fs =
  (* parse base_url: *)
  let base_url =
    Neturl.parse_url 
      ~schemes:ftp_schemes
      ~accept_8bits:true
      (Neturl.fixup_url_string base_url_s) in
  (* create client and log in: *)
  let ftp = new Ftp_client.ftp_client () in
  let () = config_client ftp in
  let last_ftp_state = ref None in
  let transaction f =
    try
      let connected =
	try (ftp # pi # ftp_state).ftp_connected
	with Failure _ -> false in
      if not connected then (
	ftp # exec (Ftp_client.connect_method
		      ~host:(Neturl.url_host base_url)
		      ?port:(try Some(Neturl.url_port base_url) 
			     with Not_found -> None)
		      ()
		   );
	ftp # exec (Ftp_client.login_method
		      ~user:(try Neturl.url_user base_url
			     with Not_found -> "anonymous")
		      ~get_password
		      ~get_account
		      ()
		   );
      );
      let r = f() in
      last_ftp_state := Some(ftp # pi # ftp_state);
      if not keep_open then
	ftp # exec (Ftp_client.quit_method());
      r
    with
      | error ->
	  last_ftp_state := Some(ftp # pi # ftp_state);
	  if not keep_open then
	    ftp # reset();
	  raise error in
  let (supports_tvfs, supports_utf8) =
    transaction
      (fun () ->
	 ( try
	     ftp # exec (Ftp_client.feat_method())
	   with
	     | FTP_method_perm_failure _ -> ()
	 );
	 (ftp # pi # supports_tvfs,
	  ftp # pi # supports_utf8
	 )
      ) in
  let path_encoding =
    if supports_utf8 then Some `Enc_utf8 else None in
  let uerror code path detail =
    raise(Unix.Unix_error(code, detail, path)) in
  let einval path detail =
    raise(Unix.Unix_error(Unix.EINVAL, detail, path)) in
  let enosys path detail =
    raise(Unix.Unix_error(Unix.ENOSYS, detail, path)) in
  let translate path =
    (* Check path. Also prepend the path from the base URL. The returned
       path does not start with /. If just the root dir is means this function
       returns the empty string.
     *)
    if path = "" then
      einval path "Ftp_fs: path is empty";
    if path.[0] <> '/' then
      einval path "Ftp_fs: path is not absolute";
    if String.contains path '\000' then
      einval path "Ftp_fs: path contains NUL byte";
    ( match path_encoding with
	| None -> ()
	| Some pe ->
	    ( try
		Netconversion.verify pe path
	      with
		| Netconversion.Malformed_code_at _ ->
		    einval path "Ftp_fs: path is not properly encoded"
	    )
    );
    let npath = Neturl.norm_path(Neturl.split_path path) in
    ( match npath with
        | "" :: ".." :: _ -> (* CHECK: maybe ENOENT? *)
            einval path "Ftp_fs: path starts with /.."
        | _ -> ()
    );
    let base_path =
      match Neturl.url_path base_url with
	| [] -> [ "" ]
	| p -> p in
    let base_path_n =  (* no slash at the end, no at the beginning *)
      if List.hd (List.rev base_path) = "" && base_path <> [""] then
	List.tl (List.rev (List.tl (List.rev base_path)))
      else
	List.tl base_path in
    let path_trans =
      base_path_n @ (List.tl npath) in
    let p = 
      String.concat "/" path_trans in
    if supports_tvfs then `TVFS p else `NVFS p in
  
object(self)
  method path_encoding = path_encoding
  method path_exclusions = [0,0; 47,47]
  method nominal_dot_dot = true

  method last_ftp_state =
    match !last_ftp_state with
      | None ->
	  raise Not_found
      | Some st ->
	  st

  method close() =
    ftp # reset()

  method read flags path =
    last_ftp_state := None;
    let vfs = translate path in
    let representation =
      if List.mem `Binary flags then `Image else `ASCII None in
    let cur_tmp = ref None in
    let cleanup() =
      match !cur_tmp with
        | None -> ()
        | Some (tmp_name,inch,outch) ->
            (* Success *)
	    close_in inch;
	    close_out outch;
            ( try Unix.unlink tmp_name with _ -> ());  (* CHECK Win32 *)
	    cur_tmp := None in
    try
      transaction
	(fun () ->
	   ftp # exec (Ftp_client.get_method
			 ~file:vfs
			 ~representation
			 ~store:(fun _ ->
				   let (tmp_name, inch, outch) =
				     Netchannels.make_temporary_file 
				       ?tmp_directory ?tmp_prefix () in
				   cur_tmp := Some (tmp_name, inch, outch);
				   let obj_outch =
				     new Netchannels.output_channel outch in
				   `File_structure obj_outch
				)
			 ()
		      );
	);
      match !cur_tmp with
        | None ->
            assert false
        | Some (tmp_name,inch,outch) ->
            (* Success *)
	    let skip =
	      try 
		Http_fs.find_flag (function `Skip p -> Some p | _ -> None) flags
	      with Not_found -> 0L in
	    LargeFile.seek_in inch skip;
	    new Netchannels.input_channel
	      ~onclose:cleanup
	      inch
    with error ->
      cleanup();
      raise error

  method write flags path =
    last_ftp_state := None;
    let vfs = translate path in
    let representation =
      if List.mem `Binary flags then `Image else `ASCII None in
    
    let create_flag = List.mem `Create flags in
    let trunc_flag = List.mem `Truncate flags in
    let excl_flag = List.mem `Exclusive flags in

    if not create_flag && not trunc_flag then
      einval path "Ftp_fs.write: you need to request either file creation \
                   or file truncation";
    if create_flag && excl_flag then
      einval path "Ftp_fs.write: exclusive file creation not supported";
    
    let req =
      if create_flag && not excl_flag && not trunc_flag then
	Some false
      else
	if not create_flag then
	  Some true
	else
	  None in

    let cur_tmp = ref None in
    let (tmp_name, inch, outch) =
      Netchannels.make_temporary_file 
	?tmp_directory ?tmp_prefix () in
    cur_tmp := Some (tmp_name, inch, outch);

    let do_write() =
      transaction
	(fun () ->
	   close_out outch;

	   try
	     ( match req with
		 | None -> ()
		 | Some r_exists ->
		     let exists =
		       try
			 ftp # exec (Ftp_client.mlst_method
				       ~file:vfs
				       ~process_result:(fun _ -> ())
				       ()
				    );
			 true
		       with
			 | FTP_method_perm_failure(550,_) -> false in
		     if exists <> r_exists then
		       let ecode =
			 if r_exists then Unix.ENOENT else Unix.EPERM in
		       raise(uerror ecode path "Ftp_fs.write");
	     );
	     
	     ftp # exec (Ftp_client.put_method
			   ~file:vfs
			   ~representation
			   ~store:(fun _ ->
				     let obj_inch =
				       new Netchannels.input_channel inch in
				     `File_structure obj_inch
				  )
			   ()
			);
	     
	     close_in inch;
	     ( try Unix.unlink tmp_name with _ -> () )
	   with
	     | error ->
		 close_in inch;
		 ( try Unix.unlink tmp_name with _ -> () );
		 raise error
	)
    in
    
    let obj_outch =
      new Netchannels.output_channel 
	~onclose:do_write
	outch in

    obj_outch

  method size flags path =
    last_ftp_state := None;
    let vfs = translate path in
    transaction
      (fun () ->
	 let n = ref 0L in
	 ftp # exec (Ftp_client.size_method 
		       ~file:vfs
		       ~representation:`Image
		       ~process_result:(fun k -> n := k)
		       ());
	 !n
      )

  method test flags path typ =
    List.hd (self # test_list flags path [typ])


  method test_list flags path typl =
    last_ftp_state := None;
    let vfs = translate path in
    transaction
      (fun () ->
	 let entries = ref [] in
	 ( try
	     ftp # exec (Ftp_client.mlst_method 
			   ~file:vfs
			   ~process_result:(fun e -> entries := e)
			   ());
	   with
	     | FTP_method_perm_failure _
	     | FTP_method_temp_failure _ -> ()
	 );
	 List.map
	   (fun typ ->
	      match typ with
		| `N -> !entries <> []
		| `E -> !entries <> []
		| `D -> (List.exists
		           (fun e -> 
			      try get_type e = `Dir with Not_found -> false)
			   !entries
			)
		| `F -> (List.exists
		           (fun e -> 
			      try get_type e = `File with Not_found -> false)
			   !entries
			)
		| `H -> false
		| `R -> (List.exists
		           (fun e -> 
			      let p = try get_perm e with Not_found -> [] in
			      List.mem `List p || List.mem `Read p
			   )
			   !entries
			)
		| `W -> (List.exists
		           (fun e -> 
			      let p = try get_perm e with Not_found -> [] in
			      List.mem `Mkdir p || List.mem `Delete_member p ||
				List.mem `Write p
			   )
			   !entries
			)
		| `X -> (List.exists
		           (fun e -> 
			      let p = try get_perm e with Not_found -> [] in
			      List.mem `Enter p
			   )
			   !entries
			)
		| `S -> (List.exists
		           (fun e -> 
			      let s = try get_size e with Not_found -> 0L in
			      s > 0L
			   )
			   !entries
			)
	   )
	   typl
      )

  method remove flags path = 
    last_ftp_state := None;
    if List.mem `Recursive flags then
      einval path "Ftp_fs.remove: recursion not supported";
    let vfs = translate path in
    transaction
      (fun () ->
	 ftp # exec (Ftp_client.delete_method vfs)
      )

  method rename flags path1 path2 =
    last_ftp_state := None;
    let vfs1 = translate path1 in
    let vfs2 = translate path2 in
    transaction
      (fun () ->
	 ftp # exec (Ftp_client.rename_method ~file_from:vfs1 ~file_to:vfs2 ())
      )


  method readdir flags path =
    last_ftp_state := None;
    let vfs = translate path in
    transaction
      (fun () ->
	 let b = Buffer.create 500 in
	 let ch = new Netchannels.output_buffer b in
	 ftp#exec (Ftp_client.nlst_method 
		     ~dir:vfs 
		     ~representation:(`ASCII None)
		     ~store:(fun _ -> `File_structure ch)
		     ()
		  );
	 parse_nlst_document (Buffer.contents b)
      )


  method mkdir flags path =
    (* FIXME: flags *)
    last_ftp_state := None;
    let vfs = translate path in
    transaction
      (fun () ->
	 ftp # exec (Ftp_client.mkdir_method vfs)
      )

  method rmdir flags path =
    last_ftp_state := None;
    let vfs = translate path in
    transaction
      (fun () ->
	 ftp # exec (Ftp_client.rmdir_method vfs)
      )


  (* Unsupported *)

  method symlink _ path1 path2 = enosys path1 "Ftp_fs.symlink not supported"
  method copy flags path1 path2 = enosys path1 "Ftp_fs.copy not supported"
  method readlink flags path = enosys path "Ftp_fs.readlink not supported"
end


let ftp_fs = new ftp_fs