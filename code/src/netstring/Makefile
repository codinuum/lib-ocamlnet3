TOP_DIR=../..

include $(TOP_DIR)/Makefile.conf

OBJECTS  = netconst.cmo netstring_str.cmo netbuffer.cmo netunichar.cmo \
	   netaux.cmo netstring_tstring.cmo \
           netchannels.cmo netchannels_crypto.cmo netsockaddr.cmo \
	   netdb.cmo netmappings_asn1.cmo netmappings.cmo netconversion.cmo \
           netulex.cmo netencoding.cmo netstream.cmo netdate.cmo \
	   netmime_string.cmo \
           nethtml_scanner.cmo nethtml.cmo \
	   neturl.cmo neturl_ldap.cmo netsaslprep_data.cmo netsaslprep.cmo \
	   netaddress.cmo netcompression.cmo \
	   netmime.cmo netmime_header.cmo netmime_channels.cmo \
	   netsendmail.cmo nethttp.cmo \
	   netpagebuffer.cmo netfs.cmo netglob_lex.cmo netglob.cmo \
	   netauth.cmo netnumber.cmo netxdr_mstring.cmo netxdr.cmo \
	   netasn1.cmo netasn1_encode.cmo netoid.cmo netdn.cmo netx509.cmo \
           netascii_armor.cmo netx509_pubkey.cmo netx509_pubkey_crypto.cmo \
	   nettls_support.cmo \
	   netgssapi_support.cmo netgssapi_auth.cmo \
	   netmech_scram.cmo netmech_scram_gssapi.cmo netmech_scram_sasl.cmo \
	   netmech_scram_http.cmo \
	   netmech_plain_sasl.cmo netmech_crammd5_sasl.cmo \
	   netmech_digest.cmo netmech_digest_sasl.cmo \
	   netmech_digest_http.cmo netmech_gs2_sasl.cmo netmech_krb5_sasl.cmo \
	   netmech_spnego_http.cmo

PKGNAME  = netstring

REQUIRES += $(REGEXP_PROVIDER_MAKE) camlp-streams
INCLUDES += $(INC_NETSYS)
INCLUDES += -I ../netstring-pcre

DOBJECTS = netconversion.mli netchannels.mli netstream.mli netmime_string.mli \
	netmime.mli netsendmail.mli neturl.mli netaddress.mli netbuffer.mli \
	netmime_header.mli netmime_channels.mli neturl_ldap.mli \
	netdate.mli netencoding.mli netulex.mli netaccel.mli \
	netaccel_link.mli nethtml.mli netstring_str.mli \
	netmappings.mli netaux.mli nethttp.mli netpagebuffer.mli \
	netfs.mli netglob.mli netauth.mli netsockaddr.mli \
        netnumber.mli netxdr_mstring.mli netxdr.mli \
	netcompression.mli netunichar.mli netasn1.mli netasn1_encode.mli \
	netoid.mli netstring_tstring.mli \
	netdn.mli netx509.mli netascii_armor.mli nettls_support.mli \
	netmech_scram.mli netmech_scram_gssapi.mli netmech_scram_sasl.mli \
        netmech_scram_http.mli \
	netgssapi_support.mli netgssapi_auth.mli netchannels_crypto.mli \
	netx509_pubkey.mli netx509_pubkey_crypto.mli netsaslprep.mli \
	netmech_plain_sasl.mli netmech_crammd5_sasl.mli \
	netmech_digest_sasl.mli netmech_digest_http.mli \
	netmech_krb5_sasl.mli netmech_gs2_sasl.mli netmech_spnego_http.mli \
	netchannels_tut.txt netmime_tut.txt netsendmail_tut.txt \
	netulex_tut.txt neturl_tut.txt

OCAMLC_OPTIONS += $(STRING_OPTS)
OCAMLOPT_OPTIONS += $(STRING_OPTS)

PP_OPTIONS = -pp "$(CPPO) $(NETNUMBER_DEFS) $(REGEXP_DEFS) $(PP_BYTES) $(PP_DEPRECATED)"

ALL_EXTRA = netaccel.cma netaccel_link.cmo netstring_top.cmo

netaccel.cma: netaccel_c.o netaccel.cmo
	$(OCAMLMKLIB) -o netaccel -oc netaccel_c netaccel_c.o netaccel.cmo

NETNUMBER_DEFS = -D WORDSIZE_$(WORD_SIZE) -D HOST_IS_$(ENDIANESS) \
                 -D USE_NETSYS_XDR

OCAMLOPT_OPTIONS_FOR_netbuffer.ml = -inline 10
OCAMLOPT_OPTIONS_FOR_netnumber.ml = -inline 10
OCAMLOPT_OPTIONS_FOR_xdr.ml = -inline 5
OCAMLC_OPTIONS_FOR_netstring_top.ml = -I +compiler-libs

include $(TOP_DIR)/Makefile.rules

distclean::
	$(MAKE) clean

include depend
