(* $Id$ *)

type parallelization_type =
    [ `Multi_processing
    | `Multi_threading
    ]
  (** Type of parallelization:
    * - [`Multi_processing] on a single host
    * - [`Multi_threading] on a single host
   *)

type socket_state =
    [ `Enabled | `Disabled | `Restarting of bool | `Down ]
  (** The state of a socket:
    * - [`Enabled]: The controller allows containers to accept connections.
    *   Note that this does not necessarily means that there such containers.
    * - [`Disabled]: It is not allowed to accept new connections. The
    *   socket is kept open, however.
    * - [`Restarting b]: The containers are being restarted. The boolean
    *   argument says whether the socket will be enabled after that.
    * - [`Down]: The socket is down/closed
   *)

type container_id
  (** Identifies a container *)

type container_state =
    [ `Accepting of int * float
    | `Busy
    ]
  (** The container state for workload management:
    * - [`Accepting(n,t)]: The container is accepting further connections.
    *   It currently processes [n] connections. The last connection was
    *   accepted at time [t] (seconds since the epoch).
    * - [`Busy]: The container does not accept connections
   *)

class type controller = 
object
  method ptype : parallelization_type

  method controller_config : controller_config

  method services : (socket_service * socket_controller * workload_manager) list

  method add_service : socket_service -> workload_manager -> unit
    (** Adds a new service. Containers for these services will be started
      * soon.
     *)

  method logger : Netplex_log.logger

  method event_system : unit -> unit

  method restart : unit -> unit
    (** Initiates a restart of all containers: All threads/processes are
      * terminated and replaced by newly initialized ones.
     *)

  method shutdown : unit -> unit
    (** Initiates a shutdown of all containers. It is no longer possible
      * to add new services. When the shutdown has been completed, 
      * the controller will terminate itself.
     *)
end

and controller_config =
object
  method create_logger : controller -> Netplex_log.logger
end
	  
and socket_service =
object
  method name : string
    (** The name of the [socket_service] is used to identify the service
      * in the whole netplex process cluster. Names are hierarchical;
      * name components are separated by dots (e.g. "company.product.service").
      * The prefix "netplex." is reserved for use by Netplex. The name
      * "netplex.controller" refers to the service provided by the
      * controller.
     *)

  method sockets : (string * Unix.file_descr array) list
    (** A [socket_service] consists of a list of supported protocols
      * which are identified by a name. Every protocol is available 
      * on a list of sockets (which may be bound to different addresses).
     *)

  method socket_service_config : socket_service_config
    (** The configuration *)

  method pre_start_hook : controller -> unit
    (** A user-supplied function that is called before the container is
      * created and started. It is called from the process/thread of the
      * controller.
     *)

  method post_start_hook : container -> unit
    (** A user-supplied function that is called after the container is
      * created and started, but before the first service request arrives.
      * It is called from the process/thread of the
      * container.
     *)

  method pre_finish_hook : container -> unit
    (** A user-supplied function that is called just before the container is
      * terminated. It is called from the process/thread of the
      * container.
     *)

  method post_finish_hook : controller -> unit
    (** A user-supplied function that is called after the container is
      * terminated. It is called from the process/thread of the
      * controller.
     *)

  method processor : processor
    (** A user-supplied object to process incoming connections *)

  method create_container : socket_service -> container
    (** {b Internal method.} Called by the controller to create a new
      * container. The container must match the parallelization type of
      * the controller. This call is already done in the process/thread
      * provided for the container.
      *)

end

and socket_service_config =
object
  method name : string
    (** The proposed name for the [socket_service] *)
  method supported_ptypes : parallelization_type list
    (** The supported parallelization types *)
  method protocols : protocol list
    (** This list describes the sockets to create in detail *)
end

and protocol =
object
  method name : string
    (** The protocol name is an arbitrary string identifying groups of
      * sockets serving the same protocol for a [socket_service].
     *)
  method addresses : Unix.sockaddr array
    (** The addresses of the master sockets. (The socket type is always
      * SOCK_STREAM.) The list must be non-empty.
     *)
  method lstn_backlog : int
    (** The backlog (argument of Unix.listen) *)
  method lstn_reuseaddr : bool
    (** Whether to reuse ports immediately *)
  method configure_slave_socket : Unix.file_descr -> unit
    (** A user-supplied function to configure slave sockets (after [accept]).
      * The function is called from the process/thread of the container.
     *)
end

and socket_controller =
object
  method state : socket_state
    (** The current state *)
  method enable : unit -> unit
    (** Enables a disabled socket service again *)
  method disable : unit -> unit
    (** Disable a socket service temporarily *)
  method restart : unit -> unit
    (** Restarts the containers for this socket service only *)
  method shutdown : unit -> unit
    (** Closes the socket service forever, and initiates a shutdown of all
      * containers serving this type of service.
     *)
  method container_state : (container_id * container_state) list

  method start_containers : int -> unit

  method stop_containers : container_id list -> unit

end

and processor =
object
  method process : 
           close:(Unix.file_descr -> unit) ->
           container -> Unix.file_descr -> string -> unit
    (** A user-supplied function that is called when a new socket connection
      * is established. The function can now process the requests arriving
      * over the connection. It is allowed to use the event system of the
      * container, and to return immediately (multiplexing processor). It is 
      * also allowed to process the requests synchronously and to first return
      * to the caller when the connection is terminated. 
      *
      * The function {b must} call [close] to indicate that it processed
      * this connection completely and to close the file descriptor.
      *
      * The string argument is the protocol name.
     *)

  method receive_message :
            container -> string -> string array -> unit

  method receive_admin_message :
            container -> string -> string array -> unit

  method shutdown : unit -> unit
    (** A user-supplied function that is called when a shutdown notification
      * arrives.
     *)
end

and container =
object
  method ptype : parallelization_type
  method socket_service : socket_service

  method event_system : Unixqueue.unix_event_system
    (** The event system the container uses *)

  method start : Unix.file_descr -> unit
    (** {b Internal Method.} Called by the controller to start the container.
      * It is the responsibility of the container to call the 
      * [post_start_hook] and the [pre_finish_hook].
      *
      * The file descriptor is the endpoint of an RPC connection to the
      * controller.
      *
      * When [start] returns the container will be terminated.
     *)

  method shutdown : unit -> unit
    (** Initiates a shutdown of the container. *)

  method ctrl : Rpc_client.t
    (** An RPC client that can be used to send messages to the controller.
      * Only available while [start] is running. It is bound to 
      * [Control.V1].
     *)

  (* TODO: Easy way to log messages *)

end

and workload_manager =
object
  method hello : controller -> unit
    (** Called by the controller when the service is added *)

  method shutdown : unit -> unit
    (** Called by the controller to notify the manager about a shutdown *)

  method adjust : socket_service -> socket_controller -> unit
    (** This function is called by the controller at certain events to
      * adjust the number of available containers. The manager can
      * call [start_containers] and [stop_containers] to change the
      * system.
      *
      * The function is called right after the startup to ensure
      * that there are containers to serve requests. It is also called:
      * - just after a connection has been accepted and before it is
      *   decided which container will have the chance to accept in the
      *   round
      * - after the shutdown of a container
     *)
end
;;