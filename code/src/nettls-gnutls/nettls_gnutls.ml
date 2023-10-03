(* $Id$ *)

open Printf

module StrMap = Map.Make(String)
module StrSet = Set.Make(String)
module OID = struct type t = Netoid.t let compare = Stdlib.compare end
module OIDMap = Map.Make(OID)

module type GNUTLS_PROVIDER =
  sig
    include Netsys_crypto_types.TLS_PROVIDER

    val gnutls_session : endpoint -> Nettls_gnutls_bindings.gnutls_session_t
    val gnutls_credentials : credentials -> 
                               Nettls_gnutls_bindings.gnutls_credentials
  end


module type GNUTLS_ENDPOINT =
  sig
    module TLS : GNUTLS_PROVIDER
    val endpoint : TLS.endpoint
  end


exception I of (module GNUTLS_PROVIDER)

module type SELF =
  sig
    val self : exn ref
  end


let parse_pem ?(empty_ok=false) header_tags file f =
  let spec = List.map (fun tag -> (tag, `Base64)) header_tags in
  let blocks =
    Netchannels.with_in_obj_channel
      (new Netchannels.input_channel(open_in file))
      (fun ch -> Netascii_armor.parse spec ch) in
  if not empty_ok && blocks = [] then
    failwith ("Cannot find PEM-encoded objects in file: " ^ file);
  List.map
    (function
      | (tag, `Base64 body) -> f (tag,body#value)
      | _ -> assert false
    )
    blocks
    
let create_pem header_tag data =
  let b64 = Netencoding.Base64.encode ~linelength:80 data in
  "-----BEGIN " ^ header_tag ^ "-----\n" ^ 
    b64 ^
      "-----END " ^ header_tag ^ "-----\n"


module Make_TLS_1 
         (Self:SELF)
         (Exc:Netsys_crypto_types.TLS_EXCEPTIONS) : GNUTLS_PROVIDER =
  struct
    let implementation_name = "Nettls_gnutls.TLS"
    let implementation () = !Self.self

    module Exc = Exc
    module G = Nettls_gnutls_bindings

    type credentials =
        { gcred : G.gnutls_credentials;
          gcred_create : unit -> G.gnutls_credentials;
        }

    type dh_params =
      [ `PKCS3_PEM_file of string
      | `PKCS3_DER of string
      | `Generate of int
      ]
          
    type crt_list =
        [`PEM_file of string | `DER of string list]

    type crl_list =
        [`PEM_file of string | `DER of string list]

    type private_key =
        [ `PEM_file of string 
        | `RSA of string 
        | `DSA of string
        | `EC of string
        | `PKCS8 of string
        | `PKCS8_encrypted of string
        ]

    type server_name = [ `Domain of string ]

    type state =
        [ `Start | `Handshake | `Data_rw | `Data_r | `Data_w | `Data_rs
        | `Switching | `Accepting | `Refusing | `End
        ]

    type raw_credentials =
      [ `X509 of string
      | `Anonymous
      ]

    type role = [ `Server | `Client ]

    type endpoint =
        { role : role;
          recv : (Netsys_types.memory -> int);
          send : (Netsys_types.memory -> int -> int);
          mutable config : config;
          session : G.gnutls_session_t;
          peer_name : string option;
          mutable our_cert : raw_credentials option;
          mutable state : state;
          mutable trans_eof : bool;
        }

      and config =
        { priority : G.gnutls_priority_t;
          dh_params : G.gnutls_dh_params_t option;
          peer_auth : [ `None | `Optional | `Required ];
          credentials : credentials;
          verify : endpoint -> bool -> bool -> bool;
        }

    type serialized_session =
        { ser_data : string;    (* GnuTLS packed session *)
          ser_our_cert : raw_credentials option;
        }

    let error_message code = 
      match code with
        | "NETTLS_CERT_VERIFICATION_FAILED" ->
             "The certificate could not be verified against the list of \
              trusted authorities"
        | "NETTLS_NAME_VERIFICATION_FAILED" ->
             "The name of the peer does not match the name of the certificate"
        | "NETTLS_USER_VERIFICATION_FAILED" ->
             "The user-supplied verification function did not succeed"
        | "NETTLS_UNEXPECTED_STATE" ->
             "The endpoint is in an unexpected state"
        | _ ->
             G.gnutls_strerror (G.b_error_of_name code)


    let () =
      Netexn.register_printer
        (Exc.TLS_error "")
        (function
          | Exc.TLS_error code ->
               sprintf "Nettls_gnutls.TLS.Error(%s)" code
          | _ ->
               assert false
        )

    let () =
      Netexn.register_printer
        (Exc.TLS_warning "")
        (function
          | Exc.TLS_warning code ->
               sprintf "Nettls_gnutls.TLS.Warning(%s)" code
          | _ ->
               assert false
        )

    let trans_exn f arg =
      try
        f arg
      with
        | G.Error code ->
            raise(Exc.TLS_error (G.gnutls_strerror_name code))
                                   

    let default_algorithms = "NORMAL:-VERS-TLS1.3"
      (* TLS1.3 is disabled because it triggers a problem in the way we
         use GnuTLS - this still needs to be understood
       *)

    let create_config ?(algorithms=default_algorithms) ?dh_params
                      ?(verify=fun _ cert_ok name_ok -> cert_ok && name_ok)
                      ~peer_auth 
                      ~credentials () =
      let f() =
        let priority = G.gnutls_priority_init algorithms in
        let dhp_opt =
          match dh_params with
            | None -> None
            | Some(`PKCS3_PEM_file file) ->
                let data =
                  List.hd (parse_pem ["DH PARAMETERS"] file snd) in
                let dhp = G.gnutls_dh_params_init() in
                G.gnutls_dh_params_import_pkcs3 dhp data `Der;
                Some dhp
            | Some(`PKCS3_DER data) ->
                let dhp = G.gnutls_dh_params_init() in
                G.gnutls_dh_params_import_pkcs3 dhp data `Der;
                Some dhp
            | Some(`Generate bits) ->
                let dhp = G.gnutls_dh_params_init() in
                G.gnutls_dh_params_generate2 dhp bits;
                Some dhp in
        let credentials' =
          match dhp_opt with
            | None ->
                 credentials
            | Some dhp ->
                 let c = credentials.gcred_create() in
                 ( match c with
                     | `Certificate gc ->
                          G.gnutls_certificate_set_dh_params gc dhp
                     | _ ->
                          ()
                 );
                 { credentials with gcred = c } in
        { priority;
          dh_params = dhp_opt;
          peer_auth;
          credentials = credentials';
          verify;
        } in
      trans_exn f ()


    let get_der_crts proj boundaries spec =
      List.map
        (fun x ->
           match proj x with
             | `PEM_file file ->
                  parse_pem [ "X509 CERTIFICATE"; "CERTIFICATE" ] file snd
             | `DER l ->
                  l
        )
        spec

    let get_der_pkeys spec =
      List.map
        (fun (_,pkey,pw_opt) ->
           let pkey1 =
             match pkey with 
               | `PEM_file file ->
                    let p =
                      parse_pem
                        [ "RSA PRIVATE KEY";
                          "DSA PRIVATE KEY";
                          "EC PRIVATE KEY";
                          "PRIVATE KEY";
                          "ENCRYPTED PRIVATE KEY"
                        ]
                        file
                        (fun (tag,data) ->
                           match tag with
                             | "RSA PRIVATE KEY" -> `RSA data
                             | "DSA PRIVATE KEY" -> `DSA data
                             | "EC PRIVATE KEY" -> `EC data
                             | "PRIVATE KEY" -> `PKCS8 data
                             | "ENCRYPTED PRIVATE KEY" -> `PKCS8_encrypted data
                             | _ -> assert false
                        ) in
                    (List.hd p :> private_key)
               | other ->
                    other in
           ( match pkey1 with
               | `PKCS8_encrypted data ->
                    ( match pw_opt with
                        | None ->
                             failwith "No password for encrypted PKCS8 data"
                        | Some _ ->
                             ()
                    )
               | _ ->
                    ()
           );
           pkey1
        )
        spec


    let id x = x
    let p13 (x,_,_) = x


    let create_x509_credentials_1 ~system_trust ~trust ~revoke ~keys () =
      let trust_certs =
        get_der_crts id [ "X509 CERTIFICATE"; "CERTIFICATE" ] trust in
      let revoke_certs =
        get_der_crts id [ "X509 CRL" ] revoke in
      let certs =
        get_der_crts p13 [ "X509 CERTIFICATE"; "CERTIFICATE" ] keys in
      let pkeys =
        get_der_pkeys keys in
      let cplist =
        List.combine certs pkeys in
      let create () =
        let gcred = G.gnutls_certificate_allocate_credentials() in
        if system_trust then (
          match Nettls_gnutls_config.system_trust with
            | `Gnutls ->
                 G.gnutls_certificate_set_x509_system_trust gcred
            | `File path ->
                 let certs =
                   parse_pem [ "X509 CERTIFICATE"; "CERTIFICATE" ] path snd in
                 List.iter
                   (fun data ->
                      G.gnutls_certificate_set_x509_trust_mem gcred data `Der
                   )
                   certs
        );
        List.iter
          (fun der_crts ->
             List.iter
               (fun data ->
                  G.gnutls_certificate_set_x509_trust_mem gcred data `Der
               )
               der_crts
          )
          trust_certs;
        List.iter
          (fun der_crls ->
             List.iter
               (fun data ->
                  G.gnutls_certificate_set_x509_crl_mem gcred data `Der
               )
               der_crls
          )
          revoke_certs;
        List.iter2
          (fun (der_crts,pkey1) (_, _, pw_opt) ->
             let gcrts =
               List.map
                 (fun data ->
                    let gcrt = G.gnutls_x509_crt_init() in
                    G.gnutls_x509_crt_import gcrt data `Der;
                    gcrt
                 )
                 der_crts in
             let gpkey = G.gnutls_x509_privkey_init() in
             ( match pkey1 with
                 | `PEM_file file ->
                     assert false
                 | `RSA data ->
                     (* There is no entry point for parsing ONLY this format *)
                     let pem = create_pem "RSA PRIVATE KEY" data in
                     G.gnutls_x509_privkey_import gpkey pem `Pem
                 | `DSA data ->
                     (* There is no entry point for parsing ONLY this format *)
                     let pem = create_pem "DSA PRIVATE KEY" data in
                     G.gnutls_x509_privkey_import gpkey pem `Pem
                 | `EC data ->
                     (* There is no entry point for parsing ONLY this format *)
                     let pem = create_pem "EC PRIVATE KEY" data in
                     G.gnutls_x509_privkey_import gpkey pem `Pem
                 | `PKCS8 data ->
                     G.gnutls_x509_privkey_import_pkcs8 
                       gpkey data `Der "" [`Plain]
                 | `PKCS8_encrypted data ->
                     ( match pw_opt with
                         | None ->
                              assert false
                         | Some pw ->
                              G.gnutls_x509_privkey_import_pkcs8
                                gpkey data `Der pw []
                     )

             );
             G.gnutls_certificate_set_x509_key gcred (Array.of_list gcrts) gpkey
          )
          cplist keys;
        G.gnutls_certificate_set_verify_flags gcred [];
        `Certificate gcred in
      { gcred = create();
        gcred_create = create
      }

    let create_x509_credentials ?(system_trust=false) 
                                ?(trust=[]) ?(revoke=[]) ?(keys=[]) () =
      trans_exn
        (create_x509_credentials_1 ~system_trust ~trust ~revoke ~keys)
        ()

    let deactivate_pull_timeout session =
      G.b_set_pull_timeout_callback session
        (fun _ ->
           failwith "Nettls_gnutls: unexpected call of pull_timeout function (hint: this may happen if TLS1.3 is picked; it is better to disable TLS1.3 for the time being)"
        )

    let create_endpoint ~role ~recv ~send ~peer_name config =
      if peer_name=None && 
         role=`Client &&
         config.peer_auth <> `None
      then
        failwith "TLS configuration error: authentication required, \
                  but no peer_name set";
      let f() =
        let flags = [ (role :> G.gnutls_init_flags_flag); (*`Nonblock*) ] in
        (* `Nonblock is recommended by GnuTLS but it apparently does not work
           properly - need to understand this. Probably required for fixing
           TLS1.3 *)
        let session = G.gnutls_init flags in
        let ep =
          { role;
            recv;
            send;
            config;
            our_cert = None;
            session;
            peer_name;
            state = `Start;
            trans_eof = false;
          } in
        let recv1 mem =
          let n = recv mem in
          if Bigarray.Array1.dim mem > 0 && n=0 then ep.trans_eof <- true;
          n in
        G.b_set_pull_callback session recv1;
        G.b_set_push_callback session send;
        deactivate_pull_timeout session;

        G.gnutls_priority_set session config.priority;
        G.gnutls_credentials_set session config.credentials.gcred;

        if role = `Client then (
          match peer_name with
            | None -> ()
            | Some n ->
                G.gnutls_server_name_set session `Dns (Bytes.of_string n)
        );

        if role = `Server && config.peer_auth <> `None then
          G.gnutls_certificate_server_set_request
            session
            (match config.peer_auth with
               | `Optional -> `Request
               | `Required -> `Require
               | `None -> assert false
            );
        ep
      in
      trans_exn f ()

    exception Stashed of role * config * G.gnutls_session_t * string option *
                           raw_credentials option * state * bool

    let stash_endpoint ep =
      G.b_set_pull_callback ep.session (fun _ -> 0);
      G.b_set_push_callback ep.session (fun _ _ -> 0);
      let exn =
        Stashed(ep.role,
                ep.config,
                ep.session,
                ep.peer_name,
                ep.our_cert,
                ep.state,
                ep.trans_eof) in
      ep.state <- `End;
      exn

    let restore_endpoint ~recv ~send exn =
      match exn with
        | Stashed(role,config,session,peer_name,our_cert,state,trans_eof) ->
             let ep =
               { role; recv; send; config; session; peer_name;
                 our_cert; state; trans_eof
               } in
             let recv1 mem =
               let n = recv mem in
               if Bigarray.Array1.dim mem > 0 && n=0 then ep.trans_eof <- true;
               n in
             G.b_set_pull_callback session recv1;
             G.b_set_push_callback session send;
             ep
        | _ ->
             failwith "Nettls_gnutls.restore_endpoint: bad exception value"

          
    let resume_client ~recv ~send ~peer_name config data =
      let f() =
        let flags = [ `Client ] in
        let session = G.gnutls_init flags in
        G.gnutls_session_set_data session (Bytes.unsafe_of_string data);
        let ep =
          { role = `Client;
            recv;
            send;
            config;
            our_cert = None;
            session;
            peer_name;
            state = `Start;
            trans_eof = false;
          } in
        let recv1 mem =
          let n = recv mem in
          if Bigarray.Array1.dim mem > 0 && n=0 then ep.trans_eof <- true;
          n in
        G.b_set_pull_callback session recv1;
        G.b_set_push_callback session send;
        deactivate_pull_timeout session;

        G.gnutls_priority_set session config.priority;
        G.gnutls_credentials_set session config.credentials.gcred;
        ep
      in
      trans_exn f ()
          
    let get_state ep = ep.state

    let get_config ep = ep.config

    let at_transport_eof ep = ep.trans_eof

    let endpoint_exn ?(warnings=false) ep f arg =
      try
        f arg
      with
        | G.Error `Again -> 
            if G.gnutls_record_get_direction ep.session then
              raise Exc.EAGAIN_WR
            else
              raise Exc.EAGAIN_RD
        | G.Error `Interrupted ->
            raise (Unix.Unix_error(Unix.EINTR, "Nettls_gnutls", ""))
        | G.Error `Rehandshake ->
            (* ignore rehandshakes triggered by the client *)
            if ep.role = `Server then
              raise (Unix.Unix_error(Unix.EINTR, "Nettls_gnutls", ""));
            if ep.state = `Switching then
              raise (Exc.TLS_switch_response true)
            else
              raise Exc.TLS_switch_request
        | G.Error (`Warning_alert_received as code) ->
            if G.gnutls_alert_get ep.session = `No_renegotiation then
              raise (Exc.TLS_switch_response false)
            else
              let code' = G.gnutls_strerror_name code in
              if warnings then
                raise(Exc.TLS_warning code')
              else
                raise(Exc.TLS_error code')
        | G.Error code ->
            let code' = G.gnutls_strerror_name code in
            if warnings && not(G.gnutls_error_is_fatal code) then
              raise(Exc.TLS_warning code')
            else
              raise(Exc.TLS_error code')

    let unexpected_state() =
      raise(Exc.TLS_error "NETTLS_UNEXPECTED_STATE")

    let update_our_cert ep =
      (* our_cert: if the session is resumed, our_cert should already be
         filled in by the [retrieve] callback (because GnuTLS omit this
         certificate in its own serialization format)
       *)
      if ep.our_cert = None then
        (* So far only X509... *)
        trans_exn
          (fun () ->
             ep.our_cert <- 
               Some (try
                        `X509 (G.gnutls_certificate_get_ours ep.session)
                      with
                        | G.Null_pointer -> `Anonymous
                    )
          )
          ()


    let hello ep =
      if ep.state <> `Start && ep.state <> `Handshake &&
           ep.state <> `Switching then
        unexpected_state();
      ep.state <- `Handshake;
      endpoint_exn
        ~warnings:true
        ep
        G.gnutls_handshake
        ep.session;
      update_our_cert ep;
      ep.state <- `Data_rw

    let bye ep how =
      if ep.state <> `End then (
        if ep.state <> `Data_rw && ep.state <> `Data_r && ep.state <> `Data_w
        then 
          unexpected_state();
        if how <> Unix.SHUTDOWN_RECEIVE then (
          let ghow, new_state =
            match how with
              | Unix.SHUTDOWN_SEND ->
                   `Wr, (if ep.state = `Data_w then `End else `Data_r)
              | Unix.SHUTDOWN_ALL ->
                   `Rdwr, `End
              | Unix.SHUTDOWN_RECEIVE ->
                   assert false in
          endpoint_exn
            ~warnings:true
            ep
            (fun arg ->
              try G.gnutls_bye ep.session arg;
              with
                | G.Error `Premature_termination -> ()
            )
            ghow;
          ep.state <- new_state
        )
      )

    let verify ep =
      let f() =
        let cert_ok, name_ok =
          if G.gnutls_certificate_get_peers ep.session = [| |] then (
            (* No certificate available *)
            if ep.config.peer_auth = `Required then
              raise(Exc.TLS_error
                      (G.gnutls_strerror_name `No_certificate_found));
            (true, true)
          )
          else (
            if ep.config.peer_auth = `None then
              (* Checks turned off *)
              (true, true)
            else
              let status_l = G.gnutls_certificate_verify_peers2 ep.session in
              let cert_ok = 
                status_l = [] in
(*
              failwith(sprintf "Certificate verification failed with codes: " ^ 
                         (String.concat ", " 
                            (List.map 
                               G.string_of_verification_status_flag
                               status_l)));
 *)
              let name_ok =
                match ep.peer_name with
                  | None ->
                      (* = we do not expect any particular name in the cert *)
                      true
                  | Some pn ->
                      let der_peer_certs = 
                        G.gnutls_certificate_get_peers ep.session in
                      assert(der_peer_certs <> [| |]);
                      let peer_cert = G.gnutls_x509_crt_init() in
                      G.gnutls_x509_crt_import peer_cert der_peer_certs.(0) `Der;
                      let ok = G.gnutls_x509_crt_check_hostname peer_cert pn in
                      ok in
              (cert_ok, name_ok)
          ) in
        let ok =
          ep.config.verify ep cert_ok name_ok in
        if not ok then
          raise(Exc.TLS_error "NETTLS_VERIFICATION_FAILED");
        () in
      trans_exn f ()

    let get_endpoint_creds ep =
      match ep.our_cert with
        | Some c -> c
        | None -> failwith "get_endpoint_creds: unavailable"

    let get_peer_creds ep =
      (* So far only X509... *)
      trans_exn
        (fun () ->
           try
             let certs = G.gnutls_certificate_get_peers ep.session in
             if certs = [| |] then
               `Anonymous
             else
               `X509 certs.(0)
           with
             | G.Null_pointer -> `Anonymous
        )
        ()

    let get_peer_creds_list ep =
      (* So far only X509... *)
      trans_exn
        (fun () ->
           try
             let certs = G.gnutls_certificate_get_peers ep.session in
             if certs = [| |] then
               [ `Anonymous ]
             else
               List.map (fun c -> `X509 c) (Array.to_list certs)
           with
             | G.Null_pointer -> [ `Anonymous ]
        )
        ()

    let switch ep conf =
      if ep.state <> `Data_rw && ep.state <> `Data_w && ep.state <> `Switching
      then
        unexpected_state();
      ep.state <- `Switching;
      ep.config <- conf;
      endpoint_exn
        ~warnings:true
        ep
        G.gnutls_rehandshake
        ep.session;
      ep.state <- `Data_rs


    let accept_switch ep conf =
      if ep.state <> `Data_rw && ep.state <> `Data_w && ep.state <> `Accepting 
      then
        unexpected_state();
      ep.state <- `Accepting;
      ep.config <- conf;
      endpoint_exn
        ~warnings:true
        ep
        G.gnutls_handshake
        ep.session;
      update_our_cert ep;
      ep.state <- `Data_rw


    let refuse_switch ep =
      if ep.state <> `Data_rw && ep.state <> `Data_w && ep.state <> `Refusing 
      then
        unexpected_state();
      ep.state <- `Refusing;
      endpoint_exn
        ~warnings:true
        ep
        (G.gnutls_alert_send ep.session `Warning)
        `No_renegotiation;
      ep.state <- `Data_rw


    let send ep buf n =
      if ep.state <> `Data_rw && ep.state <> `Data_w then
        unexpected_state();
      endpoint_exn
        ~warnings:true
        ep
        (G.gnutls_record_send ep.session buf)
        n

    let recv ep buf =
      if ep.state = `Data_w || ep.state = `End then
        0
      else (
        if ep.state <> `Data_rw && ep.state <> `Data_r && ep.state <> `Data_rs 
        then
          unexpected_state();
        let n =
          endpoint_exn
            ~warnings:true
            ep
            (fun arg ->
              try G.gnutls_record_recv ep.session arg
              with G.Error `Premature_termination -> 0
            )
            buf in
        if Bigarray.Array1.dim buf > 0 && n=0 then
          ep.state <- (if ep.state = `Data_rw then `Data_w else `End);
        n
      )

    let recv_will_not_block ep =
      let f() =
        G.gnutls_record_check_pending ep.session > 0 in
      trans_exn f ()

    let get_session_id ep =
      trans_exn
        (fun () ->
           Bytes.to_string (G.gnutls_session_get_id ep.session)
        )
        ()

    let get_session_data ep =
      trans_exn
        (fun () ->
           Bytes.to_string (G.gnutls_session_get_data ep.session)
        )
        ()

    let get_cipher_suite_type ep =
      "X509"  (* so far only this is supported *)

    let get_cipher_algo ep =
      let f() =
        G.gnutls_cipher_get_name (G.gnutls_cipher_get ep.session) in
      trans_exn f ()

    let get_kx_algo ep =
      let f() =
        G.gnutls_kx_get_name (G.gnutls_kx_get ep.session) in
      trans_exn f ()

    let get_mac_algo ep =
      let f() =
        G.gnutls_mac_get_name (G.gnutls_mac_get ep.session) in
      trans_exn f ()

    let get_compression_algo ep =
      let f() =
        G.gnutls_compression_get_name (G.gnutls_compression_get ep.session) in
      trans_exn f ()

    let get_cert_type ep =
      let f() =
        G.gnutls_certificate_type_get_name
          (G.gnutls_certificate_type_get ep.session) in
      trans_exn f ()
      
    let get_protocol ep =
      let f() =
        G.gnutls_protocol_get_name (G.gnutls_protocol_get_version ep.session) in
      trans_exn f ()

    let get_addressed_servers ep =
      let rec get k =
        try
          let n1, t = G.gnutls_server_name_get ep.session k in
          let n2 =
            match t with
              | `Dns -> `Domain (Bytes.to_string n1) in
          n2 :: get(k+1)
        with
          | G.Error `Requested_data_not_available ->
              [] in
      trans_exn get 0

    let set_session_cache ~store ~remove ~retrieve ep =
      let g_store key data =
        update_our_cert ep;
        let r =
          { ser_data = data;
            ser_our_cert = ep.our_cert
          } in
        store key (Marshal.to_string r []) in
      let g_retrieve key =
        let s = retrieve key in
        let r = (Marshal.from_string s 0 : serialized_session) in
        (* HACK: *)
        ep.our_cert <- r.ser_our_cert;
        r.ser_data in
      G.b_set_db_callbacks ep.session g_store remove g_retrieve

    let gnutls_credentials c = c.gcred
    let gnutls_session ep = ep.session
  end


let make_tls (exc : (module Netsys_crypto_types.TLS_EXCEPTIONS)) =
  let module Self =
    struct
      let self = ref Not_found
    end in
  let module Exc =
    (val exc : Netsys_crypto_types.TLS_EXCEPTIONS) in
  let module Impl =
    Make_TLS_1(Self)(Exc) in
  let () =
    Self.self := I (module Impl) in
  (module Impl : GNUTLS_PROVIDER)


(*
module Make_TLS (Exc:Netsys_crypto_types.TLS_EXCEPTIONS) : GNUTLS_PROVIDER =
  (val make_tls (module Exc) : GNUTLS_PROVIDER)
 *)

module GNUTLS = (val make_tls (module Netsys_types))
module TLS = (GNUTLS : Netsys_crypto_types.TLS_PROVIDER)

let gnutls = (module GNUTLS : GNUTLS_PROVIDER)
let tls = (module TLS : Netsys_crypto_types.TLS_PROVIDER)


let endpoint ep =
  let module EP =
    struct
      module TLS = GNUTLS
      let endpoint = ep
    end in
  (module EP : GNUTLS_ENDPOINT)

let downcast p =
  let module P = (val p : Netsys_crypto_types.TLS_PROVIDER) in
  match P.implementation() with
    | I tls -> tls
    | _ -> raise Not_found

let downcast_endpoint ep_mod =
  let module EP = (val ep_mod : Netsys_crypto_types.TLS_ENDPOINT) in
  let module T = (val downcast (module EP.TLS)) in
  let module EP1 =
    struct
      module TLS = T
      let endpoint = (Obj.magic EP.endpoint)
    end in
  (module EP1 : GNUTLS_ENDPOINT)

let rec filter_map f l =
  match l with
    | x :: l' ->
         ( try
             let x' = f x in
             x' :: filter_map f l'
           with
             | Not_found -> filter_map f l'
         )
    | [] ->
         []

let of_list l =
  List.fold_left
    (fun acc (n,v) -> StrMap.add n v acc)
    StrMap.empty
    l

module Basic_symmetric_crypto : Netsys_crypto_types.SYMMETRIC_CRYPTO = struct
  open Nettls_nettle_bindings
  open Nettls_gnutls_bindings
  open Netsys_crypto_modes.Symmetric_cipher

  let no_iv = [ 0, 0 ]

  (* The ciphers we access directly via the Nettle API. These are all in ECB
     or STREAM mode)
   *)

  let nettle_basic_props =
    [ "aes128", ("AES-128", "ECB", [ 16, 16 ], no_iv, 16);
      "aes192", ("AES-192", "ECB", [ 24, 24 ], no_iv, 16);
      "aes256", ("AES-256", "ECB", [ 32, 32 ], no_iv, 16);
      "arcfour128", ("ARCFOUR-128", "STREAM", [ 16, 16; 1, 256 ], no_iv, 1);
      "arctwo40", ("RC2-40", "ECB", [ 8, 8; 1, 256 ], no_iv, 8);
      "arctwo64", ("RC2-64", "ECB", [ 8, 8; 1, 256 ], no_iv, 8);
      "arctwo128", ("RC2-128", "ECB", [ 8, 8; 1, 256 ], no_iv, 8);
      "blowfish", ("BLOWFISH", "ECB", [ 16, 16; 8, 56 ], no_iv, 8);
      "camellia128", ("CAMELLIA-128", "ECB", [ 16, 16 ], no_iv, 16);
      "camellia192", ("CAMELLIA-192", "ECB", [ 24, 24 ], no_iv, 16);
      "camellia256", ("CAMELLIA-256", "ECB", [ 32, 32 ], no_iv, 16);
      "cast128", ("CAST-128", "ECB", [ 16, 16; 5, 16 ], no_iv, 8); 
      (* "chacha" - does not fit in here (no way to set nonce) *)
      "des", ("DES-56", "ECB", [ 8, 8 ], no_iv, 8);
      "des3", ("3DES-112", "ECB", [ 24, 24 ], no_iv, 8);
      (* "salsa20" - does not fit in here (no way to set nonce) *)
      "serpent128", ("SERPENT-128", "ECB", [ 16, 16 ], no_iv, 16);
      "serpent192", ("SERPENT-192", "ECB", [ 24, 24 ], no_iv, 16);
      "serpent256", ("SERPENT-256", "ECB", [ 32, 32 ], no_iv, 16);
      "twofish128", ("TWOFISH-128", "ECB", [ 16, 16 ], no_iv, 16);
      "twofish192", ("TWOFISH-192", "ECB", [ 24, 24 ], no_iv, 16);
      "twofish256", ("TWOFISH-256", "ECB", [ 32, 32 ], no_iv, 16);
      (* "arctwo_gutmann128" is non-standard *)
    ]

  let nettle_basic_props_m =
    of_list nettle_basic_props

  let check_key l key_lengths =
    if not (List.exists (fun (min,max) -> l >= min && l <= max) key_lengths)
    then
      failwith "create: invalid key length for this cipher"

  let check_iv l iv_lengths =
    if not (List.exists (fun (min,max) -> l >= min && l <= max) iv_lengths)
    then
      failwith "create: invalid iv length for this cipher"

  let no_mac _ =
    failwith "mac: not supported by this cipher"

  let nettle_basic_ciphers =
    let l = 
      Array.to_list (net_nettle_ciphers()) @
        Array.to_list (net_ext_ciphers()) in
    filter_map
      (fun nc ->
         let (name,mode,key_lengths,iv_lengths,dc) = 
           StrMap.find (net_nettle_cipher_name nc) nettle_basic_props_m in
         let set_iv s =
           if s <> "" then
             invalid_arg "set_iv: empty string expected" in
         let set_header s =
           () in
         let create key =
           let lkey = String.length key in
           check_key lkey key_lengths;
           let ctx = net_nettle_create_cipher_ctx nc in
           let first = ref true in
           let encrypt inbuf outbuf =
             let lbuf = Bigarray.Array1.dim inbuf in
             if lbuf <> Bigarray.Array1.dim outbuf then
               invalid_arg "encrypt: output buffer must have same size \
                            as input buffer";
             if lbuf mod dc <> 0 then
               invalid_arg (sprintf "encrypt: buffers must be multiples \
                                     of %d" dc);
             if !first then
               net_nettle_set_encrypt_key nc ctx (Bytes.of_string key);
             first := false;
             net_nettle_encrypt nc ctx lbuf outbuf inbuf in
           let decrypt inbuf outbuf =
             let lbuf = Bigarray.Array1.dim inbuf in
             if lbuf <> Bigarray.Array1.dim outbuf then
               invalid_arg "decrypt: output buffer must have same size \
                            as input buffer";
             if lbuf mod dc <> 0 then
               invalid_arg (sprintf "decrypt: buffers must be multiples \
                                     of %d" dc);
             if !first then
               net_nettle_set_decrypt_key nc ctx (Bytes.of_string key);
             first := false;
             net_nettle_decrypt nc ctx lbuf outbuf inbuf;
             true in
           { set_iv;
             set_header;
             encrypt;
             decrypt;
             mac = no_mac;
           } in
         { name;
           mode;
           key_lengths;
           iv_lengths;
           block_constraint = dc;
           supports_aead = false;
           create;
         }
      )
      l

  (* GCM. This is optional.
   
     Later Nettle versions have also a generic API for aead: TODO.
   *)

  let iv_gcm = [ 12, 12; 0, 256 ]

  let nettle_gcm_aes_props =
    if net_have_gcm_aes() then
      [ ("AES-128", "GCM", [ 16, 16 ], iv_gcm, 1);
        ("AES-192", "GCM", [ 24, 24 ], iv_gcm, 1);
        ("AES-256", "GCM", [ 32, 32 ], iv_gcm, 1);
      ]
    else
      []

  let nettle_gcm_aes_ciphers =
    List.map
      (fun (name, mode, key_lengths, iv_lengths, bs) ->
         let create key =
           let lkey = String.length key in
           check_key lkey key_lengths;
           let ctx = ref None in
           let iv = ref "" in
           let hdr = ref "" in
           let set_iv s =
             check_iv (String.length s) iv_lengths;
             iv := s in
           let set_header s =
             hdr := s in
           let get_ctx() =
             match !ctx with
               | None ->
                    let c = net_nettle_gcm_aes_init() in
                    nettle_gcm_aes_set_key c (Bytes.of_string key);
                    nettle_gcm_aes_set_iv c (Bytes.of_string !iv);
                    nettle_gcm_aes_update c (Bytes.of_string !hdr);
                    ctx := Some c;
                    c
               | Some c ->
                    c in
           let encrypt inbuf outbuf =
             let lbuf = Bigarray.Array1.dim inbuf in
             if lbuf <> Bigarray.Array1.dim outbuf then
               invalid_arg "encrypt: output buffer must have same size \
                            as input buffer";
             if lbuf mod bs <> 0 then
               invalid_arg (sprintf "encrypt: buffers must be multiples \
                                     of %d" bs);
             let c = get_ctx() in
             nettle_gcm_aes_encrypt c lbuf outbuf inbuf in
           let decrypt inbuf outbuf =
             let lbuf = Bigarray.Array1.dim inbuf in
             if lbuf <> Bigarray.Array1.dim outbuf then
               invalid_arg "decrypt: output buffer must have same size \
                            as input buffer";
             if lbuf mod bs <> 0 then
               invalid_arg (sprintf "decrypt: buffers must be multiples \
                                     of %d" bs);
             let c = get_ctx() in
             nettle_gcm_aes_decrypt c lbuf outbuf inbuf;
             true in
           let mac() =
             let c = get_ctx() in
             let s = Bytes.make 16 'X' in
             nettle_gcm_aes_digest c s;
             Bytes.to_string s in
           { set_iv;
             set_header;
             encrypt;
             decrypt;
             mac;
           } in
         { name;
           mode;
           key_lengths;
           iv_lengths;
           block_constraint = bs;
           supports_aead = true;
           create;
         }
      )
      nettle_gcm_aes_props

  (* The ciphers we access via the GnuTLS API. These are all CBC or GCM.
     GnuTLS has sometimes ways to accelerate the cipher, so prefer this.

     This is optional.
   *)

  let iv_16 = [ 16, 16 ]
  let iv_8 = [ 8, 8 ]

  let gnutls_basic_props =
    if net_have_crypto() then
      [ "AES-128-CBC", ("AES-128", "CBC", [ 16, 16 ], iv_16, 16);
        "AES-192-CBC", ("AES-192", "CBC", [ 24, 24 ], iv_16, 16);
        "AES-256-CBC", ("AES-256", "CBC", [ 32, 32 ], iv_16, 16);
        "CAMELLIA-128-CBC", ("CAMELLIA-128", "CBC", [ 16, 16 ], iv_16, 16);
        "CAMELLIA-128-GCM", ("CAMELLIA-128", "GCM", [ 16, 16 ], iv_gcm, 1);
        "CAMELLIA-192-CBC", ("CAMELLIA-192", "CBC", [ 24, 24 ], iv_16, 16);
        "CAMELLIA-192-GCM", ("CAMELLIA-192", "GCM", [ 24, 24 ], iv_gcm, 1);
        "CAMELLIA-256-CBC", ("CAMELLIA-256", "CBC", [ 32, 32 ], iv_16, 16);
        "CAMELLIA-256-GCM", ("CAMELLIA-256", "GCM", [ 32, 32 ], iv_gcm, 1);
        "DES-CBC", ("DES-56", "CBC", [ 8, 8 ], iv_8, 8);
        "3DES-CBC", ("3DES-112", "CBC", [ 24, 24 ], iv_8, 8);
        "SALSA20-256", ("SALSA20-256", "STREAM", [ 32, 32 ], iv_8, 1);
      ]
    else
      []

  let gnutls_basic_props_m =
    of_list gnutls_basic_props

  let gnutls_basic_ciphers =
    let l = gnutls_cipher_list() in
    filter_map
      (fun algo ->
         let gname = gnutls_cipher_get_name algo in
         let (name,mode,key_lengths,iv_lengths,dc) = 
           StrMap.find gname gnutls_basic_props_m in
         let create key =
           let lkey = String.length key in
           check_key lkey key_lengths;
           let ctx = ref None in
           let iv = ref "" in
           let hdr = ref "" in
           let set_iv s =
             check_iv (String.length s) iv_lengths;
             iv := s in
           let set_header s =
             hdr := s in
           let get_ctx() =
             match !ctx with
               | None ->
                    let c = gnutls_cipher_init algo key !iv in
                    if mode = "GCM" then
                      gnutls_cipher_add_auth c (Bytes.of_string !hdr);
                    ctx := Some c;
                    c
               | Some c ->
                    c in
           let encrypt inbuf outbuf =
             let lbuf = Bigarray.Array1.dim inbuf in
             if lbuf <> Bigarray.Array1.dim outbuf then
               invalid_arg "encrypt: output buffer must have same size \
                            as input buffer";
             if lbuf mod dc <> 0 then
               invalid_arg (sprintf "encrypt: buffers must be multiples \
                                     of %d" dc);
             let c = get_ctx() in
             gnutls_cipher_encrypt2 c inbuf outbuf in
           let decrypt inbuf outbuf =
             let lbuf = Bigarray.Array1.dim inbuf in
             if lbuf <> Bigarray.Array1.dim outbuf then
               invalid_arg "decrypt: output buffer must have same size \
                            as input buffer";
             if lbuf mod dc <> 0 then
               invalid_arg (sprintf "decrypt: buffers must be multiples \
                                     of %d" dc);
             let c = get_ctx() in
             try
               gnutls_cipher_decrypt2 c inbuf outbuf;
               true
             with _ -> false in
           let mac() =
             match mode with
               | "GCM" ->
                    let c = get_ctx() in
                    let s = Bytes.create 16 in
                    gnutls_cipher_tag c s;
                    Bytes.to_string s
               | _ ->
                    no_mac() in
           { set_iv;
             set_header;
             encrypt;
             decrypt;
             mac;
           } in
         { name;
           mode;
           key_lengths;
           iv_lengths;
           block_constraint = dc;
           supports_aead = (mode = "GCM");
           create;
         }
      )
      l


  include Netsys_crypto_modes.Bundle(struct
                                      (* later defs override earlier defs *)
                                      let ciphers =
                                        nettle_basic_ciphers @
                                          nettle_gcm_aes_ciphers @
                                            gnutls_basic_ciphers
                                    end)
end


module Symmetric_crypto =
  Netsys_crypto_modes.Add_modes(Basic_symmetric_crypto)


module Digests : Netsys_crypto_types.DIGESTS = struct
  open Nettls_nettle_bindings

  type digest_ctx =
      { add : Netsys_types.memory -> unit;
        finish : unit -> string
      }

  type digest =
      { name : string;
        size : int;
        block_length : int;
        create : unit -> digest_ctx;
      }


  let props =
    [ "md2",        ( "MD2-128", 16, 16 );
      "md4",        ( "MD4-128", 16, 64 );
      "md5",        ( "MD5-128", 16, 64 );
      "sha1",       ( "SHA1-160", 20, 64 );
      "sha256",     ( "SHA2-256", 32, 64 );
      "sha224",     ( "SHA2-224", 28, 64 );
      "sha384",     ( "SHA2-384", 48, 128 );
      "sha512",     ( "SHA2-512", 64, 128 );
      "sha3_256",   ( "SHA3-256", 32, 136 );
      "sha3_224",   ( "SHA3-224", 28, 144 );
      "sha3_384",   ( "SHA3-384", 48, 104 );
      "sha3_512",   ( "SHA3-512", 64, 72 );
      "ripemd160",  ( "RIPEMD-160", 20, 64 );
      "gosthash94", ( "GOSTHASH94-256", 32, 32 );
    ]

  let props_m =
    of_list props

  let digests =
    filter_map
      (fun h ->
         let (name,size,blocklen) = 
           StrMap.find (net_nettle_hash_name h) props_m in
         let create() =
           let ctx = net_nettle_create_hash_ctx h in
           let () = net_nettle_hash_init h ctx in
           let add mem =
             net_nettle_hash_update h ctx mem in
           let finish() =
             let s = Bytes.make size 'X' in
             net_nettle_hash_digest h ctx s;
             Bytes.to_string s in
           { add; finish } in
         { name;
           size;
           block_length = blocklen;
           create
         }
      )
      (Array.to_list (net_nettle_hashes()))

  let digests_m =
    of_list (List.map (fun dg -> dg.name, dg) digests)

  let find name = StrMap.find name digests_m
  let name dg = dg.name
  let size dg = dg.size
  let block_length dg = dg.block_length
  let create dg = dg.create()
  let add ctx mem = ctx.add mem
  let finish ctx = ctx.finish()

end


module Pubkey_crypto : Netsys_crypto_types.PUBKEY_CRYPTO = struct
  module G = Nettls_gnutls_bindings
  module X = Netx509_pubkey
  type oid = Netoid.t
  type public_key = Netx509_pubkey.pubkey * G.gnutls_pubkey_t
  type private_key = string * G.gnutls_privkey_t
  type hash = [ `SHA_1 | `SHA_224 | `SHA_256 | `SHA_384 | `SHA_512 ]
  type algorithm =
    | Encrypt of oid
    | Sign of oid * hash
  type x509_private_key = string * string
  type pin_callback = unit


  let trans_exn f arg =
    try
      f arg
    with
      | G.Error code ->
          failwith (G.gnutls_strerror_name code)

  let supported_x509_encrypt =
    (* Generally assume that we support RSA without checking it *)
    if G.net_have_pubkey() then
      List.map
        (fun (X.Encrypt(oid,_)) -> oid)
        [ X.Encryption.rsa
        ]
    else
      []

  let catalog_hashes =
    (* maps our name to GnuTLS name *)
    [ `SHA_1,   "SHA1";
      `SHA_224, "SHA224";
      `SHA_256, "SHA256";
      `SHA_384, "SHA384";
      `SHA_512, "SHA512"
    ]

  let hash_set =
    (* hashes supported by GnuTLS *)
    List.fold_right 
      StrSet.add 
      (List.map G.gnutls_mac_get_name (G.gnutls_mac_list()))
      StrSet.empty

  let catalog_x509_sign =
    (* catalog (oid, our hash name, GnuTLS name) *)
    List.map
      (fun (X.Sign(oid,_), hash, gnutls_name) -> (oid, hash, gnutls_name))
      [ X.Signing.rsa_with_sha1,     `SHA_1,   "RSA-SHA1";
        X.Signing.rsa_with_sha224,   `SHA_224, "RSA-SHA224";
        X.Signing.rsa_with_sha256,   `SHA_256, "RSA-SHA256";
        X.Signing.rsa_with_sha384,   `SHA_384, "RSA-SHA384";
        X.Signing.rsa_with_sha512,   `SHA_512, "RSA-SHA512";
        X.Signing.dsa_with_sha1,     `SHA_1,   "DSA-SHA1";
        X.Signing.dsa_with_sha224,   `SHA_224, "DSA-SHA224";
        X.Signing.dsa_with_sha256,   `SHA_256, "DSA-SHA256";
        X.Signing.ecdsa_with_sha1,   `SHA_1,   "ECDSA-SHA1";
        X.Signing.ecdsa_with_sha224, `SHA_224, "ECDSA-SHA224";
        X.Signing.ecdsa_with_sha256, `SHA_256, "ECDSA-SHA256";
        X.Signing.ecdsa_with_sha384, `SHA_384, "ECDSA-SHA384";
        X.Signing.ecdsa_with_sha512, `SHA_512, "ECDSA-SHA512";
      ]

  let sign_set =
    (* sign algs supported by GnuTLS *)
    List.fold_right
      StrSet.add
      (List.map G.gnutls_sign_get_name (G.gnutls_sign_list()))
      StrSet.empty

  let sign_name_of_oid =
    (* map OID of sign alg to GnuTLS name *)
    List.fold_right
      (fun (oid,_,name) acc ->
         if StrSet.mem name sign_set then
           OIDMap.add oid name acc
         else
           acc
      )
      catalog_x509_sign
      OIDMap.empty

  let supported_x509_sign =
    if G.net_have_pubkey() then
      let slist =
        List.filter
          (fun (_,_,gnutls_name) ->
           StrSet.mem gnutls_name sign_set
          )
          catalog_x509_sign in
      List.map (fun (oid,hash,_) -> oid,hash) slist
    else
      []

  let supported_x509 =
    if G.net_have_pubkey() then
      supported_x509_encrypt
      @ List.map (fun (oid,_) -> oid) supported_x509_sign
    else
      []

  let algorithm_x509 oid params =
    if List.mem oid supported_x509_encrypt then
      Encrypt oid
    else
      try
        let h = List.assoc oid supported_x509_sign in
        Sign(oid, h)
      with
        | Not_found ->
            failwith "Nettls_gnutls.Pubkey_crypto.algorith_x509: no such alg"

  let import_public_key_x509 s =
    let netpub = Netx509_pubkey.decode_pubkey_from_der s in
    let pub = G.gnutls_pubkey_init() in
    trans_exn (G.gnutls_pubkey_import pub s) `Der;
    (netpub,pub)

  let import_public_key_uri s =
    failwith "Nettls_gnutls.Pubkey_crypto.import_public_key_uri: \
              not implemented"
(*
    let pub = G.gnutls_pubkey_init() in
    G.gnutls_pubkey_import_url pub s 0;
    pub
 *)

  let import_public_key_uri_with_pin cb s =
    failwith "Nettls_gnutls.Pubkey_crypto.import_public_key_uri_with_pin: \
              not implemented"

  let import_private_key_uri s =
    failwith "Nettls_gnutls.Pubkey_crypto.import_private_key_uri: \
              not implemented"

  let import_private_key_uri_with_pin cb s =
    failwith "Nettls_gnutls.Pubkey_crypto.import_private_key_uri_with_pin: \
              not implemented"
             
  let import_private_key_x509 (format, s) =
    let pem = create_pem (format ^ " PRIVATE KEY") s in
    let priv1 = G.gnutls_x509_privkey_init() in
    trans_exn (G.gnutls_x509_privkey_import priv1 pem) `Pem;
    let priv2 = G.gnutls_privkey_init() in
    trans_exn (G.gnutls_privkey_import_x509 priv2 priv1) 0;
    (format,priv2)
        
  let import_public_key_from_private priv =
    assert false   (* TODO *)
(*
    let pub = G.gnutls_pubkey_init() in
    G.gnutls_pubkey_import_privkey pub priv 0 0;
    pub
 *)

  let simple_pin_callback _ = ()

  let privkey_format_of_encalg oid =
    X.Key.private_key_format_of_key
      (X.Encryption.key_oid_of_encrypt_alg
         (X.Encrypt(oid,None)))

  let privkey_format_of_signalg oid =
    X.Key.private_key_format_of_key
      (X.Signing.key_oid_of_sign_alg
         (X.Sign(oid,None)))


  let encrypt alg (netpub,pub) data =
    let X.Alg_id(puboid,_) = X.(netpub.pubkey_type) in
    match alg with
      | Encrypt oid ->
          let expected_puboid = 
            X.Encryption.key_oid_of_encrypt_alg (X.Encrypt(oid,None)) in
          if expected_puboid <> puboid then
            failwith "Nettls_gnutls.Pubkey_crypto.encrypt: algorithm cannot \
                      be applied to key";
          G.gnutls_pubkey_encrypt_data pub 0 data
      | _ ->
          failwith "Nettls_gnutls.Pubkey_crypto.encrypt: not an encryption \
                    algorithm"

  let decrypt alg (format,priv) data =
    match alg with
      | Encrypt oid ->
          let expected_format = privkey_format_of_encalg oid in
          if format <> expected_format then
            failwith "Nettls_gnutls.Pubkey_crypto.decrypt: algorithm cannot \
                      be applied to key";
          G.gnutls_privkey_decrypt_data priv 0 data
      | _ ->
          failwith "Nettls_gnutls.Pubkey_crypto.decrypt: not an encryption \
                    algorithm"

  let verify alg (netpub,pub) plaintext signature =
    let X.Alg_id(puboid,_) = X.(netpub.pubkey_type) in
    match alg with
      | Sign(oid,_) ->
          let expected_puboid =
            X.Signing.key_oid_of_sign_alg (X.Sign(oid,None)) in
          if expected_puboid <> puboid then
            failwith "Nettls_gnutls.Pubkey_crypto.verify: algorithm cannot \
                      be applied to key";
          let gnutls_name =
            try OIDMap.find oid sign_name_of_oid
            with Not_found ->
              failwith "Nettls_gnutls.Pubkey_crypto.verify: algorithm \
                        not supported" in
          let gnutls_alg =
            G.gnutls_sign_get_id gnutls_name in
          ( try
              G.gnutls_pubkey_verify_data2 pub gnutls_alg 0 plaintext signature;
              true
            with
              | G.Error _ ->
                  false
          )
      | _ ->
          failwith "Nettls_gnutls.Pubkey_crypto.verify: not a signing \
                    algorithm"

  let sign alg (format,priv) data =
    match alg with
      | Sign(oid,hash) ->
          let expected_format = privkey_format_of_signalg oid in
          if format <> expected_format then
            failwith "Nettls_gnutls.Pubkey_crypto.sign: algorithm cannot \
                      be applied to key";
          let gnutls_hash_name =
            List.assoc hash catalog_hashes in
          if not (StrSet.mem gnutls_hash_name hash_set) then
            failwith "Nettls_gnutls.Pubkey_crypto.sign: algorithm not \
                      supported";
          let gnutls_hash =
            G.gnutls_mac_get_id gnutls_hash_name in
          G.gnutls_privkey_sign_data priv gnutls_hash 0 data
      | _ ->
          failwith "Nettls_gnutls.Pubkey_crypto.sign: not a signing \
                    algorithm"


end


(* Initialization of GnuTLS: This is done when the first wrapper function
   is invoked via nettls_init(). Note that (since around GnuTLS-3.2) the
   file /dev/random is permanently kept open. If this is in the way,
   you can call nettls_deinit. (NB. This scheme is somewhat fragile,
   as it breaks when there is another user of GnuTLS keeping the library
   initialized.)
 *)

let init() =
  Netsys_crypto.set_current_tls
    (module TLS : Netsys_crypto_types.TLS_PROVIDER);
  Netsys_crypto.set_current_symmetric_crypto
    (module Symmetric_crypto : Netsys_crypto_types.SYMMETRIC_CRYPTO);
  Netsys_crypto.set_current_digests
    (module Digests : Netsys_crypto_types.DIGESTS);
  Netsys_crypto.set_current_pubkey_crypto
    (module Pubkey_crypto : Netsys_crypto_types.PUBKEY_CRYPTO);
  Netsys_posix.register_post_fork_handler
    ( object
        method name = "nettls_deinit"
        method run() = 
          Nettls_gnutls_bindings.nettls_deinit()
      end
    )

let () =
  init()
