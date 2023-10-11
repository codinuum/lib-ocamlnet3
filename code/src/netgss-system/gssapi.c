/* This file is included into netgss_bindings_stubs.c */

#ifdef __APPLE__
#include <GSS/gssapi.h>
#else
#ifdef NETGSS_VARIANT_INCLUDE_GSS
#include <gss.h>
#else
#include <gssapi.h>
#endif
#endif

/* In the following tag=0 means that the value was allocated by the GSSAPI
   provider, and needs to be deallocated by the special GSSAPI function for
   this purpose. tag=1 means that we allocated the value, and are also
   responsible for freeing it. tag=2 means something special.
*/

static value twrap_gss_buffer_t(long tag, gss_buffer_t buf);
static value twrap_gss_OID(long tag, gss_OID oid);
static value twrap_gss_OID_set(long tag, gss_OID_set set);
static value  wrap_gss_channel_bindings_t(gss_channel_bindings_t cb);
static value  wrap_gss_ctx_id_t(gss_ctx_id_t ctx);
static value  wrap_gss_cred_id_t(gss_cred_id_t cred);
static value  wrap_gss_name_t(gss_name_t name);
static value  wrap_gss_OID(gss_OID oid);
static value  wrap_gss_OID_set(gss_OID_set set);

static gss_buffer_t unwrap_gss_buffer_t(value);
static gss_OID      unwrap_gss_OID(value);
static gss_OID_set  unwrap_gss_OID_set(value);
static gss_ctx_id_t unwrap_gss_ctx_id_t(value);
static gss_name_t   unwrap_gss_name_t(value);
static gss_cred_id_t unwrap_gss_cred_id_t(value);

static long         tag_gss_buffer_t(value);

static void attach_gss_buffer_t(value, value);


typedef OM_uint32 flags;
typedef int status_type_t;


#define raise_null_pointer netgss_null_pointer

static void netgss_null_pointer(void) {
    caml_raise_constant(*caml_named_value
                          ("Netgss_bindings.Null_pointer"));
}


static void netgss_free_buffer_contents(long tag, gss_buffer_t buf) {
    if (buf->value != NULL) {
        if (tag == 0) {
            OM_uint32 major, minor;
            major = gss_release_buffer(&minor, buf);
            if ((major & 0xffff0000) != 0)
                fprintf(stderr, "Netgss: error from gss_release_buffer\n");
        } else {
            if (tag == 1) {
                caml_stat_free(buf->value);
            }
        }
    }
    buf->value = NULL;
    buf->length = 0;
}


static void netgss_free_buffer(long tag, gss_buffer_t buf) {
    netgss_free_buffer_contents(tag, buf);
    /* The descriptor is always allocated by us: */
    caml_stat_free(buf);
}


static gss_buffer_t netgss_alloc_buffer(void) {
    gss_buffer_t buf;
    buf = (gss_buffer_t) caml_stat_alloc(sizeof(gss_buffer_desc));
    buf->value = NULL;
    buf->length = 0;
    return buf;
}


static void init_gss_buffer_t(gss_buffer_t *p) {
    gss_buffer_t buf;
    buf = netgss_alloc_buffer();
    buf->length = 0;
    buf->value = NULL;
    *p = buf;
}


CAMLprim value netgss_release_buffer(value b) {
    gss_buffer_t buf;
    buf = unwrap_gss_buffer_t(b);
    netgss_free_buffer_contents(tag_gss_buffer_t(b), buf);
    return Val_unit;
}


CAMLprim value netgss_buffer_of_string(value s, value pos, value len) {
    gss_buffer_t buf;
    if (Long_val(len) < 0 || Long_val(pos) < 0 ||
        Long_val(pos) > caml_string_length(s) - Long_val(len))
        caml_invalid_argument("buffer_of_string");
    buf = netgss_alloc_buffer();
    buf->length = Long_val(len);
    buf->value = caml_stat_alloc(buf->length);
    memcpy(buf->value, String_val(s) + Long_val(pos), buf->length);
    return twrap_gss_buffer_t(1, buf);
}


CAMLprim value netgss_buffer_of_memory(value m) {
    value r;
    gss_buffer_t buf;
    buf = netgss_alloc_buffer();
    buf->length = caml_ba_byte_size(Caml_ba_array_val(m));
    buf->value = Caml_ba_data_val(m);
    r = twrap_gss_buffer_t(2, buf);
    attach_gss_buffer_t(r, m);
    return r;
}


CAMLprim value netgss_string_of_buffer(value b) {
    gss_buffer_t buf;
    value s;
    buf = unwrap_gss_buffer_t(b);
    if (buf->value == NULL) {
        s = caml_alloc_string(0);
    } else {
        s = caml_alloc_string(buf->length);
        memcpy(String_val(s), buf->value, buf->length);
    }
    return s;
}


CAMLprim value netgss_memory_of_buffer(value b) {
    gss_buffer_t buf;
    value m;
    buf = unwrap_gss_buffer_t(b);
    if (buf->value == NULL) netgss_null_pointer();
    m = caml_ba_alloc_dims(CAML_BA_UINT8 | CAML_BA_C_LAYOUT, 1,
                           buf->value, buf->length);
    return m;
}


static void netgss_free_oid(long tag, gss_OID buf) {
    if (tag == 0 || buf == GSS_C_NO_OID) {
        /* OIDs from the provider are to be considered as read-only */
    } else {
        caml_stat_free(buf->elements);
        caml_stat_free(buf);
    }
}


static gss_OID netgss_alloc_oid(void) {
    return (gss_OID) caml_stat_alloc(sizeof(gss_OID_desc));
}


static gss_OID netgss_copy_oid(gss_OID buf) {
    gss_OID out;
    if (buf == GSS_C_NO_OID) {
        out = GSS_C_NO_OID;
    } else {
        out = netgss_alloc_oid();
        out->length = buf->length;
        out->elements = caml_stat_alloc(buf->length);
        memcpy(out->elements, buf->elements, buf->length);
    }
    return out;
}


CAMLprim value netgss_oid_of_string(value s) {
    gss_OID buf;
    buf = netgss_alloc_oid();
    buf->length = caml_string_length(s);
    buf->elements = caml_stat_alloc(buf->length);
    memcpy(buf->elements, String_val(s), buf->length);
    return twrap_gss_OID(1, buf);
}


CAMLprim value netgss_string_of_oid(value b) {
    gss_OID buf;
    value s;
    buf = unwrap_gss_OID(b);
    if (buf == GSS_C_NO_OID) 
        caml_raise_not_found();
    s = caml_alloc_string(buf->length);
    memcpy(String_val(s), buf->elements, buf->length);
    return s;
}


static void netgss_free_oid_set(long tag, gss_OID_set set) {
    if (tag == 0 || set == GSS_C_NO_OID_SET) {
        OM_uint32 major, minor;
        major = gss_release_oid_set(&minor, &set);
        if ((major & 0xffff0000) != 0)
            fprintf(stderr, "Netgss: error from gss_release_oid_set\n");
    } else {
        size_t k;
        for (k=0; k < set->count; k++) {
            netgss_free_oid(1, set->elements+k);
        }
        caml_stat_free(set->elements);
        caml_stat_free(set);
    }
}


static gss_OID_set netgss_alloc_oid_set(void) {
    return (gss_OID_set) caml_stat_alloc(sizeof(gss_OID_set_desc));
}


CAMLprim value netgss_array_of_oid_set(value varg) {
    CAMLparam1(varg);
    CAMLlocal2(v1, v2);
    gss_OID_set set;
    size_t k, count;
    set = unwrap_gss_OID_set(varg);
    if (set == GSS_C_NO_OID_SET)
        count = 0;
    else
        count = set->count;
    /* no other way than to always copy the members */
    v1 = caml_alloc(count, 0);
    for (k=0; k<count; k++) {
        v2 = twrap_gss_OID(1, netgss_copy_oid(set->elements+k));
        Store_field(v1, k, v2);
    }
    CAMLreturn(v1);
}


CAMLprim value netgss_oid_set_of_array(value varg) {
    gss_OID_set set;
    gss_OID buf;
    gss_OID *p;
    size_t k;
    value v1;
    if (Wosize_val(varg) == 0)
        return twrap_gss_OID_set(1, GSS_C_NO_OID_SET);
    set = netgss_alloc_oid_set();
    set->count = Wosize_val(varg);
    set->elements = caml_stat_alloc(sizeof(gss_OID) * set->count);
    for (k=0; k<set->count; k++) {
        v1 = Field(varg, k);
        buf = unwrap_gss_OID(v1);
        p = &(set->elements) + k;
        *p = netgss_copy_oid(buf);
    }
    return twrap_gss_OID_set(1, set);
}


static void netgss_free_cred_id(long tag, gss_cred_id_t x) {
    OM_uint32 major, minor;
    if (x != GSS_C_NO_CREDENTIAL) {
        major = gss_release_cred(&minor, &x);
        if ((major & 0xffff0000) != 0)
            fprintf(stderr, "Netgss: error from gss_release_cred\n");
    }
}


static void netgss_free_ctx_id(long tag, gss_ctx_id_t x) {
    OM_uint32 major, minor;
    if (x != GSS_C_NO_CONTEXT) {
        major = gss_delete_sec_context(&minor, &x, GSS_C_NO_BUFFER);
        if ((major & 0xffff0000) != 0)
            fprintf(stderr, "Netgss: error from gss_delete_sec_context\n");
    }
}


static void netgss_free_name(long tag, gss_name_t x) {
    OM_uint32 major, minor;
    if (x != GSS_C_NO_NAME) {
        major = gss_release_name(&minor, &x);
        if ((major & 0xffff0000) != 0)
            fprintf(stderr, "Netgss: error from gss_release_name\n");
    }
}


CAMLprim value netgss_no_cb(value dummy) {
    return wrap_gss_channel_bindings_t(GSS_C_NO_CHANNEL_BINDINGS);
}


CAMLprim value netgss_map_cb(value iaddrty, value iaddr, value aaddrty,
                             value aaddr, value data) {
    gss_channel_bindings_t cb;
    size_t iaddr_len, aaddr_len, data_len;
    iaddr_len = caml_string_length(iaddr);
    aaddr_len = caml_string_length(aaddr);
    data_len = caml_string_length(data);
    cb = (gss_channel_bindings_t)
            caml_stat_alloc(sizeof(struct gss_channel_bindings_struct));
    cb->initiator_addrtype = Int_val(iaddrty);
    cb->initiator_address.length = iaddr_len;
    cb->initiator_address.value = caml_stat_alloc(iaddr_len);
    memcpy(cb->initiator_address.value, String_val(iaddr), iaddr_len);
    cb->acceptor_addrtype = Int_val(aaddrty);
    cb->acceptor_address.length = aaddr_len;
    cb->acceptor_address.value = caml_stat_alloc(aaddr_len);
    memcpy(cb->acceptor_address.value, String_val(aaddr), aaddr_len);
    cb->application_data.length = data_len;
    cb->application_data.value = caml_stat_alloc(data_len);
    memcpy(cb->application_data.value, String_val(data), data_len);
    return wrap_gss_channel_bindings_t(cb);
}


CAMLprim value netgss_no_ctx(value dummy) {
    return wrap_gss_ctx_id_t(GSS_C_NO_CONTEXT);
}

CAMLprim value netgss_is_no_ctx(value context) {
    gss_ctx_id_t ctx;
    ctx = unwrap_gss_ctx_id_t(context);
    return Val_bool(ctx == GSS_C_NO_CONTEXT);
}

CAMLprim value netgss_no_cred(value dummy) {
    return wrap_gss_cred_id_t(GSS_C_NO_CREDENTIAL);
}

CAMLprim value netgss_is_no_cred(value cred) {
    return Val_bool(unwrap_gss_cred_id_t(cred) == GSS_C_NO_CREDENTIAL);
}

CAMLprim value netgss_no_name(value dummy) {
    return wrap_gss_name_t(GSS_C_NO_NAME);
}

CAMLprim value netgss_is_no_name(value name) {
    return Val_bool(unwrap_gss_name_t(name) == GSS_C_NO_NAME);
}

CAMLprim value netgss_indefinite(value dummy) {
    return caml_copy_int32(GSS_C_INDEFINITE);
}

CAMLprim value netgss_no_oid(value dummy) {
    return wrap_gss_OID(GSS_C_NO_OID);
}

CAMLprim value netgss_no_oid_set(value dummy) {
    return wrap_gss_OID_set(GSS_C_NO_OID_SET);
}

static void netgss_free_cb(gss_channel_bindings_t x) {
    if (x != NULL) {
        caml_stat_free(x->initiator_address.value);
        caml_stat_free(x->acceptor_address.value);
        caml_stat_free(x->application_data.value);
    }
}
