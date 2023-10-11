(* Generator for library stubs

   For examples, see nettls-gnutls and netgss-system.

   ----------------------------------------------------------------------
   Declaration of functions:
   ----------------------------------------------------------------------

   let functions = [ decl1; decl2; ... ]

   Every declaration is a triple (name, parameters, directives).
   Parameters: a list of triples (name, kind, type).

   Parameter kinds: Input parameters appear in the argument list of the
   OCaml binding. Output parameter appear in the result tuple.

    - `In: the parameter is an input
    - `In_ptr: same, but passed as pointer
    - `In_ignore: the parameter is an input. The OCaml interface omits it.
    - `Out: the parameter is an output. The C function gets only a pointer
       to a value of [type], and needs to initialize it.
    - `Out_ignore: the parameter is an output, but is omitted in the OCaml
       interface.
    - `Out_noptr: the parameter is an output. In this variant, the C function
       gets the value of [type] directly (no pointer), and modifies its
       contents.
    - `In_out: the parameter is an input and an output. The C function gets
       a pointer to a value of [type]
    - `In_out_noptr: the parameter is an input and an output. No pointer
       here.
    - `Return: the return value of the C function. Appears in the result
       tuple of the OCaml binding.
    - `Return_ignore: the return value of the C function, omitted in the
       OCaml binding.

  The type may be one of the following:

   type                   C mapping           OCaml mapping
   ------------------------------------------------------------
   void                   void                unit
   int                    int                 int
   uint                   unsigned int        int
   int32                  int32_t             int32
   uint32                 int32_t             int32
   bool                   int                 bool
   ubool                  unsigned int        bool
   double                 double              float
   file_descr             int                 Unix.file_descr

   ztstr                  char *              string
     (zero-terminated string)

   t ztlist               map(t) *            map(t) list
     (zero-terminated list of pointers; t may be any type)

   t array                map(t) *            map(t) array
     (array of pointers; t may be any type)

   pname array_size       size_t              int
     (must be used in conjuction with a "t array" parameter, and the name
      of this other parameter must be specified as pname)

   pname array_size_uint  unsigned int        int
     (must be used in conjuction with a "t array" parameter, and the name
      of this other parameter must be specified as paramname)

   id bigarray            void *              Netsys_mem.memory   
     (the id is an arbitrary identifier)

   id bigarray_size       size_t              int
     (must be used in conjunction with "bigarray", same id)

   id stringbuf           void *              bytes
     (the id is an arbitrary identifier)

   id stringbuf_size      size_t              int
     (must be used in conjunction with "stringbuf", same id)

   id ztstringbuf         void *              bytes
     (zero-terminated; the id is an arbitrary identifier)

   id ztstringbuf_size    size_t              int
     (must be used in conjunction with "stringbuf", same id)


   Also, you can use the special notation

     t1/t2

   meaning that t1 is used on the C side, but it has the same properties
   as t2, and t2 is also used for the OCaml mapping.

   All other type names: It is expected that a type wrapper is defined
   for the type. See next section.


   DIRECTIVES:

   - `Optional: the function is only optionally available. A macro
     HAVE_FUN_<name> is tested.

   - `Declare "decl": This C declaration is added to the declarations
     in the generated stub function.

   - `Pre "stm": This C statement is emitted just before the wrapped
     function is called.

   - `Post "stm": This C statement is emitted after the wrapped
     function is called.

   - `GNUTLS_ask_for_size: special feature for GNUTLS



   ----------------------------------------------------------------------
   Declaration of type wrappers:
   ----------------------------------------------------------------------

   let types = [ (name1, decl1); (name2, decl2); ... ]

   Possible declarations:

   - `Manual "type name = something"

     just add the type definition to the ml code. Do nothing on the C side.
     The user has to manually write the wrapper helpers (when t is the type
     name):

     static t     unwrap_t(value);
     static value wrap_t(t);

   - abstract_ptr "free_function"

     Generates wrapper helpers for a pointer-like type. The user must write
     a C function that releases memory:

     static void free_function(t);

   - tagged_abstract_ptr "free_function2"

     Generates wrapper helpers for a pointer-like type. The user must write
     a C function that releases memory:

     static void free_function2(long,t);

     In this variant, the free function gets a long as first argument, the
     tag. The tag will be 0 for all values that are wrapped by wrap_t, i.e.
     for all wrapped values returned by C code. Other tag values can be
     defined by the user. The generator also emits code for

     static value twrap_t(long,t);

     which sets the tag to the passed long. The idea is to memoize in the tag
     how the value was once allocated, and use the right method for
     deallocation.

   - `Abstract_enum

     XXX

   - `Enum cases

     This is for an enumerator type (either an "enum", or a simulated enum
     declared as integer where the cases are available as macros). The
     cases are given as a list [ "value1"; "value2"; ... ].

     A few special notations are understood:

     VERTICAL BAR:  "PREFIX|SUFFIX". In C the value is known as "PREFIXSUFFIX".
                    The OCaml version uses only "SUFFIX".

     QUESTION MARK: "?VALUE". The value is only optionally available.
                    (Dependent on a macro HAVE_ENUM_ plus the value name)

   - `Flags flags

     Flags that are bitwise OR-ed. The flags are given as list
     [ "value1"; "value2"; ... ].

     Works very much like `Enum.

   - `Same_as "other_type"

     Treat this type as an alias for another type.


   ----------------------------------------------------------------------
   Generating
   ----------------------------------------------------------------------

   Call the generator as

   generate
     ~c_file:"helpers.c"
     ~ml_file:"helpers.ml"
     ~mli_file:"helpers.mli"
     ~optional_functions: [ "fun1"; "fun2"; ... ]
     ~optional_types: [ "t1"; "t2"; ... ]
     ~enum_of_string: [ "t1"; "t2"; ... ]
     ~modname:"modulename"
     ~types       (* type wrappers, see above *)
     ~functions   (* functions, see above *)
     ~free: [ "t1"; "t2"; ... ]
     ~init: [ "t1"; "t2"; ... ]
     ~hashes: [ "h1"; "h2"; ... ]
     ()

  The generated code will go into:

    - modulename.ml
    - modulename.mli
    - modulename_stubs.c

  Also, a shell script config_checks.sh is generated: For every optional
  function, optional type, or optional value a shell function is called.
  The user is expected to define this shell function.

  optional_functions: Additional functions to check for.

  optional_types: additional types to check for.

  enum_of_string: For `Enum types, additional functions are generated
  that map the enum values to and from strings.


  free: If a type is listed here, and there is an input or in/out parameter
  of this type, the generator will emit the code

  free_<t>(value)

  after calling the wrapped function.


  init: If a type is listed here, and there is an output-only parameter of this
  type (i.e. not in/out), the generator will emit the code

  init_<t>(&variable)

  before calling the wrapped function.

 *)


#directory "+compiler-libs"
(* only for Btype.hash_variant *)

#load "str.cma"
#load "ocamlcommon.cma"

open Printf

let p1_re = Str.regexp "^\\(.*\\)(\\(.*\\))"
let p2_re = Str.regexp "[ \t]*,[ \t]*"
let p3_re = Str.regexp "[ \t]+"

let parse decl =
  (* Parsing helper, optional *)
  try
    if Str.string_match p1_re decl 0 then (
      let part1 = Str.matched_group 1 decl in
      let part2 = Str.matched_group 2 decl in
      let result_name = Str.split p3_re part1 in
      let params =
        List.map
          (fun param_s ->
             let l = Str.split p3_re param_s in
             let tag, l1 =
               match l with
                 | "IN" :: l1 -> (`In, l1)
                 | "IN_PTR" :: l1 -> (`In_ptr, l1)
                 | "IN_IGNORE" :: l1 -> (`In_ignore, l1)
                 | "IN_OUT" :: l1 -> (`In_out, l1)
                 | "OUT" :: l1 -> (`Out, l1)
                 | "OUT_IGNORE" :: l1 -> (`Out_ignore, l1)
                 | "OUT_NOPTR" :: l1 -> (`Out_noptr, l1)
                 | _ -> (`In, l) in
             let n = List.hd (List.rev l1) in
             let ty = List.rev (List.tl (List.rev l1)) in
             (n, tag, String.concat " " ty)
          )
          (Str.split p2_re part2) in
      let name = List.hd (List.rev result_name) in
      let result = List.rev (List.tl (List.rev result_name)) in
      (name, String.concat " " result, params)
    )
    else raise Not_found
  with
    | Not_found ->
         failwith ("Parse error: " ^ decl)


let has_prefix ~prefix s =
  let l1 = String.length s in
  let l2 = String.length prefix in
  l2 <= l1 && String.sub s 0 l2 = prefix


type abs_ptr =
    { abs_free_fn : [`Untagged of string | `Tagged of string ];
      abs_nullok : bool;
      abs_gen_set : bool;
    }

let abstract_ptr ?(nullok=false) ?(gen_set=false) abs_free_fn =
  `Abstract_ptr { abs_free_fn = `Untagged abs_free_fn; 
                  abs_nullok = nullok;
                  abs_gen_set = gen_set }

let tagged_abstract_ptr ?(nullok=false) ?(gen_set=false) abs_free_fn =
  `Abstract_ptr { abs_free_fn = `Tagged abs_free_fn; 
                  abs_nullok = nullok;
                  abs_gen_set = gen_set }


(**********************************************************************)
(* Abstract_enum                                                      *)
(**********************************************************************)

let gen_abstract_enum c mli ml tyname ~optional =
  fprintf mli "type %s\n" tyname;
  fprintf ml "type %s\n" tyname;

  fprintf c "/************** %s *************/\n\n" tyname;
  if optional then
    fprintf c "#ifdef HAVE_TY_%s\n" tyname;
  fprintf c "struct enumstruct_%s { %s value; long oid; };\n\n" tyname tyname;
  fprintf c "#define enumstructptr_%s_val(v) \
             ((struct enumstruct_%s *) (Data_custom_val(v)))\n" tyname tyname;
  fprintf c "#define enum_%s_unwrap(v) \
             (enumstructptr_%s_val(v)->value)\n" tyname tyname;
  fprintf c "long enum_%s_oid = 0;\n" tyname;

  fprintf c "\n";
  fprintf c "static int enum_%s_compare(value v1, value v2) {\n" tyname;
  fprintf c "  struct enumstruct_%s *p1;\n" tyname;
  fprintf c "  struct enumstruct_%s *p2;\n" tyname;
  fprintf c "  p1 = enumstructptr_%s_val(v1);\n" tyname;
  fprintf c "  p2 = enumstructptr_%s_val(v2);\n" tyname;
  fprintf c "  return p1->oid - p2->oid;\n";
  fprintf c "}\n\n";

  fprintf c "static struct custom_operations enum_%s_ops = {\n" tyname;
  fprintf c "  \"\",\n";
  fprintf c "  custom_finalize_default,\n";
  fprintf c "  enum_%s_compare,\n" tyname;
  fprintf c "  custom_hash_default,\n";
  fprintf c "  custom_serialize_default,\n";
  fprintf c "  custom_deserialize_default\n";
  fprintf c "};\n\n";

  fprintf c "static %s unwrap_%s(value v) {\n" tyname tyname;
  fprintf c "  return enum_%s_unwrap(v);\n" tyname;
  fprintf c "}\n\n";

  fprintf c "static value wrap_%s(%s x) {\n" tyname tyname;
  fprintf c "  value v;\n";
  fprintf c "  v = caml_alloc_custom(&enum_%s_ops, \
                                     sizeof(struct enumstruct_%s), 0, 1);\n"
         tyname tyname;
  fprintf c "  enumstructptr_%s_val(v)->value = x;\n" tyname;
  fprintf c "  enumstructptr_%s_val(v)->oid = enum_%s_oid++;\n" tyname tyname;
  fprintf c "  return v;\n";
  fprintf c "}\n";

  if optional then
    fprintf c "#endif\n";

  fprintf c "\n";

  ()

(**********************************************************************)
(* Abstract_ptr                                                       *)
(**********************************************************************)

(* Here we allocate a pair

   (tag, custom, list)

   where custom is the custom block, and list is a list of
   auxiliary values whose lifetime must exceed the custom block.

   tag is an optional integer, usually 0. Especially, this allow to
   deallocate the custom in different ways.

 *)

let gen_abstract_ptr c mli ml tyname abs ~optional =
  fprintf mli "type %s\n" tyname;
  fprintf ml "type %s\n" tyname;

  fprintf c "/************** %s *************/\n\n" tyname;
  if optional then
    fprintf c "#ifdef HAVE_TY_%s\n" tyname;
  fprintf c "struct absstruct_%s { %s value; long tag; long oid; };\n\n"
             tyname tyname;
  fprintf c "#define absstructptr_%s_val(v) \
             ((struct absstruct_%s *) (Data_custom_val(v)))\n" tyname tyname;
  fprintf c "#define abs_%s_unwrap(v) \
             (absstructptr_%s_val(v)->value)\n" tyname tyname;
  fprintf c "#define abs_%s_tag(v) \
             (absstructptr_%s_val(v)->tag)\n" tyname tyname;
  fprintf c "long abs_%s_oid = 0;\n" tyname;

  fprintf c "\n";
  fprintf c "static int abs_%s_compare(value v1, value v2) {\n" tyname;
  fprintf c "  struct absstruct_%s *p1;\n" tyname;
  fprintf c "  struct absstruct_%s *p2;\n" tyname;
  fprintf c "  p1 = absstructptr_%s_val(v1);\n" tyname;
  fprintf c "  p2 = absstructptr_%s_val(v2);\n" tyname;
  fprintf c "  return p1->oid - p2->oid;\n";
  fprintf c "}\n\n";

  fprintf c "static void abs_%s_finalize(value v1) {\n" tyname;
  fprintf c "  struct absstruct_%s *p1;\n" tyname;
  fprintf c "  p1 = absstructptr_%s_val(v1);\n" tyname;
  ( match abs.abs_free_fn with
      | `Untagged free -> 
          fprintf c "  %s(p1->value);\n" free
      | `Tagged free ->
          fprintf c "  %s(p1->tag, p1->value);\n" free
  );
  fprintf c "}\n\n";

  fprintf c "static struct custom_operations abs_%s_ops = {\n" tyname;
  fprintf c "  \"\",\n";
  fprintf c "  abs_%s_finalize,\n" tyname;
  fprintf c "  abs_%s_compare,\n" tyname;
  fprintf c "  custom_hash_default,\n";
  fprintf c "  custom_serialize_default,\n";
  fprintf c "  custom_deserialize_default\n";
  fprintf c "};\n\n";

  fprintf c "static %s unwrap_%s(value v) {\n" tyname tyname;
  fprintf c "  %s r;\n" tyname;
  fprintf c "  r = abs_%s_unwrap(Field(v,0));\n" tyname;
  if not abs.abs_nullok then
    fprintf c "  if (r == NULL) raise_null_pointer();\n";
  fprintf c "  return r;\n";
  fprintf c "}\n\n";

  fprintf c "static long tag_%s(value v) {\n" tyname;
  fprintf c "  return abs_%s_tag(Field(v,0));\n" tyname;
  fprintf c "}\n\n";

  fprintf c "static value twrap_%s(long tag, %s x) {\n" tyname tyname;
  fprintf c "  CAMLparam0();\n";
  fprintf c "  CAMLlocal2(v,r);\n";
  if not abs.abs_nullok then
    fprintf c "  if (x == NULL) caml_failwith(\"wrap_%s: NULL pointer\");\n" tyname;
  fprintf c "  v = caml_alloc_custom(&abs_%s_ops, \
                                     sizeof(struct absstruct_%s), 0, 1);\n"
         tyname tyname;
  fprintf c "  absstructptr_%s_val(v)->tag = tag;\n" tyname;
  fprintf c "  absstructptr_%s_val(v)->value = x;\n" tyname;
  fprintf c "  absstructptr_%s_val(v)->oid = abs_%s_oid++;\n" tyname tyname;
  fprintf c "  r = caml_alloc(2,0);\n";
  fprintf c "  Field(r,0) = v;\n";
  fprintf c "  Field(r,1) = Val_int(0);\n";
  fprintf c "  CAMLreturn(r);\n";
  fprintf c "}\n\n";

  fprintf c "static value wrap_%s(%s x) {\n" tyname tyname;
  fprintf c "  return twrap_%s(0, x);\n" tyname;
  fprintf c "}\n\n";

  if abs.abs_gen_set then (
    fprintf c "static void set_%s(value v, %s x) {\n" tyname tyname;
    fprintf c "  absstructptr_%s_val(v)->value = x;\n" tyname;
    fprintf c "}\n\n";
  );

  fprintf c "static void attach_%s(value v, value aux) {\n" tyname;
  fprintf c "  CAMLparam2(v,aux);\n";
  fprintf c "  CAMLlocal1(h);\n";
  fprintf c "  h = caml_alloc(2,0);\n";
  fprintf c "  Field(h,0) = aux;\n";
  fprintf c "  Field(h,1) = Field(v,1);\n";
  fprintf c "  Store_field(v,1,h);\n";
  fprintf c "  CAMLreturn0;\n";
  fprintf c "}\n";

  if optional then
    fprintf c "#endif\n";

  fprintf c "\n";

  ()

(**********************************************************************)
(* Enum                                                               *)
(**********************************************************************)

let vert_re = Str.regexp "[|]"
let qmark_re = Str.regexp "[?]"

let c_name_of_enum n =
  Str.replace_first qmark_re ""
    (Str.replace_first vert_re "" n)

let ml_name_of_enum n0 =
  let n = Str.replace_first qmark_re "" n0 in
  try
    let l = String.length n in
    let p = String.index n '|' in
    String.capitalize_ascii (String.lowercase_ascii (String.sub n (p+1) (l-p-1)))
  with
    | Not_found ->
         String.capitalize_ascii (String.lowercase_ascii n)


let is_opt_case n =
  n.[0] = '?'


let gen_enum c mli ml tyname cases ~optional =
  List.iter
    (fun f ->
       fprintf f "type %s =\n" tyname;
       fprintf f "  [ ";
       let first = ref true in
       List.iter
         (fun case ->
            if not !first then fprintf f "  | ";
            first := false;
            fprintf f "`%s\n" (ml_name_of_enum case)
         )
         cases;
       fprintf f "  ]\n";
    )
    [ mli; ml ];

  fprintf c "/************** %s *************/\n\n" tyname;
  if optional then
    fprintf c "#ifdef HAVE_TY_%s\n" tyname;
  fprintf c "static value wrap_%s(%s x) {\n" tyname tyname;
  fprintf c "  switch (x) {\n";
  List.iter
    (fun case ->
       let opt = is_opt_case case in
       let n1 = c_name_of_enum case in
       let n2 = ml_name_of_enum case in
       let h = Btype.hash_variant n2 in
       if opt then
         fprintf c "#ifdef HAVE_ENUM_%s\n" n1;
       fprintf c "    case %s: return Val_long(%d);\n" n1 h;
       if opt then
         fprintf c "#endif\n"
    )
    cases;
  fprintf c "    default: break;\n";
  fprintf c "  };\n";
  fprintf c "  caml_failwith(\"wrap_%s: unexpected value\");\n" tyname;
  fprintf c "}\n\n";

  fprintf c "static %s unwrap_%s(value v) {\n" tyname tyname;
  fprintf c "  switch (Long_val(v)) {\n";
  List.iter
    (fun case ->
       let opt = is_opt_case case in
       let n1 = c_name_of_enum case in
       let n2 = ml_name_of_enum case in
       let h = Btype.hash_variant n2 in
       if opt then
         fprintf c "#ifdef HAVE_ENUM_%s\n" n1;
       fprintf c "    case %d: return %s;\n" h n1;
       if opt then
         fprintf c "#endif\n"
    )
    cases;
  fprintf c "    default: caml_invalid_argument(\"unwrap_%s\");\n" tyname;
  fprintf c "  };\n";
  fprintf c "  caml_failwith(\"unwrap_%s: unexpected value\");\n" tyname;
  fprintf c "}\n";

  if optional then
    fprintf c "#endif\n";

  fprintf c "\n";
  ()

let gen_enum_of_string mli ml fun_name type_name cases =
  fprintf ml "let %s name =\n" fun_name;
  fprintf ml "  match name with\n";
  List.iter
    (fun case ->
       let n1 = c_name_of_enum case in
       let n2 = ml_name_of_enum case in
       fprintf ml "  | %S -> `%s\n" n1 n2
    )
    cases;
  fprintf ml "  | any -> failwith(\"%s: unknown error code\" ^ any)\n" fun_name;
  fprintf ml "\n";

  fprintf mli "val %s : string -> %s\n" fun_name type_name;

  ()

(**********************************************************************)
(* Flags                                                              *)
(**********************************************************************)

let gen_flags c mli ml tyname cases ~optional =
  List.iter
    (fun f ->
       fprintf f "type %s_flag =\n" tyname;
       fprintf f "  [ ";
       let first = ref true in
       List.iter
         (fun case ->
            if not !first then fprintf f "  | ";
            first := false;
            fprintf f "`%s\n" (ml_name_of_enum case)
         )
         cases;
       fprintf f "  ]\n";
       fprintf f "type %s = %s_flag list\n" tyname tyname;
    )
    [ mli; ml ];

  fprintf c "/************** %s *************/\n\n" tyname;
  if optional then
    fprintf c "#ifdef HAVE_TY_%s\n" tyname;
  fprintf c "static value wrap_%s(%s x) {\n" tyname tyname;
  fprintf c "  CAMLparam0();\n";
  fprintf c "  CAMLlocal2(v,u);\n";
  fprintf c "  v = Val_long(0);\n";
  List.iter
    (fun case ->
       let opt = is_opt_case case in
       let n1 = c_name_of_enum case in
       let n2 = ml_name_of_enum case in
       let h = Btype.hash_variant n2 in
       if opt then
         fprintf c "#ifdef HAVE_ENUM_%s\n" n1;
       fprintf c "  if (x & %s) {\n" n1;
       fprintf c "    u = caml_alloc(2,0);\n";
       fprintf c "    Field(u, 0) = Val_long(%d);\n" h;
       fprintf c "    Field(u, 1) = v;\n";
       fprintf c "    v = u;\n";
       fprintf c "  };\n";
       if opt then
         fprintf c "#endif\n";
    )
    cases;
  fprintf c "  CAMLreturn(v);\n";
  fprintf c "}\n\n";

  fprintf c "static %s unwrap_%s(value v) {\n" tyname tyname;
  fprintf c "  %s x = 0;\n" tyname;
  fprintf c "  while (Is_block(v)) {\n";
  fprintf c "    switch (Long_val(Field(v,0))) {\n";
  List.iter
    (fun case ->
       let opt = is_opt_case case in
       let n1 = c_name_of_enum case in
       let n2 = ml_name_of_enum case in
       let h = Btype.hash_variant n2 in
       if opt then
         fprintf c "#ifdef HAVE_ENUM_%s\n" n1;
       fprintf c "      case %d: x |= %s; break;\n"
               h n1;
       if opt then
         fprintf c "#endif\n";
    )
    cases;
  fprintf c "    };\n";
  fprintf c "    v = Field(v,1);\n";
  fprintf c "  };\n";
  fprintf c "  return x;\n";
  fprintf c "}\n";

  if optional then
    fprintf c "#endif\n";

  fprintf c "\n";
  ()

(**********************************************************************)
(* Same_as                                                            *)
(**********************************************************************)

let gen_same_as c mli ml old_tyname tyname =
  fprintf mli "type %s = %s\n" tyname old_tyname;
  fprintf ml "type %s = %s\n" tyname old_tyname;
  (* (* this generates gcc warnings: *)
  fprintf c "#define wrap_%s wrap_%s\n" tyname old_tyname;
  fprintf c "#define unwrap_%s unwrap_%s\n" tyname old_tyname
   *)
  fprintf c "/************** %s *************/\n\n" tyname;
  fprintf c "static value wrap_%s(%s x) {\n" tyname tyname;
  fprintf c "  %s y;\n" old_tyname;
  fprintf c "  y = (%s) x;\n" old_tyname;
  fprintf c "  return wrap_%s(y);\n" old_tyname;
  fprintf c "}\n\n";
  fprintf c "static %s unwrap_%s(value v) {\n" tyname tyname;
  fprintf c "  %s y;\n" old_tyname;
  fprintf c "  y = unwrap_%s(v);\n" old_tyname;
  fprintf c "  return (%s) y;\n" tyname;
  fprintf c "}\n\n"

(**********************************************************************)
(* Functions                                                          *)
(**********************************************************************)

let ws_re = Str.regexp "[ \t]+"

let split_type ty =
  let l = Str.split ws_re ty in
  match l with
    | "const" :: l' -> true, l'
    | _ -> false, l


let rec translate_type_to_ml name ty =
  let (is_const, ty_list) = split_type ty in
  match ty_list with
    | [ "void" ] -> "unit"
    | [ "int" ] -> "int"
    | [ "uint" ] -> "int"
    | [ "int32" ] -> "int32"
    | [ "uint32" ] -> "int32"
    | [ "bool" ] -> "bool"
    | [ "ubool" ] -> "bool"
    | [ "double" ] -> "float"
    | [ "ztstr" ] -> "string"
    | [ elt; "ztlist" ] -> translate_type_to_ml name elt ^ " list"
    | [ elt; "array" ] -> translate_type_to_ml name elt ^ " array"
    | [ aname; "array_size" ] -> "int"
    | [ id; "bigarray" ] -> "Netsys_mem.memory"
    | [ id; "bigarray_size" ] -> "int"
    | [ id; "stringbuf" ] -> "Bytes.t"
    | [ id; "stringbuf_size" ] -> "int"
    | [ id; "ztstringbuf" ] -> "Bytes.t"
    | [ id; "ztstringbuf_size" ] -> "int"
    | [ "bigarray_datum" ] -> "Netsys_mem.memory"
    | [ "str_datum" ] -> "string"
    | [ "file_descr" ] -> "Unix.file_descr"
    | [ tyname ] -> 
         ( try
             let p = String.index tyname '/' in
             let tyname2 =
               String.sub tyname (p+1) (String.length tyname -p - 1) in
             translate_type_to_ml name tyname2
           with Not_found ->
                tyname
         )
    | _ -> failwith ("Bad type in function " ^ name ^ ": " ^ ty)


let rec translate_type_to_c name ty =
  let (is_const, ty_list) = split_type ty in
  let c_ty, tag =
    match ty_list with
      | [ "void" ] -> 
           "void", `Ignore
      | [ "int" ] -> 
           "int", `Plain("Int_val", "Val_int")
      | [ "uint" ] -> 
           "unsigned int", `Plain("uint_val", "Val_int")
      | [ "int32" ] -> 
           "int32_t", `Plain("Int32_val", "caml_copy_int32")
      | [ "uint32" ] -> 
           "uint32_t", `Plain("Int32_val", "caml_copy_int32")
      | [ "bool" ] -> 
           "int", `Plain("Bool_val", "Val_bool")
      | [ "ubool" ] -> 
           "unsigned int", `Plain("Bool_val", "Val_bool")
      | [ "double" ] -> 
           "double", `Plain("Double_val", "caml_copy_double")
      | [ "ztstr" ] -> 
           "char *", `Plain("String_val", "protected_copy_string")
      | [ "file_descr" ] ->    (* FIXME: win32 *)
           "int", `Plain("Int_val", "Val_int")
      | [ elt; "ztlist" ] -> 
           let el_cty, el_tag = 
             translate_type_to_c name elt in
           el_cty ^ " *", `ZTList el_tag
      | [ elt; "array" ] ->
           let el_cty, el_tag =
             translate_type_to_c name elt in
           el_cty ^ " *", `Array(el_cty, el_tag)
      | [ aname; "array_size" ] ->
           "size_t", `Array_size(aname, "size_t")
      | [ aname; "array_size_uint" ] ->
           "unsigned int", `Array_size(aname, "unsigned int")
      | [ id; "bigarray" ] -> 
           "void *", `Bigarray id
      | [ id; "bigarray_size" ] -> 
           "size_t", `Bigarray_size id
      | [ id; "stringbuf" ] -> 
           "void *", `Stringbuf id
      | [ id; "stringbuf_size" ] -> 
           "size_t", `Stringbuf_size id
      | [ id; "ztstringbuf" ] -> 
           "void *", `ZTStringbuf id
      | [ id; "ztstringbuf_size" ] -> 
           "size_t", `ZTStringbuf_size id
(*
      | [ "bigarray_datum" ] -> 
           "gnutls_datum_t", `Bigarray_datum
      | [ "bigarray_datum_p" ] -> 
           "gnutls_datum_t *", `Bigarray_datum
 *)
      | [ tyname ] -> 
           ( try
               let p = String.index tyname '/' in
               let tyname1 =
                 String.sub tyname 0 p in
               let tyname2 =
                 String.sub tyname (p+1) (String.length tyname - p - 1) in
               let (_, tag) = translate_type_to_c name tyname2 in
               (tyname1, tag)
             with Not_found ->
               tyname, `Plain("unwrap_" ^ tyname, "wrap_" ^ tyname)
           )
      | _ -> 
           ty, `Unsupported in
  let c_ty1 =
    if is_const && tag <> `Unsupported then "const " ^ c_ty else c_ty in
  (c_ty1, tag)


let is_size ty =
  let (is_const, ty_list) = split_type ty in
  match ty_list with
    | [ id; "bigarray_size" ] -> true
    | [ id; "array_size" ] -> true
    | [ id; "stringbuf_size" ] -> true
    | [ id; "ztstringbuf_size" ] -> true
    | _ -> false



let rec first n l =
  if n=0 then
    []
  else
    match l with
      | x :: l' -> x :: first (n-1) l'
      | [] -> []


let rec after_first n l =
  if n=0 then
    l
  else
    match l with
      | x :: l' -> after_first (n-1) l'
      | [] -> []


let result_re = Str.regexp "RESULT"


let input_kinds = [ `In; `In_ptr; `In_ignore; `In_out; `In_out_noptr ]
let outonly_kinds = [ `Out; `Out_ignore; `Out_noptr ]
let inout_kinds = [ `In_out; `In_out_noptr ]
let output_kinds = outonly_kinds @ inout_kinds

let gen_fun c mli ml name args directives free init =
  let optional = List.mem `Optional directives in
  let blocking = List.mem `Blocking directives in
  let input_args =
    List.filter
      (fun (n,kind,ty) -> List.mem kind input_kinds)
      args in
  let input_ml_args0 =
    List.filter
      (fun (n,kind,ty) ->
         List.mem kind inout_kinds ||
           ((kind = `In || kind = `In_ptr) && not(is_size ty))
      )
      input_args in
  let input_ml_args =
    if input_ml_args0 = [] then [ "dummy", `In, "void" ] else input_ml_args0 in
  let output_args =
    List.filter
      (fun (n,kind,ty) -> List.mem kind output_kinds)
      args in
  let output_ml_args0 =
    List.filter
      (fun (n,kind,ty) -> kind = `Out || kind = `Out_noptr || 
                            List.mem kind inout_kinds)
      output_args in
  let return_args =
    List.filter
      (fun (n,kind,ty) -> kind = `Return || kind = `Return_ignore)
      args in
  let return_arg =
    match return_args with
      | [] -> ("", `Return_ignore, "void")
      | [ return_arg ] -> return_arg
      | _ -> failwith ("More than one return value: " ^ name) in
  let ignore_return_arg =
    let (_, kind, _) = return_arg in
    kind = `Return_ignore in  
  let output_ml_args =
    if ignore_return_arg then (
      if output_ml_args0 = [] then
        ["", `Out_ignore, "void" ]
      else
        output_ml_args0
    )
    else
      return_arg :: output_ml_args0 in
  let trans_input_ml_args =
    List.map
      (fun (_,_,ty) -> translate_type_to_ml name ty)
      input_ml_args in
  let trans_output_ml_args =
    List.map
      (fun (_,_,ty) -> translate_type_to_ml name ty)
      output_ml_args in
  fprintf mli "val %s : %s -> %s\n" 
          name
          (String.concat " -> " trans_input_ml_args)
          (String.concat " * " trans_output_ml_args);
  fprintf ml "external %s : %s -> %s\n" 
          name
          (String.concat " -> " trans_input_ml_args)
          (String.concat " * " trans_output_ml_args);
  fprintf ml " = %S %S\n"
          (if List.length trans_input_ml_args > 5 then
             ("net_" ^ name ^ "__byte")
           else
             ("net_" ^ name)
          )
          ("net_" ^ name);

  let c_args =
    List.map
      (fun (n,kind,ty) ->
         let (c_ty, tag) = translate_type_to_c name ty in
         (n, kind, ty, c_ty, tag)
      )
      args in

  let c_decls = ref [] in
  let ml_locals = ref [] in
  let c_code_pre = ref [] in
  let c_code_post = ref [] in
  let c_code_post_prio = ref [] in
  let c_act_args = ref [] in
  let c_act_ret = ref None in

  let n = ref 0 in
  let new_local() = let k = !n in incr n; sprintf "local_%d" k in

(*
  if not ignore_return_arg then (
    let (n,_,_) = return_arg in
    ml_locals := n :: !ml_locals
  );
 *)

  let n_return = ref 0 in
  let return_names = ref [] in

  List.iter
    (fun (n, kind, ty, c_ty, tag) ->
       if kind <> `Return_ignore || ty <> "void" then (
         let n1 = sprintf "%s__c" n in
         c_decls := sprintf "%s %s;" c_ty n1 :: !c_decls;
         
         if List.mem kind output_kinds && List.mem c_ty init then (
           c_code_pre := sprintf "init_%s(&%s);" c_ty n1 :: !c_code_pre
         );

         if kind <> `In_ignore && List.mem kind input_kinds then (
           match tag with
             | `Plain(to_c,to_ml) ->
                  let need_free = List.mem c_ty free in
                  let unwrap = 
                    sprintf "%s = %s(%s);" n1 to_c n in
                  c_code_pre := unwrap :: !c_code_pre;
                  if need_free then (
                    let free_call =
                      sprintf "free_%s(%s);" c_ty n1 in
                    c_code_post_prio := free_call :: !c_code_post_prio
                  )
             | `Array(el_c_ty, `Plain(to_c,to_ml)) ->
                  let i1 = new_local() in
                  c_decls := sprintf "long %s;" i1 :: !c_decls;
                  let code1 =
                    [ sprintf "%s = (%s) caml_stat_alloc(Wosize_val(%s)*sizeof(%s));" 
                              n1 c_ty n el_c_ty;
                      sprintf "for (%s=0; %s < Wosize_val(%s); %s++) {"
                              i1 i1 n i1;
                      sprintf "  %s[%s] = %s(Field(%s,%s));" n1 i1 to_c n i1;
                      sprintf "};";
                    ] in
                  c_code_pre := List.rev code1 @ !c_code_pre;
                  let el_need_free = List.mem el_c_ty free in
                  let code2 =
                    (if el_need_free then
                       [ sprintf "for (%s=0; %s < Wosize_val(%s); %s++) {"
                                 i1 i1 n i1;
                         sprintf "  free_%s(%s[%s]);" el_c_ty n1 i1;
                         sprintf "};"
                       ]
                     else []) @
                      [ sprintf "caml_stat_free(%s);" n1 ] in
                  c_code_post_prio := List.rev code2 @ !c_code_post_prio;
             | `Array_size(n_array, ty) ->
                  let code =
                    sprintf "%s = (%s) Wosize_val(%s);" n1 ty n_array in
                  c_code_pre := code :: !c_code_pre
             | `Bigarray id ->
                  let code1 =
                    [ sprintf "%s = Caml_ba_data_val(%s);" n1 n ] in
                  c_code_pre := List.rev code1 @ !c_code_pre;
             | `Bigarray_size id ->
                  let (n_array,_,_,_,_) =
                    try
                      List.find
                        (fun (_,_,_,_,tag) -> 
                           tag = `Bigarray id
                        )
                        c_args
                    with
                      | Not_found ->
                           failwith ("bigarray_size needs bigarray, fn: " ^ 
                                       name) in
                  let code1 =
                    [ sprintf "%s = caml_ba_byte_size(Caml_ba_array_val(%s));"
                              n1 n_array ] in
                  c_code_pre := List.rev code1 @ !c_code_pre;
                  
             | `Stringbuf id ->
                  let code1 =
                    [ sprintf "%s = String_val(%s);" n1 n ] in
                  c_code_pre := List.rev code1 @ !c_code_pre;
             | `Stringbuf_size id ->
                  let (n_array,_,_,_,_) =
                    try
                      List.find
                        (fun (_,_,_,_,tag) -> 
                           tag = `Stringbuf id
                        )
                        c_args
                    with
                      | Not_found ->
                           failwith ("stringbuf_size needs stringbuf, fn: " ^ 
                                       name) in
                  let code1 =
                    [ sprintf "%s = caml_string_length(%s);"
                              n1 n_array ] in
                  c_code_pre := List.rev code1 @ !c_code_pre;

             | `ZTStringbuf id ->
                  let code1 =
                    [ sprintf "%s = String_val(%s);" n1 n ] in
                  c_code_pre := List.rev code1 @ !c_code_pre;

             | `ZTStringbuf_size id ->
                  (* sole difference to Stringbuf_size: the length includes
                     the trailing null byte
                   *)
                  let (n_array,_,_,_,_) =
                    try
                      List.find
                        (fun (_,_,_,_,tag) -> 
                           tag = `ZTStringbuf id
                        )
                        c_args
                    with
                      | Not_found ->
                           failwith ("ztstringbuf_size needs ztstringbuf, fn: "
                                     ^  name) in
                  let code1 =
                    [ sprintf "%s = caml_string_length(%s)+1;"
                              n1 n_array ] in
                  c_code_pre := List.rev code1 @ !c_code_pre;
                  
             | _ ->
                  failwith ("Unsupported arg: " ^ n ^ ", fn " ^ name)
         );

         if (kind <> `Out_ignore && List.mem kind outonly_kinds)
            || kind = `Return
         then (
           ml_locals := n :: !ml_locals;
         );

         if (kind <> `Out_ignore && List.mem kind output_kinds)
            || kind = `Return
         then (
           incr n_return;
           return_names := n :: !return_names;
           match tag with
             | `Plain(to_c,to_ml) ->
                  let wrap = 
                    sprintf "%s = %s(%s);" n to_ml n1 in
                  c_code_post := wrap :: !c_code_post
             | `ZTList(`Plain(to_c,to_ml)) ->
                  let i1 = new_local() in
                  let h1 = new_local() in
                  c_decls := sprintf "long %s;" i1 :: !c_decls;
                  ml_locals := h1 :: !ml_locals;
                  let code =
                    [ sprintf "%s = 0;" i1;
                      sprintf "while (%s[%s] != 0) %s++;" n1 i1 i1;
                      sprintf "%s = Val_int(0);" n;
                      sprintf "while (%s > 0) {" i1;
                      sprintf "  %s--;" i1;
                      sprintf "  %s = caml_alloc(2,0);" h1;
                      sprintf "  Field(%s,0) = %s(%s[%s]);" h1 to_ml n1 i1;
                      sprintf "  Field(%s,1) = %s;" h1 n;
                      sprintf "  %s = %s;" n h1;
                      sprintf "};"
                    ] in
                  c_code_post := List.rev code @ !c_code_post;
             | `Array(el_c_ty, `Plain(to_c,to_ml)) ->
                  let (n_size,_,_,_,_) =
                    try
                      List.find
                        (fun (_,_,_,_,tag) -> 
                           match tag with
                             | `Array_size(n_size,_) -> n_size = n
                             | _ -> false
                        )
                        c_args
                    with
                      | Not_found ->
                           failwith ("array needs array_size, fn: " ^  name) in
                  let i1 = new_local() in
                  c_decls := sprintf "long %s;" i1 :: !c_decls;
                  (* for simplicity we return an empty error in case of a
                     NULL pointer. Let's hope this is right.
                   *)
                  let code =
                    [ (* sprintf "if (%s == NULL) failwith(\"%s: NULL pointer\");"
                              n1 name;
                       *)
                      sprintf "if (%s == NULL)" n1;
                      sprintf "  %s = caml_alloc(0,0);" n;
                      sprintf "else {";
                      sprintf "  %s = caml_alloc(%s__c,0);" n n_size;
                      sprintf "  for (%s = 0; %s < %s__c; %s++) {" 
                              i1 i1 n_size i1;
                      sprintf "    Store_field(%s, %s, %s(%s[%s]));"
                              n i1 to_ml n1 i1;
                      sprintf "  };";
                      sprintf "};"
                    ] in
                  c_code_post := List.rev code @ !c_code_post;

             | `Array_size(aname,ty) ->
                  let code =
                    [ sprintf "%s = Val_long(%s);" n n1 ] in
                  c_code_post := List.rev code @ !c_code_post;

             | `Bigarray _ ->
                  failwith ("Bigarray unsupported as `Out: " ^ name)

             | `Bigarray_size id ->
                  let code1 =
                    [ sprintf "%s = Val_long(%s);" n n1 ] in
                  c_code_post := List.rev code1 @ !c_code_post;

             | `Stringbuf id ->
                  if kind = `In_out then
                    failwith ("Stringbuf unsupported as `In_out: " ^ name);
                  if not (List.mem `GNUTLS_ask_for_size directives) then
                    failwith ("Stringbuf needs GNUTLS_ask_for_size: " ^ name);
                  ()

             | `Stringbuf_size id ->
                  let code1 =
                    [ sprintf "%s = Val_long(%s);" n n1 ] in
                  c_code_post := List.rev code1 @ !c_code_post;

             | `ZTStringbuf id ->
                  if kind = `In_out then
                    failwith ("ZTStringbuf unsupported as `In_out: " ^ name);
                  if not (List.mem `GNUTLS_ask_for_size directives) then
                    failwith ("ZTStringbuf needs GNUTLS_ask_for_size: " ^ name);
                  ()

             | `ZTStringbuf_size id ->
                  let code1 =
                    [ sprintf "%s = Val_long(%s);" n n1 ] in
                  c_code_post := List.rev code1 @ !c_code_post;

             | _ ->
                  failwith ("Unsupported arg: " ^ n ^ ", fn " ^ name)
         );

         let noref =
           (* don't put a "&" before the arg even if it is an output *)
           match tag with
             | `Stringbuf _ -> true
             | `ZTStringbuf _ -> true
             | `Bigarray _ -> true
             | _ -> false in

         ( match kind with
             | `In | `In_ignore ->
                  c_act_args := n1 :: !c_act_args
             | `In_ptr ->
                  c_act_args := ("&" ^ n1) :: !c_act_args
             | `In_out | `Out | `Out_ignore ->
                  if noref then
                    c_act_args := n1 :: !c_act_args
                  else
                    c_act_args := ("&" ^ n1) :: !c_act_args
             | `Out_noptr | `In_out_noptr ->
                  c_act_args := n1 :: !c_act_args
             | `Return | `Return_ignore ->
                  c_act_ret := Some n1
         )
       )
    )
    c_args;

  let n_compare =
    List.length output_ml_args0 + (if ignore_return_arg then 0 else 1) in
  if !n_return <> n_compare then
    failwith(sprintf "Problem 1: %s (n_return=%d n_compare=%d)" 
                     name
                     !n_return
                     n_compare);

  let caml_return = ref None in
  if !n_return = 1 then
    caml_return := Some(List.hd !return_names)
  else
    if !n_return > 1 then (
      let n1 = new_local() in
      ml_locals := n1 :: !ml_locals;
      c_code_post := 
        sprintf "%s = caml_alloc(%d,0);" n1 !n_return :: !c_code_post;
      let k = ref 0 in
      List.iter
        (fun (n,_,_) ->
           if not (List.mem n !return_names) then
             failwith ("Output name not found: " ^ n);
           c_code_post :=
             sprintf "Field(%s, %d) = %s;" n1 !k n :: !c_code_post;
           incr k
        )
        output_ml_args;
      caml_return := Some n1
    );

  let input_ml_args_as_c =
    String.concat ","
      (List.map (fun (n,_,_) -> "value " ^ n) input_ml_args) in

  let l = ref input_ml_args in
  let maybe_x = ref "" in
  if !l = [] then
    c_decls := "CAMLparam0();" :: !c_decls;
  while !l <> [] do
    let hd5 = first 5 !l in
    let s = String.concat "," (List.map (fun (n,_,_) -> n) hd5) in
    let d = sprintf "CAML%sparam%d(%s);" !maybe_x (List.length hd5) s in
    c_decls := d :: !c_decls;
    l := after_first 5 !l;
    maybe_x := "x"
  done;

  let l = ref (List.rev !ml_locals) in
  while !l <> [] do
    let hd5 = first 5 !l in
    let s = String.concat "," hd5 in
    let d = sprintf "CAMLlocal%d(%s);" (List.length hd5) s in
    c_decls := d :: !c_decls;
    l := after_first 5 !l;
  done;

  fprintf c "value net_%s(%s) {\n" name input_ml_args_as_c;
  if optional then
    fprintf c "#ifdef HAVE_FUN_%s\n" name;
  List.iter
    (fun d -> fprintf c "  %s\n" d)
    (List.rev !c_decls);
  List.iter
    (function
      | `Declare stmt -> fprintf c "  %s\n" stmt
      | _ -> ()
    )
    directives;
  List.iter
    (fun stmt -> fprintf c "  %s\n" stmt)
    (List.rev !c_code_pre);
  
  List.iter
    (function
      | `Pre stmt -> fprintf c "  %s\n" stmt
      | _ -> ()
    )
    directives;

  let emit_call() =
    if blocking then
      fprintf c "caml_enter_blocking_section();\n  ";
    ( match !c_act_ret with
        | None -> ()
        | Some var -> fprintf c "%s = " var
    );
    fprintf c "%s(%s);\n" name (String.concat "," (List.rev !c_act_args));
    if blocking then
      fprintf c "  caml_leave_blocking_section();\n" in

  if List.mem `GNUTLS_ask_for_size directives then (
    (* Call the function twice: once to get the size of the string buffer,
       and a second time to fill the buffer
     *)
    let (n_strbuf,_,_,_,tag) =
      try
        List.find
          (fun (_,_,_,_,tag) ->
             tag = `Stringbuf "1" || tag = `ZTStringbuf "1"
          )
          c_args
      with
        | Not_found ->
             failwith ("GNUTLS_ask_for_size needs '1 stringbuf', fn: " ^ 
                         name) in
    let (n_strbuf_size,_,_,_,tag_size) =
      try
        List.find
          (fun (_,_,_,_,tag_size) -> 
             tag_size = `Stringbuf_size "1" || tag_size = `ZTStringbuf_size "1"
          )
          c_args
      with
        | Not_found ->
             failwith ("GNUTLS_ask_for_size needs '1 stringbuf_size', fn: " ^ 
                         name) in
    let zt =
      match tag, tag_size with
        | `ZTStringbuf _, `ZTStringbuf_size _ -> true
        | `Stringbuf _, `Stringbuf_size _ -> false
        | _ ->
             failwith ("Mixed use of Stringbuf/ZTStringbuf, fn: " ^ name) in

    fprintf c "  %s__c = NULL;\n" n_strbuf;
    fprintf c "  %s__c = 0;\n" n_strbuf_size;
    fprintf c "  %s = caml_alloc_string(0);\n" n_strbuf;
    (* "pre call" *)
    fprintf c "  ";
    let ret_var =
      match !c_act_ret with
        | None -> assert false
        | Some var -> var in
    fprintf c "%s = " ret_var;
    fprintf c "%s(%s);\n" name (String.concat "," (List.rev !c_act_args));

    if zt then (
      (* Be very conservative: allocate one more byte for the terminating
         null. The returned ocaml string will not include any null bytes
       *)
      fprintf c "  if (%s == 0 || %s == GNUTLS_E_SHORT_MEMORY_BUFFER) {\n" 
              ret_var ret_var;
      fprintf c "    long n__stub;\n";
      fprintf c "    %s__c++;\n" n_strbuf_size;
      fprintf c "    n__stub = %s__c;\n" n_strbuf_size;
      fprintf c "    %s__c = caml_stat_alloc(%s__c+1);\n" n_strbuf n_strbuf_size;
      fprintf c "    ";
      emit_call();
      fprintf c "    if (%s == 0) {\n" ret_var;
      fprintf c "      ((char *) %s__c)[n__stub] = 0;\n" n_strbuf;
      fprintf c "      %s = caml_copy_string(%s__c);\n" n_strbuf n_strbuf;
      fprintf c "    };\n";
      fprintf c "    caml_stat_free(%s__c);\n" n_strbuf;
      fprintf c "  };\n";      
    )
    else (
      fprintf c "  if (%s == 0 || %s == GNUTLS_E_SHORT_MEMORY_BUFFER) {\n" 
              ret_var ret_var;
      fprintf c "    %s = caml_alloc_string(%s__c);\n"
              n_strbuf n_strbuf_size;
      fprintf c "    %s__c = String_val(%s);\n" n_strbuf n_strbuf;
      fprintf c "    ";
      emit_call();
      fprintf c "  };\n";
    )
  )
  else (
    fprintf c "  ";
    emit_call();
  );

  List.iter
    (fun stmt -> fprintf c "  %s\n" stmt)
    (List.rev !c_code_post_prio);

  List.iter
    (function
      | `Post stmt ->
           let stmt1 =
             match !c_act_ret with
               | None -> stmt
               | Some r -> 
                    Str.global_replace result_re r stmt in
           fprintf c "  %s\n" stmt1
      | _ -> ()
    )
    directives;

  List.iter
    (fun stmt -> fprintf c "  %s\n" stmt)
    (List.rev !c_code_post);

  ( match !caml_return with
      | None ->
           fprintf c "  CAMLreturn(Val_unit);\n"
      | Some r ->
           fprintf c "  CAMLreturn(%s);\n" r;
  );

  if optional then (
    fprintf c "#else\n";
    fprintf c "  caml_invalid_argument(\"%s\");\n" name;
    fprintf c "#endif\n";
  );

  fprintf c "}\n\n";

  if List.length trans_input_ml_args > 5 then (
    fprintf c "value net_%s__byte(value * argv, int argn) {\n" name;
    fprintf c "  return net_%s(%s);\n"
            name
            (String.concat ","
               (Array.to_list
                  (Array.init
                     (List.length trans_input_ml_args)
                     (fun i -> sprintf "argv[%d]" i)
                  )
               )
            );
    fprintf c "}\n\n";
  );
  
  ()


(**********************************************************************)

let cfg_cases cfg cases =
  List.iter
    (fun case ->
       if is_opt_case case then (
         let cname = c_name_of_enum case in
         fprintf cfg "check_enum HAVE_ENUM_%s %s\n" cname cname
       )
    )
    cases


let cfg_fun cfg name =
  fprintf cfg "check_fun HAVE_FUN_%s %s\n" name name


let cfg_type cfg name =
  fprintf cfg "check_type HAVE_TY_%s %s\n" name name


(**********************************************************************)

let gen_c_head c =
  fprintf c "#include <stdlib.h>\n\
             #include <stdio.h>\n\
             #include <string.h>\n\
             \n\
             #include \"caml/mlvalues.h\"\n\
             #include \"caml/alloc.h\"\n\
             #include \"caml/memory.h\"\n\
             #include \"caml/misc.h\"\n\
             #include \"caml/custom.h\"\n\
             #include \"caml/fail.h\"\n\
             #include \"caml/unixsupport.h\"\n\
             #include \"caml/callback.h\"\n\
             #include \"caml/bigarray.h\"\n\
             #include \"caml/threads.h\"\n\
             \n\
             static unsigned int uint_val(value v);\n\
             static value protected_copy_string(const char *s);\n\
             \n"

let gen_c_head2 c =
  fprintf c "static unsigned int uint_val(value v) {\n\
             \032   if (Int_val(v) < 0) caml_invalid_argument(\"negative integer\");\n\
             \032   return (unsigned int) Int_val(v);\n\
             }\n\
             \n\
             static value protected_copy_string(const char *s) {\n\
             \032   if (s==NULL) raise_null_pointer();\n\
             \032   return caml_copy_string(s);\n\
             }\n\
             \n"


let generate ?c_file ?ml_file ?mli_file
             ?(optional_functions = [])
             ?(optional_types = [])
             ?(enum_of_string = [])
             ~modname ~types ~functions ~free ~init
             ~hashes
             () =
  let c_name = modname ^ "_stubs.c" in
  let ml_name = modname ^ ".ml" in
  let mli_name = modname ^ ".mli" in
  let cfg_name = "config_checks.sh" in
  let to_close = ref [] in
  try
    let c = open_out c_name in
    to_close := (fun () -> close_out_noerr c) :: !to_close;
    let ml = open_out ml_name in
    to_close := (fun () -> close_out_noerr ml) :: !to_close;
    let mli = open_out mli_name in
    to_close := (fun () -> close_out_noerr mli) :: !to_close;
    let cfg = 
      open_out_gen
        [Open_wronly;Open_append;Open_creat;Open_text] 0o666 cfg_name in
    to_close := (fun () -> close_out_noerr cfg) :: !to_close;

    fprintf mli "(** Bindings of a C library *)";

    List.iter
      (fun h ->
         fprintf c "#define H_%s %d\n" h (Btype.hash_variant h)
      )
      hashes;

    let copy out file =
      match file with
        | Some fn ->
             let f = open_in fn in
             ( try
                 while true do
                   let line = input_line f in
                   fprintf out "%s\n" line
                 done;
                 assert false
               with End_of_file ->
                 close_in f
             );
        | None -> ()  in

    gen_c_head c;
    copy c c_file;
    gen_c_head2 c;

    List.iter
      (fun name -> cfg_type cfg name)
      optional_types;

    List.iter
      (fun (tyname,tydecl) ->
         let optional = List.mem tyname optional_types in
         match tydecl with
           | `Abstract_enum ->
                gen_abstract_enum c mli ml tyname ~optional
           | `Abstract_ptr abs ->
                gen_abstract_ptr c mli ml tyname abs ~optional
           | `Enum cases ->
                cfg_cases cfg cases;
                gen_enum c mli ml tyname cases ~optional
           | `Flags cases ->
                cfg_cases cfg cases;
                gen_flags c mli ml tyname cases ~optional
           | `Same_as old_tyname ->
                gen_same_as c mli ml old_tyname tyname 
           | `Manual(ocaml_decl ) ->
                fprintf ml "%s\n" ocaml_decl;
                fprintf mli "%s\n" ocaml_decl;
      )
      types;

    List.iter
      (fun (name,args,directives) ->
         if List.mem `Optional directives then
           cfg_fun cfg name;
         gen_fun c mli ml name args directives free init
      )
      functions;

    List.iter
      (fun name -> cfg_fun cfg name)
      optional_functions;

    List.iter
      (fun (fun_name, type_name) ->
         let tydef =
           try List.assoc type_name types
           with Not_found ->
             failwith ("enum_of_string: type not found: " ^ type_name) in
         match tydef with
           | `Enum cases ->
                gen_enum_of_string mli ml fun_name type_name cases
           | _ ->
                failwith ("enum_of_string: not an enum: " ^ type_name)
      )
      enum_of_string;

    copy ml ml_file;
    copy mli mli_file;

    close_out c;
    close_out ml;
    close_out mli;
    close_out cfg
  with
    | error ->
         List.iter
           (fun f -> f())
           !to_close;
         List.iter
           (fun n -> try Sys.remove n with _ -> ())
           [ c_name; ml_name; mli_name ];
         raise error

