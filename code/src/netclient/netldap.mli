(* $Id$ *)

(** {2 Error handling} *)

type result_code =
  [ `Success
  | `OperationsError
  | `ProtocolError
  | `TimeLimitExceeded
  | `SizeLimitExceeded
  | `CompareFalse
  | `CompareTrue
  | `AuthMethodNotSupported
  | `StrongAuthRequired
  | `Referral
  | `AdminLimitExceeded
  | `UnavailableCriticalExtension
  | `ConfidentialityRequired
  | `SaslBindInProgress
  | `NoSuchAttribute
  | `UndefinedAttributeType
  | `InappropriateMatching
  | `ConstraintViolation
  | `AttributeOrValueExists
  | `InvalidAttributeSyntax
  | `NoSuchObject
  | `AliasProblem
  | `InvalidDNSyntax
  | `AliasDereferencingProblem
  | `InappropriateAuthentication
  | `InvalidCredentials
  | `InsufficientAccessRights
  | `Busy
  | `Unavailable
  | `UnwillingToPerform
  | `LoopDetect
  | `NamingViolation
  | `ObjectClassViolation
  | `NotAllowedOnNonLeaf
  | `NotAllowedOnRDN
  | `EntryAlreadyExists
  | `ObjectClassModsProhibited
  | `AffectsMultipleDSAs
  | `Other
  | `Unknown_code of int
  ]

exception Timeout
exception LDAP_error of result_code * string
exception Auth_error of string

(** {2 Specifying the LDAP server} *)

class type ldap_server =
object
  method ldap_endpoint : Netsockaddr.socksymbol
  method ldap_timeout : float
  method ldap_peer_name : string option
  method ldap_tls_config : (module Netsys_crypto_types.TLS_CONFIG) option
end

val ldap_server : ?timeout:float ->
                  ?peer_name:string ->
                  ?tls_config:(module Netsys_crypto_types.TLS_CONFIG) ->
                  ?tls_enable:bool ->
                  Netsockaddr.socksymbol -> ldap_server

(** {2 Specifying LDAP credentials} *)

type bind_creds

val simple_bind_creds : dn:string -> pw:string -> bind_creds
val sasl_bind_creds : dn:string -> user:string -> authz:string ->
                       creds:(string * string * (string * string)list)list ->
                       params:(string * string * bool) list ->
                       (module Netsys_sasl_types.SASL_MECHANISM) ->
                       bind_creds

(** {2 LDAP connections} *)

type ldap_connection

val connect_e :
      ?proxy:#Uq_engines.client_endpoint_connector ->
      ldap_server -> Unixqueue.event_system -> 
      ldap_connection Uq_engines.engine
val connect : 
      ?proxy:#Uq_engines.client_endpoint_connector ->
      ldap_server -> ldap_connection

val close_e : ldap_connection -> unit Uq_engines.engine
val close : ldap_connection -> unit
val abort : ldap_connection -> unit

val conn_bind_e : ldap_connection -> bind_creds -> unit Uq_engines.engine
val conn_bind : ldap_connection -> bind_creds -> unit

(** {2 LDAP results} *)

(** A class type for encapsulating results *)
class type ['a] ldap_result =
  object
    method code : result_code
      (** The code, [`Success] on success *)
    method matched_dn : string
      (** The matchedDN field sent with some codes *)
    method diag_msg : string
      (** diagnostic message *)
    method referral : string list
      (** if non-empty, a list of URIs where to find more results *)
    method value : 'a
      (** the value when [code=`Success]. Raises [LDAP_error] for other
          codes *)
    method partial_value : 'a
      (** the value so far available, independently of the code *)
  end

exception Notification of string ldap_result
  (** An unsolicited notification. The string is the OID. Best reaction is
      to terminate the connection.
   *)


(** {2 LDAP searches} *)

type scope = [ `Base | `One | `Sub ]
  (** The scope of the search:
       - [`Base]: only the base object
       - [`One]: only the direct children of the base object
       - [`Sub]: the base object and all direct and indirect children
   *)

type deref_aliases = [ `Never | `In_searching | `Finding_base_obj | `Always ]
  (** What to do when aliases (server-dereferenced symbolic links) are found
      in the tree:
       - [`Never]: do not dereference aliases but return them as part of the
         search result
       - [`In_searching]: when aliases are found in the children of the base
         object dereference the aliases, and continue the search there, and
         repeat this recursively if needed
       - [`Finding_base_obj]: dereference alises in base objects but not in
         children
       - [`Always]: always dereference aliases
   *)

type filter = 
  [ `And of filter list
  | `Or of filter list
  | `Not of filter
  | `Equality_match of string * string
  | `Substrings of string * string option * string list * string option
  | `Greater_or_equal of string * string
  | `Less_or_equal of string * string
  | `Present of string
  | `Approx_match of string * string
  | `Extensible_match of string option * string option * string * bool
  ]
  (** Filter:
       - [`Equality_match(attr_descr, value)]
       - [`Substrings(attr_descr, prefix_match, substring_matches, suffix_match)]
       - [`Greater_or_equal(attr_descr,value)]
       - [`Less_or_equal(attr_descr,value)]
       - [`Present(attr_descr)]
       - [`Approx_match(attr_descr,value)]
       - [`Extensible_match(matching_rule_id, attr_descr, value, dn_attrs)]

     Here, [attr_descr] is the name of the attribute, either given by
     an OID (in dotted representation) or a by a descriptive name. There
     can be options, separated from the name by a semicolon.

     The [value] is the value to filter with (an UTF-8 string).
   *)

type search_result =
  [ `Entry of string * (string * string list) list
  | `Reference of string list
  ]
  (** Search results are either entries or references:
       - [`Entry(object_dn, [(attr_descr, values); ...])]
       - [`Reference urls]: The entry is not present on this server but can
         be looked up by following one of the [urls]
   *)

val search_e : ldap_connection ->
               base:string ->
               scope:scope ->
               deref_aliases:deref_aliases ->
               size_limit:int ->
               time_limit:int ->
               types_only:bool ->
               filter:filter ->
               attributes:string list ->
               unit ->
               search_result list ldap_result Uq_engines.engine
  (** Run the specified search: Search at [base] according to [scope] for
      entries matching the [filter] and return their [attributes].

      If the [base] object is not present on the server but somewhere else
      (redirection) the result will be empty and the referral is set in the
      response. If children
      of the base object are redirected to another server, the result will
      contain [`Reference] elements. 

      Note that [time_limit] is a server-enforced limit (in seconds; 0 for
      no limit). Independently of that
      this client employs the timeout set in the [ldap_connection]. This timeout
      limits the time between two consecutive server messages.

      The [size_limit] limits the number of returned entries (0 for no limit).

      If [types_only] there will not be values in the result (instead, empty
      lists are returned).

      A [filter] is mandatory. If you want to get all results, specify a
      useless filter like [`Present("objectclass")].

      If you pass an empty [attributes] list, no attributes will be
      returned.  In order to get all attributes, pass the list
      [["*"]]. The asterisk can also be appended to a non-empty list
      to get all remaining attributes in any order.
  *)

val search : ldap_connection ->
               base:string ->
               scope:scope ->
               deref_aliases:deref_aliases ->
               size_limit:int ->
               time_limit:int ->
               types_only:bool ->
               filter:filter ->
               attributes:string list ->
               unit ->
               search_result list ldap_result

(** {2 LDAP routines} *)

val test_bind_e : ?proxy:#Uq_engines.client_endpoint_connector ->
                  ldap_server -> bind_creds -> 
                  Unixqueue.event_system -> bool Uq_engines.engine
val test_bind : ?proxy:#Uq_engines.client_endpoint_connector ->
                ldap_server -> bind_creds -> bool

(*
val retr_password_e : dn:string -> ldap_server -> bind_creds ->
                      (string * string * (string * string) list) list engine
val retr_password : dn:string -> ldap_server -> bind_creds ->
                      (string * string * (string * string) list) list
*)


(** {1 Debugging} *)

module Debug : sig
  val enable : bool ref
    (** Enables {!Netlog}-style debugging of this module *)
end
