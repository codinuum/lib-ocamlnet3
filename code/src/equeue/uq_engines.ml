(* 
 * $Id$
 *)

open Printf


exception Closed_channel
exception Broken_communication
exception Addressing_method_not_supported
exception Watchdog_timeout
exception Cancelled
exception Timeout

class type async_out_channel = object
  method output : Bytes.t -> int -> int -> int
  method close_out : unit -> unit
  method pos_out : int
  method flush : unit -> unit
  method can_output : bool
  method request_notification : (unit -> bool) -> unit
end
;;


class type async_in_channel = object
  method input : Bytes.t -> int -> int -> int
  method close_in : unit -> unit
  method pos_in : int
  method can_input : bool
  method request_notification : (unit -> bool) -> unit
end
;;


type 't engine_state =
  [ `Working of int
  | `Done of 't
  | `Error of exn
  | `Aborted
  ]
;;

type 't final_state =
  [ `Done of 't
  | `Error of exn
  | `Aborted
  ]

class type [ 't ] engine = object
  method state : 't engine_state
  method abort : unit -> unit
  method request_notification : (unit -> bool) -> unit
  method request_proxy_notification : ('t engine -> bool) -> unit
  method event_system : Unixqueue.event_system
end
;;


class type async_out_channel_engine = object
  inherit [ unit ] engine
  inherit async_out_channel
end
;;


class type async_in_channel_engine = object
  inherit [ unit ] engine
  inherit async_in_channel
end
;;


class type ['a] serializer_t =
object
  method serialized : (Unixqueue.event_system -> 'a engine) -> 'a engine
end


class type ['a] prioritizer_t =
object
  method prioritized : (Unixqueue.event_system -> 'a engine) -> int -> 'a engine
end


class type ['a] cache_t =
object
  method get_engine : unit -> 'a engine
  method get_opt : unit -> 'a option
  method put : 'a -> unit
  method invalidate : unit -> unit
  method abort : unit -> unit
end


module Debug = struct
  let enable = ref false
end

let dlog = Netlog.Debug.mk_dlog "Uq_engines" Debug.enable
let dlogr = Netlog.Debug.mk_dlogr "Uq_engines" Debug.enable

let () =
  Netlog.Debug.register_module "Uq_engines" Debug.enable


let string_of_state =
  function
    | `Working n -> "Working(" ^ string_of_int n ^ ")"
    | `Done v -> "Done(_)"
    | `Error e -> "Error(" ^ Netexn.to_string e ^ ")"
    | `Aborted -> "Aborted"

let is_active state =
  match state with
      `Working _ -> true
    | _          -> false
;;

module IntSet =
  Set.Make
    (struct
       type t = int
       let compare (x:t) (y:t) = Stdlib.compare x y
     end
    )


class [ 't ] engine_mixin_i (state : 't engine_state ref) esys =
  let notify_list = ref [] in
  let notify_list_new = ref [] in
  let setup_notify_list() =
    match !notify_list_new with
      | [] -> ()
      | n -> 
	   notify_list := !notify_list @ n;
	   notify_list_new := [] in
  let proxy_notification = ref None in
object(self)
  method state = !state

  method event_system = esys

  method request_notification f =
    if (not (is_active !state)) then
      dlog "engine_mixin warning: the method request_notification was called \
            when the engine already reached the final state";
    notify_list_new := f :: !notify_list_new
    
  method request_proxy_notification ( f : 't engine -> bool ) =
    if (not (is_active !state)) then
      dlog "engine_mixin warning: the method request_proxy_notification was \
             called when the engine already reached the final state";
    proxy_notification := Some f
    
  method private set_state s =
    if is_active !state then (
      state := s;
      self # notify();
    )

  method private notify_list() =
    setup_notify_list();
    !notify_list

  method private notify() =
    setup_notify_list();
    (* Optimize the case that we only have 1 element in the list. The
       expensive part here is the assignment (calls caml_modify).
     *)
    ( match !notify_list with
	| [] -> ()
	| [ f ] ->
	    let keep =
	      try
		f()
	      with
		| error ->
		    Unixqueue.epsilon esys (fun () -> raise error);
		    false in
	    if not keep then
	      notify_list := []
	| _ ->
	    notify_list := (
	      List.filter
		(fun f ->
		   try
		     f()
		   with
		     | error ->
			 Unixqueue.epsilon esys (fun () -> raise error);
			 false
		)
		!notify_list
	    )
    )

  method private proxy_notify e =
    match !proxy_notification with
      | None ->
           ()
      | Some p ->
           let keep =
	      try
		p e
	      with
		| error ->
		    Unixqueue.epsilon esys (fun () -> raise error);
		    false in
	   if not keep then
	     proxy_notification := None


  method private proxy_notify_list() =
    match !proxy_notification with
      | None -> []
      | Some p -> [p]

end ;;


class [ 't ] engine_mixin init_state esys =
  ['t] engine_mixin_i (ref init_state) esys



let when_state ?(is_done = fun _ -> ())
               ?(is_error = fun _ -> ())
	       ?(is_aborted = fun _ -> ())
	       ?(is_progressing = fun _ -> ())
	       (eng : 'a #engine) =
  (* Execute is_done when the state of eng goes to `Done,
   * execute is_error when the state goes to `Error, and
   * execute is_aborted when the state goes to `Aborted.
   * The argument of the callback function is the argument
   * of the state value.
   *)
  let last_n = 
    match eng#state with
      | `Done _ | `Error _ | `Aborted -> ref 0 
      | `Working n -> ref n in
  eng # request_notification
    (fun () ->
       match eng#state with
	   `Done v    -> is_done v; false
	 | `Error x   -> is_error x; false
	 | `Aborted   -> is_aborted(); false
	 | `Working n -> 
	     if n <> !last_n then is_progressing n;
	     last_n := n;
	     true
    )
;;


class ['a,'b] map_engine ~map_done ?map_error ?map_aborted 
              ?(propagate_working = true)
              (eng : 'a #engine) =
  let map_state eng_state =
    match eng_state with
	(`Working _ as wrk_state) -> 
	  wrk_state
      | `Done x -> 
	    map_done x
      | (`Error x as err_state) ->
	  ( match map_error with
		Some f -> f x
	      | None   -> err_state
	  )
      | `Aborted ->
	  ( match map_aborted with
		Some f -> f ()
	      | None   -> `Aborted
	  ) in

object(self)
  inherit ['b] engine_mixin (map_state eng#state) eng#event_system

  initializer
    if is_active eng#state then
      eng # request_notification self#map_forward_notification;

  method private map_forward_notification() =
    (* This method is called when [eng] changes its state. We compute our
     * mapped state, and notify our own listeners.
     *)
    let eng_state = eng#state in
    let state' = map_state eng_state in
    let cont =
      match state' with
	  (`Working _) -> true
	| (`Done _)
	| (`Error _)
	| `Aborted ->     false in
    if not cont || propagate_working then
      self # set_state state';
    cont


  method event_system = eng#event_system

  method abort() = 
    eng#abort()
end;;


let map_engine = new map_engine


class ['a,'b] fmap_engine e (f : 'a final_state -> 'b final_state) =
  [_,_] map_engine
    ~map_done:(fun x -> (f (`Done x) :> 'b engine_state))
    ~map_error:(fun e -> (f (`Error e) :> 'b engine_state))
    ~map_aborted:(fun () -> (f `Aborted :> 'b engine_state))
    e

let fmap_engine = new fmap_engine

class ['a] meta_engine e =
  ['a,'a final_state] map_engine
    ~map_done:(fun x -> `Done (`Done x))
    ~map_error:(fun e -> `Done (`Error e))
    ~map_aborted:(fun () -> `Done `Aborted)
    e

let meta_engine = new meta_engine


let const_engine st esys =
  ( object (self)
      inherit [_] engine_mixin st esys
      method abort() = ()
    end
  )

let aborted_engine esys =
  const_engine `Aborted esys


(* Sequencing engines ("bind" operation): This is somewhat special,
   because the sequences can be arbitrarily long, and we'd like to
   avoid that engines stack up indefinitely.

   If event counting is enabled (nocount=false), there is no chance
   to improve anything.

   If counting is disabled, though, we also optimize a few other things:

   1) Cut notification chains: In a chain e1 ++ e2 ++ ... ++ eN the
   last started engine sN is the first one that transitions to `Done
   (or `Error):

   e1 arg1 ++ (fun2 arg -> e2 arg2 ++ ... (fun argN -> eN argN) ...)
   ----------------------------------------------------------------- = s1
                           ----------------------------------------- = s2
                                                       .......       = sN=eN

   Now, the other engines are notified: sN notifies s(N-1), which
   in turn notifies its predecessor, etc., until s1 is reached. This
   chain has two bad effects:
     - The long notification chain may cause a stack overflow
     - The engine objects remain live in memory, because there are references
       from s(k) to s(k-1)

   The idea to short-circuit the notification. When s(k+1) is created
   we configure it so that the very first element of the chain is directly
   notified, and not the direct predecessor.

   This is implemented this way: when the second engine (eng_b) of a
   sequencing pair is created, it is configured so that all notifications
   for the current engine are directly applied to the new engine. Also,
   there is no direct connection between the current and the new engine.

   Drawback: for methods like [state], we need to keep the reference
   eng_b longer than we want. [state] is now implemented by forwarding
   the state request to eng_b. In other words, we replace the notification
   chain with another chain that forwards individual requests from one
   chain element to the next. This also creates memory references, but now
   in the opposite direction.

   2) Use proxy notification: If we are smart, we forward requests like
   s1#state directly to sN#state bypassing all engines in the middle.
   This is called proxying: sN becomes a proxy for the result of s1.
   Proxying is activated once the right-hand part of a sequencing pair
   is running (which is possible because the right-hand part is the
   result of the whole pair).
 *)


class ['a,'b] iseq_engine ~nocount
                          (eng_a : 'a #engine)
                          (make_b : 'a -> 'b #engine) =
  let esys = eng_a # event_system in
  let eng_a_state = ref (eng_a # state) in
  let eng_a = ref (Some (eng_a :> 'a engine)) in
  (* to get rid of the eng_a value when it is done *)

  let eng_b = ref None in
  let eng_b_state = ref (`Working 0) in

  let proxy = ref None in

object(self)
  inherit ['b] engine_mixin (`Working 0) esys as super

  initializer
    match !eng_a with
      | Some e ->
	  if is_active e#state then
	    e # request_notification self#update_a
	  else (
	    (* eng_a is already in a final state *)
	    ignore(self#update_a())
	  )
      | None -> assert false

  method state =
    if nocount then
      match !proxy with
        | None ->
             ( match !eng_b with
                 | None -> super#state
                 | Some e -> e#state
             )
        | Some p ->
             p#state
    else
      super#state

  method request_notification f =
    if nocount then
      match !proxy with
        | None ->
             ( match !eng_b with
                 | None -> super#request_notification f
                 | Some e -> e#request_notification f
             )
        | Some p ->
             p#request_notification f
    else
      super#request_notification f
    

  method private update_a() =
    (* eng_a is running, eng_b not yet existing *)
    let ea =
      match !eng_a with Some e -> e | None -> assert false in
    let s = ea # state in
    match s with
      |	`Working n ->
	  ( match !eng_a_state with
	      | `Working n' when n = n' -> ()
	      | _ ->   (* i.e. s <> !eng_a_state *)
		  self # seq_count();
		  eng_a_state := s
	  );
	  true
      | `Done arg ->
	  (* Create eng_b *)
	  (* get rid of eng_a - otherwise mem leak: *)
	  eng_a := None;
	  let e = 
	    try (make_b arg :> _ engine)
	    with error ->
	      const_engine (`Error error) esys in
	  eng_b := Some e;
	  let s' = e # state in
	  eng_b_state := s';
	  self # seq_count();
          (* Tell the listeners that this engine acts now as a proxy: *)
          self # proxy_notify e;
	  if is_active s' then (
            if nocount then (
              (* We bypass this engine, and send updates directly to the
                 observers of this engine. That way we avoid that the
                 notification chain grows indefinitely. Also, in this case
                 [self#state] is forwarded to [eng_b#state] (see above).
               *)
              let l1 = self # notify_list() in
              List.iter
                (fun f ->
                   e # request_notification f
                )
                l1;
              (* Configure proxying: If this object doesn't have any
                 proxy notification request, it is the start of the chain.
                 So we request that whenever there is a proxy for eng_b,
                 it shall also be the proxy for this object (update_proxy).
                 Otherwise, we just forward notifications like above.
               *)
              let l2 = self # proxy_notify_list() in
              if l2 = [] then
                e # request_proxy_notification self#update_proxy
              else
                List.iter
                  (fun f ->
                     e # request_proxy_notification f
                  )
                  l2
            )
            else
              (* this one also has the danger of running into stack overflows *)
	      e # request_notification self#update_b
          )
	  else
	    ignore(self#update_b());
	  false
      | `Error arg ->
	  self # set_state (`Error arg);
	  false
      | `Aborted ->
	  self # set_state `Aborted;
	  false

  method private update_b() =
    (* eng_a is `Done, eng_b is running *)
    let e = match !eng_b with Some e -> e | None -> assert false in
    let s = e # state in
    match s with
      | `Working n ->
	  ( match !eng_b_state with
	      | `Working n' when n=n' -> ()
	      | _ ->
		  self # seq_count();
		  eng_b_state := s
	  );
	  true
      | `Done arg ->
	  self # set_state s;
	  false
      | `Error arg ->
	  self # set_state s;
	  false
      | `Aborted ->
	  self # set_state s;
	  false

  method private update_proxy p =
    proxy := Some p;
    eng_b := None;
    eng_b_state := (`Working 0);
    true

  method private seq_count() =
    match self#state with
      | `Working n ->
          if not nocount then
  	    self # set_state (`Working (n+1))
      | _ ->
          ()

  method abort() =
    ( match !eng_a with
	| Some e -> 
	    e # abort()
	| None -> ()
    );
    ( match !eng_b with
	| Some e -> 
	    e # abort()
	| None -> ()
    );
    ( match !proxy with
	| Some e -> 
	    e # abort()
	| None -> ()
    )
end;;


class ['a,'b] seq_engine = ['a,'b] iseq_engine ~nocount:false
let seq_engine = new seq_engine

class ['a,'b] qseq_engine = ['a,'b] iseq_engine ~nocount:true
let qseq_engine = new qseq_engine


class ['a] delegate_engine e =
object(self)
  inherit ['a] engine_mixin e#state e#event_system

  initializer (
    if is_active e#state then 
      when_state
	~is_done:(fun x -> self # set_state (`Done x))
	~is_error:(fun e -> self # set_state (`Error e))
	~is_aborted:(fun () -> self # set_state `Aborted)
	~is_progressing:(fun n -> self # set_state (`Working n))
	e
  )

  method abort() =
    e#abort();
    self # set_state `Aborted
end



class ['a] stream_seq_engine x0 (s : ('a -> 'a #engine) Stream.t)  esys =
object(self)
  inherit ['a] engine_mixin (`Working 0) esys

  val mutable x = x0
  val mutable cur_e = aborted_engine esys

  initializer
    self#next()

  method private next() =
    match Stream.peek s with
      | None ->
	  self # set_state (`Done x)
      | Some f ->
	  let _ = Stream.next s in  (* yep, it's "partial" *)
	  let e =
	    try (f x :> _ engine)
	    with error -> const_engine (`Error error) esys in
	  cur_e <- e;
	  if is_active e#state then
	    when_state
	      ~is_done:(fun x1 -> 
			  x <- x1;
			  Unixqueue.epsilon esys self#next
			    (* avoids stack overflow *)
		       )
	      ~is_error:(fun e -> self # set_state (`Error e))
	      ~is_aborted:(fun () -> self # set_state `Aborted)
	      ~is_progressing:(fun _ -> self # sseq_count())
	      e
	  else
	    self # set_state e#state

  method abort() =
    cur_e # abort();
    self # set_state `Aborted

  method private sseq_count() =
    match self#state with
	`Working n ->
	  self # set_state (`Working (n+1))
      | _ ->
	  ()
end


let stream_seq_engine = new stream_seq_engine



let abort_if_working eng =
  match eng#state with
      `Working _ ->
	eng # abort()
    | _ ->
	()
;;


class ['a,'b] sync_engine (eng_a : 'a #engine) (eng_b : 'b #engine) =
object(self)

  val mutable eng_a_state = eng_a # state

  val mutable eng_b_state = eng_b # state

  inherit ['a * 'b] engine_mixin (`Working 0) eng_a#event_system


  initializer
    if is_active eng_a#state then
      eng_a # request_notification self#sy_update_a
    else
      ignore(self#sy_update_a());
    if is_active eng_b#state then
      eng_b # request_notification self#sy_update_b
    else
      ignore(self#sy_update_b())

  method private sy_update_a() =
    let s = eng_a # state in
    match s with
      |	`Working n ->
	  if s <> eng_a_state then self # transition();
	  eng_a_state <- s;
	  true
      | `Done _ ->
	  eng_a_state <- s;
	  self # transition();
	  false
      | _ ->
	  eng_a_state <- s;
	  self # transition();
	  abort_if_working eng_b;
	  false

  method private sy_update_b() =
    let s = eng_b # state in
    match s with
      | `Working n ->
	  if s <> eng_b_state then self # transition();
	  eng_b_state <- s;
	  true
      | `Done _ ->
	  eng_b_state <- s;
	  self # transition();
	  false
      | _ ->
	  eng_b_state <- s;
	  self # transition();
	  abort_if_working eng_a;
	  false

  method private transition() =
    (* Compute new state from eng_a_state and eng_b_state: *)
    let state' =
      match self#state with
	  `Working n ->
	    ( match (eng_a_state, eng_b_state) with
		  (`Working _, `Working _) ->
		    `Working (n+1)
		| (`Working _, `Done _) ->
		    `Working (n+1)
		| (`Done _, `Working _) ->
		    `Working (n+1)
		| (`Done a, `Done b) ->
		    `Done (a,b)
		| (`Error x, _) ->
		    `Error x
		| (_, `Error x) ->
		    `Error x
		| (`Aborted, _) ->
		    `Aborted
		| (_, `Aborted) ->
		    `Aborted
	    )
	| _ ->
	    (* The state will never change again! *)
	    self#state
    in
    self # set_state state'

  method abort() =
    eng_a # abort();
    eng_b # abort();
end;;


let sync_engine = new sync_engine


class ['t] epsilon_engine (target_state:'t engine_state) ues : ['t] engine =
  let aborted = ref false in
object(self)
  inherit ['t] engine_mixin (`Working 0) ues

  initializer (
    Unixqueue.epsilon ues
      (fun () -> 
	 if not !aborted then
	   self # set_state target_state
      )
  )

  method abort() =
    aborted := true;
    self # set_state `Aborted
end

let epsilon_engine = new epsilon_engine



class poll_engine ?(extra_match = fun _ -> false) 
                  oplist ues =
  let state = ref (`Working 0) in
object(self)

  inherit [Unixqueue.event] engine_mixin_i state ues

  val mutable group = Unixqueue.new_group ues

  initializer
    self # restart()


  method group = group

  method restart() =
    group <- Unixqueue.new_group ues;
    state := (`Working 0 : Unixqueue.event engine_state);
      (* N.B. set_state would not work here *)
    (* Define the event handler: *)
    Unixqueue.add_handler ues group (fun _ _ -> self # handle_event);
    (* Add the resources: *)
    List.iter (Unixqueue.add_resource ues group) oplist;


  method private handle_event ev =
    match ev with
	Unixqueue.Input_arrived(g,fd) when g = group ->
	  self # accept_event ev
      | Unixqueue.Output_readiness(g,fd) when g = group ->
	  self # accept_event ev
      | Unixqueue.Out_of_band(g,fd) when g = group ->
	  self # accept_event ev
      | Unixqueue.Timeout(g,op) when g = group ->
	  self # accept_event ev
      | Unixqueue.Extra x ->
	  if extra_match x then
	    self # accept_event ev
	  else
	    raise Equeue.Reject
      | _ ->
	  raise Equeue.Reject


  method private accept_event ev =
    Unixqueue.clear ues group;
    self # set_state (`Done ev);


  method private handle_exception x =
    self # set_state (`Error x)


  method abort() =
    match self#state with
	`Working _ ->
	  Unixqueue.clear ues group;
	  self # set_state `Aborted;
      | _ ->
	  ()

  method event_system = ues

end ;;


class ['a] delay_engine t f esys =
  let wid = Unixqueue.new_wait_id esys in
  [_,'a] seq_engine
    (new poll_engine [ Unixqueue.Wait wid, t ] esys)
    (fun _ -> f())


let delay_engine = new delay_engine

let signal_engine esys =
  let wid = Unixqueue.new_wait_id esys in
  let op = Unixqueue.Wait wid in
  let p = new poll_engine [op, (-1.0)] esys in
  let r = ref `Aborted in
  let flag = ref false in
  let e = new map_engine
            ~map_done:(fun _ -> (!r :> _ engine_state))
	    ~map_aborted:(fun _ -> (!r :> _ engine_state)) p in
  let signal st =
    if not !flag then (   (* atomic *)
      r := st;
      flag := true
    );
    (* p#abort() - old implementation *)
    Unixqueue.add_event esys (Unixqueue.Timeout(p#group, op)) in
  (e, signal)


class ['a] signal_engine esys =
  let (e, signal) = signal_engine esys in
object(self)
  inherit ['a] delegate_engine e
  method signal x = signal (x : _ final_state)
end


let timeout_engine d exn eng =
  let esys = eng#event_system in
  let g = Unixqueue.new_group esys in
  let timeout_flag = ref false in
  Unixqueue.once esys g d 
    (fun () ->
       timeout_flag := true;
       eng#abort();
    );
  map_engine
    ~map_done:(fun r -> Unixqueue.clear esys g; `Done r)
    ~map_aborted:(fun _ -> 
		    if !timeout_flag then `Error exn
		    else ( Unixqueue.clear esys g; `Aborted))
    ~map_error:(fun e -> Unixqueue.clear esys g; `Error e)
    eng


class ['a] timeout_engine d exn (eng : _ engine) =
  ['a] delegate_engine(timeout_engine d exn eng)


class poll_process_engine ?(period = 0.1) ~pid ues =
object(self)

  inherit [Unix.process_status] engine_mixin (`Working 0) ues

  val group = Unixqueue.new_group ues
  val wait_id = Unixqueue.new_wait_id ues

  initializer
    (* Define the event handler: *)
    Unixqueue.add_handler ues group (fun _ _ -> self # handle_event);
    (* Define the abort (exception) handler: *)
    Unixqueue.add_abort_action ues group (fun _ -> self # handle_exception);
    (* Add the resources: *)
    Unixqueue.add_resource ues group (Unixqueue.Wait wait_id, period);


  method private handle_event ev =
    match ev with
	Unixqueue.Timeout(g, Unixqueue.Wait wid) 
	                                   when g = group && wid = wait_id ->
	  self # check_process()
      | Unixqueue.Signal ->
	  self # check_process();
	  raise Equeue.Reject    (* Signal must not be accepted! *)
      | _ ->
	  raise Equeue.Reject


  method private check_process () =
    try
      let (w_pid, w_status) = Unix.waitpid [ Unix.WNOHANG ] pid in
      if w_pid > 0 then (
	Unixqueue.clear ues group;
	self # set_state (`Done w_status);
      )
    with
	error ->
	  raise(Unixqueue.Abort(group,error))


  method private handle_exception x =
    self # set_state (`Error x)


  method abort() =
    match self#state with
	`Working _ ->
	  Unixqueue.clear ues group;
	  self # set_state `Aborted;
      | _ ->
	  ()

  method event_system = ues

end ;;


class watchdog period eng =
  let ues = eng#event_system in
  let wid = Unixqueue.new_wait_id ues in
object (self)
  inherit [unit] engine_mixin (`Working 0) ues

  val mutable last_eng_state = eng # state
  val timer_eng = new poll_engine [ Unixqueue.Wait wid, 0.1 *. period ] ues
  val mutable aborted = false
  val mutable inactivity = 0
			     (* Counts to 10 *)

  initializer
    let rec watch() =
      when_state 
	~is_done:(fun _ ->
		    let eng_state = eng # state in
		    if eng_state = last_eng_state then (
		      inactivity <- inactivity + 1;
		      if inactivity >= 10 then (
			aborted <- true;
			self # set_state (`Error Watchdog_timeout)
		      )
		      else (
			timer_eng # restart();
			watch();
		      )
		    )
		    else (
		      last_eng_state <- eng_state;
		      inactivity <- 0;
		      timer_eng # restart();
		      watch()
		    )
		 )
	timer_eng
    in

    watch();

    when_state
      ~is_done:(fun _ -> if not aborted then self # set_state (`Done()))
      ~is_error:(fun _ -> if not aborted then self # set_state (`Done()))
      ~is_aborted:(fun _ -> if not aborted then self # set_state (`Done()))
      eng


  method abort() =
    match self#state with
	`Working _ ->
	  aborted <- true;
	  timer_eng # abort();
	  self # set_state `Aborted;
      | _ ->
	  ()

  method event_system = 
    ues

end ;;


let watchdog = new watchdog


let rec msync_engine l f x0 esys =
  match l with
    | [] ->
	new epsilon_engine (`Done x0) esys
    | [e] ->
	new map_engine
	  ~map_done:(fun r -> `Done (f r x0))
	  e
    | e1 :: l' ->
	new map_engine
	  ~map_done:(fun (r,x) -> `Done (f r x))
	  (new sync_engine e1 (msync_engine l' f x0 esys))


class ['a,'b] msync_engine (l : 'a #engine list) f (x0:'b) esys = 
  ['b] delegate_engine (msync_engine l f x0 esys)


class ['a] serializer (esys : Unixqueue.event_system) =
object(self)
  val mutable running = None
  val mutable queue = Queue.create()

  method serialized ( f : (Unixqueue.event_system -> 'a engine) ) =
    (** Will call [f esys] when it is time to start the engine *)
    let rec next f signal =
      let e = 
	try (f esys : 'a engine)
	with error -> epsilon_engine (`Error error) esys in
      running <- Some e;
      signal e;
      if is_active e#state then 
	when_state
	  ~is_done:(fun _ -> check())
	  ~is_error:(fun _ -> check())
	  ~is_aborted:(fun _ -> check())
	  e
      else (
	Unixqueue.epsilon esys check;
      );
      e
    and check() =
      running <- None; 
      if not (Queue.is_empty queue) then (
	let (f,signal) = Queue.take queue in
	ignore(next f signal)
      )
    in

    match running with
      | Some _ ->
	  (** Create a wrapper engine. When [f] is finally called, the
              wrapper is terminated and "replaced" by the engine returned
              by [f]
	   *)
	  let sig_e, do_signal = signal_engine esys in
	  let eff_e = ref None in
	  let wrap_e =
	    new seq_engine
	      sig_e
	      (fun _ ->
		 match !eff_e with
		   | None -> assert false
		   | Some e -> e
	      ) in
	  let signal e =
	    eff_e := Some e;
	    do_signal(`Done()) in
	  Queue.push (f,signal) queue;
	  wrap_e
      | None ->
	  next f (fun _ -> ())
end

let serializer = new serializer


class ['a] prioritizer (esys : Unixqueue.event_system) =
object(self)
  val mutable prio = 0       (* priority of [running] engines *)
  val mutable running = 0    (* # running engines *)
  val mutable prios = IntSet.empty        (* all waiting priorities *)
  val mutable preempting = false          (* whether there is a bigger prio in prios *)
  val mutable waiting = Hashtbl.create 3  (* the waiting engines by prio *)

  method prioritized f p =
    let rec next f signal =
      running <- running + 1;
      prio <- p;
      let e = 
	try (f esys : 'a engine)
	with error -> epsilon_engine (`Error error) esys in
      signal e;
      if is_active e#state then 
	when_state
	  ~is_done:(fun _ -> check())
	  ~is_error:(fun _ -> check())
	  ~is_aborted:(fun _ -> check())
	  e
      else (
	Unixqueue.epsilon esys check;
      );
      e

    and check () =
      running <- running - 1;
      if running = 0 && prios <> IntSet.empty then (
	let highest = IntSet.min_elt prios in
	prios <- IntSet.remove highest prios;
	preempting <- false;
	let l = 
	  try Hashtbl.find waiting highest with Not_found -> assert false in
	Hashtbl.remove waiting highest;
	List.iter
	  (fun (f,signal) ->
	     ignore(next f signal)
	  )
	  (List.rev l);
      )
    in

    if running = 0 || prio = p || not preempting then (
      (* we can start immediately *)
      next f (fun _ -> ())
    )
    else (
      (* push f onto the queue *)
      let sig_e, do_signal = signal_engine esys in
      let eff_e = ref None in
      let wrap_e =
	seq_engine
	  sig_e
	  (fun _ ->
	     match !eff_e with
	       | None -> assert false
	       | Some e -> e
	  ) in
      let signal e =
	eff_e := Some e;
	do_signal(`Done()) in
      let l = try Hashtbl.find waiting p with Not_found -> [] in
      Hashtbl.replace waiting p ((f,signal)::l);
      prios <- IntSet.add p prios;
      if p < prio then
	preempting <- true;
      wrap_e
    )
end


let prioritizer = new prioritizer


class ['a] cache call_get_e esys =
object(self)
  val mutable value_opt = (None : 'a option)
  val mutable value_gen = 0
  val mutable getting = None

  method get_opt() = value_opt

  method get_engine() =
    match value_opt with
      | None ->
	  ( match getting with
	      | None ->
		  (* No get engine is running. Start a new one *)
		  let get_e = call_get_e esys in
		  getting <- Some get_e;
		  let gen = value_gen in
		  let get_e' =
		    new map_engine
		      ~map_done:(fun v -> 
				   (* There could be a [put] writing: *)
				   if value_gen = gen then (
				     value_opt <- Some v;
				     value_gen <- gen+1
				   );
				   `Done v
				)
		      get_e in
		  get_e'
	      | Some get_e ->
		  (* Some previous user already called [get] but it was
                     not yet finished. For simplicity we return here the
                     same engine. This is ok except that when one user
		     aborts this engine, all other users are also affected.
		   *)
		  get_e
	)

    | Some v ->
	new epsilon_engine (`Done v) esys

  method put v' =
    value_opt <- Some v';
    value_gen <- value_gen + 1

  method invalidate () =
    value_opt <- None;
    value_gen <- value_gen + 1

  method abort() =
    ( match value_opt with
	| None ->
	    ( match getting with
		| None ->
		    ()
		| Some get_e ->
		    get_e # abort()
	    )
	| Some _ -> ()
    );
    self#invalidate()

end

let cache = new cache


class ['a] input_engine f fd tmo esys =
  [Unixqueue.event, 'a]
  seq_engine
    (new poll_engine [ Unixqueue.Wait_in fd, tmo ] esys)
    (fun ev ->
       match ev with
	 | Unixqueue.Input_arrived(_,_) ->
	     ( try
		 let r = f fd in
		 epsilon_engine (`Done r) esys
	       with
		 | error -> epsilon_engine (`Error error) esys
	     )
	 | Unixqueue.Timeout(_,_) ->
	     epsilon_engine (`Error Timeout) esys
	 | _ ->
	     assert false
    )


class ['a] output_engine f fd tmo esys =
  [Unixqueue.event, 'a]
  seq_engine
    (new poll_engine [ Unixqueue.Wait_out fd, tmo ] esys)
    (fun ev ->
       match ev with
	 | Unixqueue.Output_readiness(_,_) ->
	     ( try
		 let r = f fd in
		 epsilon_engine (`Done r) esys
	       with
		 | error -> epsilon_engine (`Error error) esys
	     )
	 | Unixqueue.Timeout(_,_) ->
	     epsilon_engine (`Error Timeout) esys
	 | _ ->
	     assert false
    )


exception Mem_not_supported

class type multiplex_controller =
object
  method alive : bool
  method mem_supported : bool
  method event_system : Unixqueue.event_system
  method tls_session_props : Nettls_support.tls_session_props option
  method tls_session : (string * string) option
  method tls_stashed_endpoint : unit -> exn
  method reading : bool
  method start_reading : 
    ?peek:(unit -> unit) ->
    when_done:(exn option -> int -> unit) -> Bytes.t -> int -> int -> unit
  method start_mem_reading : 
    ?peek:(unit -> unit) ->
    when_done:(exn option -> int -> unit) -> Netsys_mem.memory -> int -> int ->
    unit
  method cancel_reading : unit -> unit
  method writing : bool
  method start_writing :
    when_done:(exn option -> int -> unit) -> Bytes.t -> int -> int -> unit
  method start_mem_writing : 
    when_done:(exn option -> int -> unit) -> Netsys_mem.memory -> int -> int ->
    unit
  method supports_half_open_connection : bool
  method start_writing_eof :
    when_done:(exn option -> unit) -> unit -> unit
  method cancel_writing : unit -> unit
  method read_eof : bool
  method wrote_eof : bool
  method shutting_down : bool
  method start_shutting_down :
    ?linger : float ->
    when_done:(exn option -> unit) -> unit -> unit
  method cancel_shutting_down : unit -> unit
  method inactivate : unit -> unit
end


class type datagram_multiplex_controller =
object
  inherit multiplex_controller
  method received_from : Unix.sockaddr
  method send_to : Unix.sockaddr -> unit
end


type onshutdown_out_spec =
    [ `Ignore
    | `Initiate_shutdown
    | `Action of async_out_channel_engine -> multiplex_controller -> 
                   unit engine_state -> unit
    ]

type onshutdown_in_spec =
    [ `Ignore
    | `Initiate_shutdown
    | `Action of async_in_channel_engine -> multiplex_controller -> 
                   unit engine_state -> unit
    ]


type copy_task =
    [ `Unidirectional of (Unix.file_descr * Unix.file_descr)
    | `Uni_socket of (Unix.file_descr * Unix.file_descr)
    | `Bidirectional of (Unix.file_descr * Unix.file_descr)
    | `Tridirectional of (Unix.file_descr * Unix.file_descr * Unix.file_descr)
    ]
;;


type inetspec =
  [ `Sock_inet of (Unix.socket_type * Unix.inet_addr * int)
  | `Sock_inet_byname of (Unix.socket_type * string * int)
  ]

type sockspec =
  [ `Sock_unix of (Unix.socket_type * string)
  | inetspec
  ]
;;


type connect_address =
    [ `Socket of sockspec * connect_options
    | `Command of string * (int -> Unixqueue.event_system -> unit)
    | `W32_pipe of Netsys_win32.pipe_mode * string
    ]

and connect_options =
    { conn_bind : sockspec option }


type connect_status =
    [ `Socket of Unix.file_descr * sockspec
    | `Command of Unix.file_descr * int
    | `W32_pipe of Unix.file_descr
    ]


class type client_endpoint_connector = object
  method connect : connect_address -> 
                   Unixqueue.event_system ->
		     connect_status engine
end 



type listen_address =
    [ `Socket of sockspec * listen_options
    | `W32_pipe of Netsys_win32.pipe_mode * string * listen_options
    ]

and listen_options =
    { lstn_backlog : int;
      lstn_reuseaddr : bool;
    }
;;


class type server_endpoint_acceptor = object
  method server_address : connect_address
  method multiple_connections : bool
  method accept : unit -> (Unix.file_descr * inetspec option) engine
  method shut_down : unit -> unit
end
;;

class type server_socket_acceptor = server_endpoint_acceptor



class type server_endpoint_listener = object
  method listen : listen_address ->
                  Unixqueue.event_system ->
		    server_endpoint_acceptor engine
end
;;


class type server_socket_listener = server_endpoint_listener


type datagram_type =
    [ `Unix_dgram
    | `Inet_udp
    | `Inet6_udp
    ]
;;


class type wrapped_datagram_socket =
object
  method descriptor : Unix.file_descr
  method sendto : 
    Bytes.t -> int -> int -> Unix.msg_flag list -> sockspec -> int
  method recvfrom : 
    Bytes.t -> int -> int -> Unix.msg_flag list -> (int * sockspec)
  method shut_down : unit -> unit
  method datagram_type : datagram_type
  method socket_domain : Unix.socket_domain
  method socket_type : Unix.socket_type
  method socket_protocol : int
end;;


class type datagram_socket_provider =
object
  method create_datagram_socket : datagram_type ->
                                  Unixqueue.event_system ->
                                    wrapped_datagram_socket engine
end ;;


module Operators = struct
  let ( ++ ) = qseq_engine
  let ( >> ) = fmap_engine
  let eps_e = epsilon_engine
end
