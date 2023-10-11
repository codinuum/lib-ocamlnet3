.PHONY: all
all: chtml.cmo chtml.cmxs x_to_odoc

chtml.ml:
	case `ocamlc -version` in 				\
	    3\.*) ln -s chtml_ocaml3.ml chtml.ml ;;		\
	    *) ln -s chtml_ocaml4.ml chtml.ml ;;		\
	esac

chtml.cmo: chtml.ml
	ocamlc -I +str -I +ocamldoc -I +compiler-libs -c chtml.ml

chtml.cmxs: chtml.ml
	-ocamlopt -I +str -I +ocamldoc -I +compiler-libs -shared chtml.ml -o chtml.cmxs

x_to_odoc: x_to_odoc.ml
	ocamlc -o x_to_odoc str.cma x_to_odoc.ml

.PHONY: clean
clean:
	rm -f *.cmi *.cmo *.cmx *.cmxs *.o
	rm -f x_to_odoc
	rm -f chtml.ml

.PHONY: CLEAN
CLEAN: clean

.PHONY: distclean
distclean: clean
