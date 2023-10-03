TOP_DIR=../..

include $(TOP_DIR)/Makefile.conf

PKGNAME = equeue
OBJECTS = equeue.cmo unixqueue_util.cmo unixqueue_pollset.cmo \
          unixqueue_select.cmo unixqueue.cmo \
	  uq_resolver.cmo \
          uq_engines.cmo uq_multiplex.cmo uq_transfer.cmo \
          uq_io.cmo uq_lwt.cmo \
	  uq_libevent.cmo uq_mt.cmo uq_client.cmo uq_server.cmo \
          uq_datagram.cmo uq_socks5.cmo uq_engines_compat.cmo
DOBJECTS = equeue.mli unixqueue.mli unixqueue_pollset.mli \
           unixqueue_select.mli \
	   uq_resolver.mli \
           uq_engines.mli uq_multiplex.mli uq_transfer.mli \
           uq_socks5.mli uq_io.mli uq_lwt.mli \
	   uq_libevent.mli uq_mt.mli uq_client.mli uq_server.mli  \
	   uq_datagram.mli uq_engines_compat.mli \
           equeue_intro.txt equeue_howto.txt

INCLUDES += $(INC_NETSYS)
INCLUDES += $(INC_NETSTRING)

REQUIRES += camlp-streams

OCAMLC_OPTIONS += $(STRING_OPTS)
OCAMLOPT_OPTIONS += $(STRING_OPTS)

PP_OPTIONS = -pp "$(CPPO) $(PP_BYTES) $(PP_DEPRECATED)"

include $(TOP_DIR)/Makefile.rules

include depend
