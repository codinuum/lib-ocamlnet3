(* $Id$ *)

(** Controller *)

(** The controller is the main part of the Netplex system that starts and
  * stop the individual service containers.
 *)

open Netplex_types

val create_controller : parallelizer -> controller_config -> controller

val extract_config : 
  logger_factory list -> config_file -> controller_config