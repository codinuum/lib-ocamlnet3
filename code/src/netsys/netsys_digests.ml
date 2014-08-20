(* $Id$ *)

class type digest_ctx =
object
  method add_memory : Netsys_types.memory -> unit
  method add_substring : string -> int -> int -> unit
  method finish : unit -> string
end


class type digest =
object
  method name : string
  method size : int
  method block_length : int
  method create : unit -> digest_ctx
end


module Digest(Impl : Netsys_crypto_types.DIGESTS) = struct

  let digest_ctx (dg : Impl.digest) (ctx : Impl.digest_ctx) =
    ( object
        method add_memory mem =
          Impl.add ctx mem
        method add_substring s pos len =
          let mem, free = Netsys_mem.pool_alloc_memory2 Netsys_mem.small_pool in
          let n = ref len in
          let p = ref pos in
          while !n > 0 do
            let r = min !n (Bigarray.Array1.dim mem) in
            Netsys_mem.blit_string_to_memory s !p mem 0 r;
            Impl.add ctx (Bigarray.Array1.sub mem 0 r);
            n := !n - r;
            p := !p + r;
          done;
          free()
        method finish() =
          Impl.finish ctx
      end
    )

  let digest (dg : Impl.digest) =
    ( object
        method name = Impl.name dg
        method size = Impl.size dg
        method block_length = Impl.block_length dg
        method create() = digest_ctx dg (Impl.create dg)
      end
    )

  let list() =
    List.map digest Impl.digests

  let find name =
    digest (Impl.find name)

end


let digests ?(impl = Netsys_crypto.current_digests()) () =
  let module I = (val impl : Netsys_crypto_types.DIGESTS) in
  let module C = Digest(I) in
  C.list()


let find ?(impl = Netsys_crypto.current_digests()) name =
  let module I = (val impl : Netsys_crypto_types.DIGESTS) in
  let module C = Digest(I) in
  C.find name


let digest_string dg s =
  let ctx = dg # create() in
  ctx # add_substring s 0 (String.length s);
  ctx # finish()


let digest_mstrings (hash:digest) ms_list =
  (* Like Netsys_digests.digest_string, but for "mstring list" *)
  let ctx = hash#create() in

  let rec loop in_list =
    match in_list with
      | ms :: in_list' ->
	  let ms_len = ms#length in
	  ( match ms#preferred with
	      | `String ->
		  let (s,start) = ms#as_string in
		  ctx#add_substring s start ms_len;
		  loop in_list'
	      | `Memory ->
		  let (m,start) = ms#as_memory in
                  ctx#add_memory m;
		  loop in_list'
	  )
      | [] ->
	  ctx#finish() in
  loop ms_list
  

let xor_s s u =
  let s_len = String.length s in
  let u_len = String.length u in
  assert(s_len = u_len);
  let x = String.create s_len in
  for k = 0 to s_len-1 do
    x.[k] <- Char.chr ((Char.code s.[k]) lxor (Char.code u.[k]))
  done;
  x

let hmac_ctx dg key =
  let b = dg # block_length in
  if String.length key > b then
    invalid_arg "Netsys_digests.hmac: key too long";
  
  let k_padded = key ^ String.make (b - String.length key) '\000' in
  let ipad = String.make b '\x36' in
  let opad = String.make b '\x5c' in

  let ictx = dg#create() in
  let k_ipad = xor_s k_padded ipad in
  ictx # add_substring k_ipad 0 (String.length ipad);
  
  ( object
      method add_memory m =
        ictx # add_memory m
      method add_substring s pos len =
        ictx # add_substring s pos len
      method finish() =
        let ires = ictx # finish() in
        digest_string dg ((xor_s k_padded opad) ^ ires)
    end
  )

let hmac dg key =
  ( object
      method name = "HMAC-" ^ dg#name
      method size = dg#size
      method block_length = dg#block_length
      method create() = hmac_ctx dg key
    end
  )
