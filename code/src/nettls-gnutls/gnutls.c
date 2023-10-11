/* This file is included into nettls_gnutls_bindings_stubs.c */

#include "./config.h"

#include <gnutls/gnutls.h>
#include <gnutls/openpgp.h>
#include <gnutls/x509.h>

#ifdef HAVE_GNUTLS_CRYPTO_H
#include <gnutls/crypto.h>
#endif

#ifdef HAVE_GNUTLS_ABSTRACT_H
#include <gnutls/abstract.h>
#endif

#include <errno.h>

#pragma GCC diagnostic ignored "-Wunused-function"

static int initialized = 0;

void nettls_init(void) {
    int code;
    if (!initialized) {
        code = gnutls_global_init();
        if (code != GNUTLS_E_SUCCESS) {
            fprintf(stderr, "Nettls_gnutls: cannot initialize: %s\n",
                    gnutls_strerror(code));
        }
        else
            initialized = 1;
    }
}


void nettls_deinit(void) {
    if (initialized) {
        gnutls_global_deinit();
        initialized = 0;
    }    
}


typedef int error_code;
typedef unsigned int gnutls_init_flags;
typedef unsigned int key_usage;
typedef const char * const_charp;
typedef gnutls_datum_t str_datum;
typedef gnutls_datum_t * str_datum_p;
typedef const gnutls_datum_t * const_str_datum_p;

#define DUMMY 0

typedef unsigned int empty_flags;
   
#define wrap_const_str_datum_p wrap_str_datum_p
#define unwrap_const_str_datum_p unwrap_str_datum_p

static value wrap_error_code(error_code x);
static value wrap_gnutls_x509_crt_t(gnutls_x509_crt_t x);
static value wrap_gnutls_x509_crl_t(gnutls_x509_crl_t x);

static gnutls_session_t 
           unwrap_gnutls_session_t(value v);
static void
           attach_gnutls_session_t(value v, value aux);
static gnutls_certificate_credentials_t 
           unwrap_gnutls_certificate_credentials_t(value v);
static void
           attach_gnutls_certificate_credentials_t(value v, value aux);
static gnutls_srp_client_credentials_t 
           unwrap_gnutls_srp_client_credentials_t(value v);
static gnutls_srp_server_credentials_t 
           unwrap_gnutls_srp_server_credentials_t(value v);
static gnutls_psk_client_credentials_t 
           unwrap_gnutls_psk_client_credentials_t(value v);
static gnutls_psk_server_credentials_t 
           unwrap_gnutls_psk_server_credentials_t(value v);
static gnutls_anon_client_credentials_t 
           unwrap_gnutls_anon_client_credentials_t(value v);
static gnutls_anon_server_credentials_t 
           unwrap_gnutls_anon_server_credentials_t(value v);
static gnutls_x509_crt_fmt_t 
           unwrap_gnutls_x509_crt_fmt_t(value v);
static gnutls_certificate_import_flags 
           unwrap_gnutls_certificate_import_flags(value v);

#define raise_null_pointer net_gnutls_null_pointer

static void net_gnutls_null_pointer(void) {
    caml_raise_constant(*caml_named_value
                          ("Nettls_gnutls_bindings.Null_pointer"));
}


static const char * unwrap_charp(value dummy) { return NULL; }
   
static value wrap_str_datum(const gnutls_datum_t d) {
    value s;
    s = caml_alloc_string(d.size);
    memcpy(String_val(s), d.data, d.size);
    return s;
}

static value wrap_str_datum_p(const gnutls_datum_t *d) {
    if (d==NULL) net_gnutls_null_pointer();
    return wrap_str_datum(*d);
}
   
static gnutls_datum_t unwrap_str_datum(value v) {
    gnutls_datum_t d;
    d.size = caml_string_length(v);
    d.data = caml_stat_alloc(d.size);
    memcpy(d.data, String_val(v), d.size);
    return d;
}
   
static gnutls_datum_t * unwrap_str_datum_p(value v) {
    gnutls_datum_t *d;
    d = caml_stat_alloc(sizeof(gnutls_datum_t));
    *d = unwrap_str_datum(v);
    return d;
}
   
static void free_str_datum(gnutls_datum_t d) {
    if (d.data != NULL) { caml_stat_free(d.data); d.data = NULL; };
}

static void free_str_datum_p(gnutls_datum_t *d) {
    if (d != NULL) {
        if (d->data != NULL) caml_stat_free(d->data);
        caml_stat_free(d);
    }
}
   
static void net_gnutls_error_check(int error_code) {
    if (error_code < 0) {
        caml_raise_with_arg(*caml_named_value("Nettls_gnutls_bindings.Error"),
                            wrap_error_code(error_code));
    }
}


static void net_gnutls_size_check(int error_code, size_t s) {
    if (error_code == GNUTLS_E_SHORT_MEMORY_BUFFER) {
        caml_raise_with_arg(*caml_named_value
                              ("Nettls_gnutls_bindings.Short_memory_buffer"),
                            Val_long(s));
    }
}


/*
static void net_gnutls_transport_set_int(gnutls_session_t s,long fd) {
    gnutls_transport_set_ptr(s, (gnutls_transport_ptr_t) fd);
}
*/


struct b_session_callbacks_st {
    gnutls_session_t session;
    value pull_fun;            /* memory -> int unix_code */
    value pull_timeout_fun;    /* int -> int unix_code */
    value push_fun;            /* memory -> int -> int unix_code */
    value verify_fun;          /* unit -> bool */
    /* value params_fun; */
    value db_retrieve_fun;     /* string -> string */
    value db_store_fun;        /* string -> string -> unit */
    value db_remove_fun;       /* string -> unit */
};

typedef struct b_session_callbacks_st *b_session_callbacks_t;


static int get_transport_errno(value r) {
    switch (Int_val(r)) {
    case 0:
        return EINTR;
    case 1:
        return EAGAIN;
    case 2:
        return EMSGSIZE;
    case 3:
        return EPERM;
    default:
        return EPERM;
    }    
}


static ssize_t push_callback(gnutls_transport_ptr_t cb_ptr, const void *data,
                     size_t size) {
    b_session_callbacks_t cb;
    int flags;
    ssize_t n;
    CAMLparam0();
    CAMLlocal2(ba,r);

    cb = (b_session_callbacks_t) cb_ptr;
    if (Is_block(cb->push_fun)) {
        flags = CAML_BA_UINT8 | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL;
        ba = caml_ba_alloc_dims(flags, 1, (void *) data, (intnat) size);
        r = caml_callback2_exn(cb->push_fun, ba, Val_long(size));
        if (Is_exception_result(r)) {
            r = Extract_exception(r);
            gnutls_transport_set_errno(cb->session, EPERM);
            n = -1;
        }
        else {
            /* r is an [int unix_code] */
            if (Is_block(r)) {
                n = Long_val(Field(r, 0));
                if (n<0) {
                    gnutls_transport_set_errno(cb->session, EPERM);
                    n = -1;
                }
            }
            else {
                gnutls_transport_set_errno(cb->session, get_transport_errno(r));
                n = -1;
            }
        }
    } else {
        gnutls_transport_set_errno(cb->session, EPERM);
        n = -1;
    };
    CAMLreturn(n);
}


static ssize_t pull_callback(gnutls_transport_ptr_t cb_ptr, void *data,
                     size_t size) {
    b_session_callbacks_t cb;
    int flags;
    ssize_t n;
    CAMLparam0();
    CAMLlocal2(ba,r);

    cb = (b_session_callbacks_t) cb_ptr;
    if (Is_block(cb->pull_fun)) {
        flags = CAML_BA_UINT8 | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL;
        ba = caml_ba_alloc_dims(flags, 1, data, (intnat) size);
        r = caml_callback_exn(cb->pull_fun, ba);
        if (Is_exception_result(r)) {
            r = Extract_exception(r);
            gnutls_transport_set_errno(cb->session, EPERM);
            n = -1;
        }
        else {
            /* r is an [int unix_code] */
            if (Is_block(r)) {
                n = Long_val(Field(r, 0));
                if (n<0) {
                    gnutls_transport_set_errno(cb->session, EPERM);
                    n = -1;
                }
            }
            else {
                gnutls_transport_set_errno(cb->session, get_transport_errno(r));
                n = -1;
            }
        }
    } else {
        gnutls_transport_set_errno(cb->session, EPERM);
        n = -1;
    };
    CAMLreturn(n);
}


static int pull_timeout_callback(gnutls_transport_ptr_t cb_ptr,
                                     unsigned int ms) {
    b_session_callbacks_t cb;
    int n;
    CAMLparam0();
    CAMLlocal1(r);

    cb = (b_session_callbacks_t) cb_ptr;
    if (Is_block(cb->pull_timeout_fun)) {
        r = caml_callback_exn(cb->pull_timeout_fun, Val_int(ms));
        if (Is_exception_result(r)) {
            r = Extract_exception(r);
            gnutls_transport_set_errno(cb->session, EPERM);
            n = -1;
        }
        else {
            /* r is an [int unix_code] */
            if (Is_block(r)) {
                n = Long_val(Field(r, 0));
                if (n<0) {
                    gnutls_transport_set_errno(cb->session, EPERM);
                    n = -1;
                }
            }
            else {
                gnutls_transport_set_errno(cb->session, get_transport_errno(r));
                n = -1;
            }
        }
    } else {
        gnutls_transport_set_errno(cb->session, EPERM);
        n = -1;
    };
    CAMLreturn(n);
}


static int verify_callback(gnutls_session_t s) {
    b_session_callbacks_t cb;
    int n;
    CAMLparam0();
    CAMLlocal1(r);

    cb = (b_session_callbacks_t) gnutls_session_get_ptr(s);
    if (Is_block(cb->verify_fun)) {
        r = caml_callback_exn(cb->verify_fun, Val_unit);
        if (Is_exception_result(r)) {
            r = Extract_exception(r);
            n = 1;
        }
        else
            n = Bool_val(r) ? 0 : 1;
    }
    else 
        n=0;
    CAMLreturn(n);
}


static int db_store_callback(void *ptr, gnutls_datum_t key, 
                             gnutls_datum_t data) {
    b_session_callbacks_t cb;
    int n;
    CAMLparam0();
    CAMLlocal3(r, keyv, datav);

    cb = (b_session_callbacks_t) ptr;
    if (Is_block(cb->db_store_fun)) {
        keyv = wrap_str_datum(key);
        datav = wrap_str_datum(data);
        r = caml_callback2_exn(cb->db_store_fun, keyv, datav);
        if (Is_exception_result(r)) {
            r = Extract_exception(r);
            n = 1;
        }
        else
            n = 0;
    }
    else
        n = 1;
    CAMLreturn(n);
}


static int db_remove_callback(void *ptr, gnutls_datum_t key) {
    b_session_callbacks_t cb;
    int n;
    CAMLparam0();
    CAMLlocal2(r, keyv);

    cb = (b_session_callbacks_t) ptr;
    if (Is_block(cb->db_remove_fun)) {
        keyv = wrap_str_datum(key);
        r = caml_callback_exn(cb->db_remove_fun, keyv);
        if (Is_exception_result(r)) {
            r = Extract_exception(r);
            n = 1;
        }
        else
            n = 0;
    }
    else
        n = 1;
    CAMLreturn(n);
}


static gnutls_datum_t db_retrieve_callback(void *ptr, gnutls_datum_t key) {
    b_session_callbacks_t cb;
    gnutls_datum_t r;
    CAMLparam0();
    CAMLlocal2(keyv, datav);

    r.data = NULL;
    r.size = 0;
    cb = (b_session_callbacks_t) ptr;
    if (Is_block(cb->db_retrieve_fun)) {
        keyv = wrap_str_datum(key);
        datav = caml_callback_exn(cb->db_retrieve_fun, keyv);
        if (Is_exception_result(datav)) {
            datav = Extract_exception(datav);
        }
        else {
            r.size = caml_string_length(datav);
            r.data = gnutls_malloc(r.size);
            memcpy(r.data, String_val(datav), r.size);
        }
    };
    CAMLreturnT(gnutls_datum_t, r);
}


static void attach_session_callbacks (gnutls_session_t s) {
    b_session_callbacks_t cb;

    cb = (b_session_callbacks_t) 
            caml_stat_alloc(sizeof(struct b_session_callbacks_st));
    cb->session = s;
    cb->pull_fun = Val_int(0);
    cb->pull_timeout_fun = Val_int(0);
    cb->push_fun = Val_int(0);
    cb->verify_fun = Val_int(0);
    /* cb->params_fun = Val_int(0); */
    cb->db_retrieve_fun = Val_int(0);
    cb->db_store_fun = Val_int(0);
    cb->db_remove_fun = Val_int(0);

    caml_register_generational_global_root(&(cb->pull_fun));
    caml_register_generational_global_root(&(cb->pull_timeout_fun));
    caml_register_generational_global_root(&(cb->push_fun));
    caml_register_generational_global_root(&(cb->verify_fun));
    /* caml_register_generational_global_root(&(cb->params_fun));*/
    caml_register_generational_global_root(&(cb->db_retrieve_fun));
    caml_register_generational_global_root(&(cb->db_store_fun));
    caml_register_generational_global_root(&(cb->db_remove_fun));

    gnutls_session_set_ptr(s, cb);
    gnutls_transport_set_ptr(s, cb);
    gnutls_db_set_ptr(s, cb);
    gnutls_transport_set_push_function(s, &push_callback);
    gnutls_transport_set_pull_function(s, &pull_callback);
#ifdef HAVE_FUN_gnutls_transport_set_pull_timeout_function
    gnutls_transport_set_pull_timeout_function(s, &pull_timeout_callback);
#endif
    /*
    gnutls_db_set_retrieve_function: see net_b_set_db_callbacks
    gnutls_db_set_remove_function: see net_b_set_db_callbacks
    gnutls_db_set_store_function: see net_b_set_db_callbacks
    */
    /* verify_callback: this is set in net_gnutls_credentials_set for
       the certificate once it is connected with the session. (The
       callback is the same for all sessions, so this is no problem.)
    */
}


static void b_free_session(gnutls_session_t s) {
    b_session_callbacks_t cb;

    cb = gnutls_session_get_ptr(s);
    caml_remove_generational_global_root(&(cb->pull_fun));
    caml_remove_generational_global_root(&(cb->pull_timeout_fun));
    caml_remove_generational_global_root(&(cb->push_fun));
    caml_remove_generational_global_root(&(cb->verify_fun));
    /* caml_remove_generational_global_root(&(cb->params_fun)); */
    caml_remove_generational_global_root(&(cb->db_retrieve_fun));
    caml_remove_generational_global_root(&(cb->db_store_fun));
    caml_remove_generational_global_root(&(cb->db_remove_fun));

    caml_stat_free(cb);
    gnutls_deinit(s);
}


CAMLprim value net_b_set_pull_callback(value sv, value fun) {
    gnutls_session_t s;
    b_session_callbacks_t cb;
    nettls_init();
    s = unwrap_gnutls_session_t(sv);
    cb = gnutls_session_get_ptr(s);
    caml_modify_generational_global_root(&(cb->pull_fun), fun);
    return Val_unit;
}


CAMLprim value net_b_set_pull_timeout_callback(value sv, value fun) {
#ifdef HAVE_FUN_gnutls_transport_set_pull_timeout_function
    gnutls_session_t s;
    b_session_callbacks_t cb;
    nettls_init();
    s = unwrap_gnutls_session_t(sv);
    cb = gnutls_session_get_ptr(s);
    caml_modify_generational_global_root(&(cb->pull_timeout_fun), fun);
    return Val_unit;
#else
    caml_invalid_argument("b_set_pull_timeout_callback");
#endif
}


CAMLprim value net_b_set_push_callback(value sv, value fun) {
    gnutls_session_t s;
    b_session_callbacks_t cb;
    nettls_init();
    s = unwrap_gnutls_session_t(sv);
    cb = gnutls_session_get_ptr(s);
    caml_modify_generational_global_root(&(cb->push_fun), fun);
    return Val_unit;
}


CAMLprim value net_b_set_verify_callback(value sv, value fun) {
#ifdef HAVE_FUN_gnutls_certificate_set_verify_function
    gnutls_session_t s;
    b_session_callbacks_t cb;
    nettls_init();
    s = unwrap_gnutls_session_t(sv);
    cb = gnutls_session_get_ptr(s);
    caml_modify_generational_global_root(&(cb->verify_fun), fun);
    return Val_unit;
#else
    caml_invalid_argument("b_set_verify_callback");
#endif
}


CAMLprim value net_b_set_db_callbacks(value sv,
                                      value store_fun,
                                      value remove_fun,
                                      value retrieve_fun) {
    gnutls_session_t s;
    b_session_callbacks_t cb;
    nettls_init();
    s = unwrap_gnutls_session_t(sv);
    cb = gnutls_session_get_ptr(s);
    gnutls_db_set_retrieve_function(s, &db_retrieve_callback);
    gnutls_db_set_remove_function(s, &db_remove_callback);
    gnutls_db_set_store_function(s, &db_store_callback);
    caml_modify_generational_global_root(&(cb->db_store_fun), store_fun);
    caml_modify_generational_global_root(&(cb->db_remove_fun), remove_fun);
    caml_modify_generational_global_root(&(cb->db_retrieve_fun), retrieve_fun);
    return Val_unit;
}



CAMLprim value net_gnutls_credentials_set(value sess, value creds) {
    gnutls_session_t s;
    int error_code;
    CAMLparam2(sess,creds);
    nettls_init();
    s = unwrap_gnutls_session_t(sess);
    switch (Long_val(Field(creds,0))) {
    case H_Certificate: {
        gnutls_certificate_credentials_t cert;
        cert = unwrap_gnutls_certificate_credentials_t(Field(creds,1));
        error_code = 
            gnutls_credentials_set(s, GNUTLS_CRD_CERTIFICATE, cert);
#ifdef HAVE_FUN_gnutls_certificate_set_verify_function
        if (error_code == 0) 
            gnutls_certificate_set_verify_function(cert, &verify_callback);
#endif
        break;
        }
    case H_Srp_client:
        error_code = 
            gnutls_credentials_set(s,
                                   GNUTLS_CRD_SRP,
                                   unwrap_gnutls_srp_client_credentials_t 
                                     (Field(creds,1))
                                   );
        break;
    case H_Srp_server:
        error_code = 
            gnutls_credentials_set(s,
                                   GNUTLS_CRD_SRP,
                                   unwrap_gnutls_srp_server_credentials_t 
                                     (Field(creds,1))
                                   );
        break;
    case H_Anon_client:
        error_code = 
            gnutls_credentials_set(s,
                                   GNUTLS_CRD_ANON,
                                   unwrap_gnutls_anon_client_credentials_t 
                                     (Field(creds,1))
                                   );
        break;
    case H_Anon_server:
        error_code = 
            gnutls_credentials_set(s,
                                   GNUTLS_CRD_ANON,
                                   unwrap_gnutls_anon_server_credentials_t 
                                     (Field(creds,1))
                                   );
        break;
    case H_Psk_client:
        error_code = 
            gnutls_credentials_set(s,
                                   GNUTLS_CRD_PSK,
                                   unwrap_gnutls_psk_client_credentials_t 
                                     (Field(creds,1))
                                   );
        break;
    case H_Psk_server:
        error_code = 
            gnutls_credentials_set(s,
                                   GNUTLS_CRD_CERTIFICATE,
                                   unwrap_gnutls_psk_server_credentials_t 
                                     (Field(creds,1))
                                   );
        break;
    default:
        caml_failwith("net_gnutls_credentials_set");
    };
    net_gnutls_error_check(error_code);
    attach_gnutls_session_t(sess, creds);
    CAMLreturn(Val_unit);
}


CAMLprim value net_gnutls_x509_crt_list_import(value datav, value formatv, 
                                               value flagsv) {
    gnutls_datum_t data;
    gnutls_x509_crt_fmt_t format;
    unsigned int flags;
    gnutls_x509_crt_t cert1;
    gnutls_x509_crt_t *certs;
    unsigned int n;
    int code, k, alloc_certs;
    CAMLparam3(datav, formatv, flagsv);
    CAMLlocal2(array, crt);

    nettls_init();
    data = unwrap_str_datum(datav);
    format = unwrap_gnutls_x509_crt_fmt_t(formatv);
    flags = unwrap_gnutls_certificate_import_flags(flagsv);

    certs = &cert1;
    n = 1;
    alloc_certs = 0;
    code = gnutls_x509_crt_list_import(certs, &n, &data, format, 
                    flags | GNUTLS_X509_CRT_LIST_IMPORT_FAIL_IF_EXCEED);
    if (code == GNUTLS_E_SHORT_MEMORY_BUFFER) {
        certs = (gnutls_x509_crt_t *) caml_stat_alloc(n * sizeof(void *));
        alloc_certs = 1;
        code = gnutls_x509_crt_list_import(certs, &n, &data, format, 
                                           flags);
    };
    if (code >= 0) {
        array = caml_alloc(code, 0);
        for (k = 0; k < code; k++) {
            crt = wrap_gnutls_x509_crt_t(certs[k]);
            Store_field(array, k, crt);
        };
    };
    if (alloc_certs)
        caml_stat_free(certs);
    net_gnutls_error_check(code);
    CAMLreturn(array);
}


CAMLprim value net_gnutls_x509_crl_list_import(value datav, value formatv, 
                                               value flagsv) {
#ifdef HAVE_FUN_net_gnutls_x509_crl_list_import
    gnutls_datum_t data;
    gnutls_x509_crt_fmt_t format;
    unsigned int flags;
    gnutls_x509_crl_t cert1;
    gnutls_x509_crl_t *certs;
    unsigned int n;
    int code, k, alloc_certs;
    CAMLparam3(datav, formatv, flagsv);
    CAMLlocal2(array, crt);

    nettls_init();
    data = unwrap_str_datum(datav);
    format = unwrap_gnutls_x509_crt_fmt_t(formatv);
    flags = unwrap_gnutls_certificate_import_flags(flagsv);

    certs = &cert1;
    n = 1;
    alloc_certs = 0;
    code = gnutls_x509_crl_list_import(certs, &n, &data, format, 
                    flags | GNUTLS_X509_CRT_LIST_IMPORT_FAIL_IF_EXCEED);
    if (code == GNUTLS_E_SHORT_MEMORY_BUFFER) {
        certs = (gnutls_x509_crl_t *) caml_stat_alloc(n * sizeof(void *));
        alloc_certs = 1;
        code = gnutls_x509_crl_list_import(certs, &n, &data, format, 
                                           flags);
    };
    if (code >= 0) {
        array = caml_alloc(code, 0);
        for (k = 0; k < code; k++) {
            crt = wrap_gnutls_x509_crl_t(certs[k]);
            Store_field(array, k, crt);
        };
    };
    if (alloc_certs)
        caml_stat_free(certs);
    net_gnutls_error_check(code);
    CAMLreturn(array);
#else
    caml_invalid_argument("gnutls_x509_crl_list_import");
#endif
}

static int net_have_crypto(void) {
#ifdef HAVE_FUN_gnutls_cipher_encrypt2
    return 1;
#else
    return 0;
#endif
}


#ifndef HAVE_GNUTLS_ABSTRACT_H
typedef void *gnutls_pubkey_t;
typedef void *gnutls_privkey_t;
static void gnutls_pubkey_deinit(gnutls_pubkey_t key) {}
static void gnutls_privkey_deinit(gnutls_privkey_t key) {}
#endif


static int net_have_pubkey(void) {
#ifdef HAVE_FUN_gnutls_pubkey_encrypt_data
    return 1;
#else
    return 0;
#endif
}
