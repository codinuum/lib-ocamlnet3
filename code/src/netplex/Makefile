TOP_DIR=../..

include $(TOP_DIR)/Makefile.conf

PKGNAME  = netplex
OBJECTS  = netplex_types.cmo \
	   netplex_ctrl_aux.cmo netplex_ctrl_clnt.cmo netplex_ctrl_srv.cmo \
           netplex_util.cmo netplex_encap.cmo netplex_internal.cmo \
	   netplex_cenv.cmo netplex_mp.cmo netplex_mt.cmo netplex_log.cmo \
           netplex_container.cmo netplex_sockserv.cmo netplex_workload.cmo \
	   netplex_kit.cmo netplex_sharedvar.cmo netplex_controller.cmo \
           netplex_config.cmo netplex_main.cmo rpc_netplex.cmo \
           netplex_semaphore.cmo netplex_mutex.cmo \
	   netplex_mbox.cmo
DOBJECTS = netplex_types.mli netplex_mp.mli netplex_mt.mli netplex_log.mli \
	   netplex_controller.mli netplex_container.mli \
	   netplex_sockserv.mli netplex_workload.mli netplex_main.mli \
	   netplex_config.mli netplex_kit.mli rpc_netplex.mli \
	   netplex_cenv.mli netplex_semaphore.mli netplex_sharedvar.mli \
	   netplex_mutex.mli netplex_encap.mli netplex_mbox.mli \
	   netplex_internal.mli \
	   netplex_intro.txt netplex_advanced.txt netplex_admin.txt

OCAMLC_OPTIONS += $(STRING_OPTS)
OCAMLOPT_OPTIONS += $(STRING_OPTS)

PP_OPTIONS = -pp "$(CPPO) $(PP_BYTES) $(PP_DEPRECATED)"

REQUIRES += camlp-streams

INCLUDES += $(INC_EQUEUE) $(INC_RPC) $(INC_NETSTRING) $(INC_NETSYS)

ALL_EXTRA = netplex-admin$(EXEC_SUFFIX) netplex-packlist 

PACKLIST = netplex-packlist

include $(TOP_DIR)/Makefile.rules

netplex-admin$(EXEC_SUFFIX): netplex.cma netplex_admin.cmo
	$(OCAMLC) -o netplex-admin -custom \
	        -package "bytes unix str" -linkpkg \
		netsys_oothr.cma netsys.cma netstring.cma equeue.cma \
		rpc.cma netplex.cma netplex_admin.cmo

netplex-packlist:
	echo $(BINDIR)/netplex-admin >netplex-packlist

include depend
