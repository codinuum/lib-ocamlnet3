(* $Id$ *)

external s_read_int4_64_unsafe : string -> int -> int
  = "netsys_s_read_int4_64" "noalloc"

external s_write_int4_64_unsafe : string -> int -> int -> unit
  = "netsys_s_write_int4_64" "noalloc"