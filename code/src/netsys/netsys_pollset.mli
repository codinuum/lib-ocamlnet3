(* $Id$ *)

(** Sets of file descriptors for polling *)

class type pollset =
object
  method find : Unix.file_descr -> Netsys.poll_in_events
    (** Checks whether a descriptor is member of the set, and returns
        its event mask. Raises [Not_found] if the descriptor is not in the set.
     *)

  method add : Unix.file_descr -> Netsys.poll_in_events -> unit
    (** Add a descriptor or modify an existing descriptor *)

  method remove : Unix.file_descr -> unit
    (** Remove a descriptor from the set (if it is member) *)

  method wait : float -> 
                ( Unix.file_descr * 
		  Netsys.poll_in_events * 
		  Netsys.poll_out_events ) list
    (** Wait for events, and return the output events matching the event
        mask. This is level-triggered polling, i.e. if a descriptor continues
        to match an event mask, it is again reported the next time [wait]
        is invoked.

        There is no guarantee that the list is complete.

        It is unspecified how the set reacts on descriptors that became
        invalid (i.e. are closed) while being member of the set. The set
        implementation is free to silently disregard such descriptors,
        or to report them as invalid. It is strongly recommended to
        remove descriptors before closing them.
     *)

  method dispose : unit -> unit
    (** Release any OS resources associated with the poll set. *)

  method cancel_wait : unit -> unit
    (** Cancel any [wait] invocation that has been started in a different
        thread. [wait] will immediately time out. Note that there is no
        protection against race conditions: It is possible that [wait]
        returns events that are found at the same time the cancellation
        is carried out, i.e. you cannot rely on that the list returned
        by [wait] is empty.

        This is the only method of a pollset that is allowed to be started
        in a different thread. In single-threaded programs, this method
        is a no-op. If not supported on a platform this method will
        fail.
     *)

end
