/*
 * RingCFFI - Typed value read/write, bitfield access, and Ring value pushing
 * Author: Youssef Saeed <youssefelkholey@gmail.com>
 * Copyright (c) 2026
 */

#include "ring_cffi_internal.h"

#if defined(FFI_TARGET_HAS_INT128) && defined(__SIZEOF_INT128__)
typedef __int128 cffi_i128;
typedef unsigned __int128 cffi_u128;
#endif

#ifndef LDBL_DECIMAL_DIG
#define LDBL_DECIMAL_DIG 21
#endif

bool ffi_parse_i128(const char *s, void *out, bool is_unsigned)
{
#if defined(FFI_TARGET_HAS_INT128) && defined(__SIZEOF_INT128__)
	if (!s || !out)
		return false;
	const char *p = s;
	while (isspace((unsigned char)*p))
		p++;
	bool neg = false;
	if (*p == '-') {
		neg = true;
		p++;
	} else if (*p == '+') {
		p++;
	}
	if (!*p || *p < '0' || *p > '9')
		return false;

	/* Magnitude limit: UINT128_MAX for unsigned, 2^127 for signed
	   (the min-int magnitude), 2^127-1 for positive signed. */
	cffi_u128 limit =
		is_unsigned ? ~(cffi_u128)0 : (neg ? ((cffi_u128)1 << 127) : (((cffi_u128)1 << 127) - 1));
	cffi_u128 acc = 0;
	while (*p) {
		if (*p < '0' || *p > '9')
			return false;
		unsigned digit = (unsigned)(*p - '0');
		if (acc > (limit - digit) / 10)
			return false; /* overflow */
		acc = acc * 10 + digit;
		p++;
	}

	if (is_unsigned) {
		if (neg)
			return false;
		*(cffi_u128 *)out = acc;
	} else if (neg) {
		/* acc == 2^127 is INT128_MIN; the bit pattern is what two's
		   complement stores, so write the magnitude directly. */
		if (acc == ((cffi_u128)1 << 127)) {
			*(cffi_u128 *)out = acc;
		} else {
			*(cffi_i128 *)out = -(cffi_i128)acc;
		}
	} else {
		*(cffi_i128 *)out = (cffi_i128)acc;
	}
	return true;
#else
	(void)s;
	(void)out;
	(void)is_unsigned;
	return false;
#endif
}

size_t ffi_format_i128(char *buf, size_t sz, const void *src, bool is_unsigned)
{
#if defined(FFI_TARGET_HAS_INT128) && defined(__SIZEOF_INT128__)
	cffi_i128 signed_val = 0;
	cffi_u128 val;
	if (is_unsigned) {
		val = *(const cffi_u128 *)src;
	} else {
		signed_val = *(const cffi_i128 *)src;
		/* Magnitude via two's-complement negation on the unsigned view —
		   avoids UB (and the wrong digits) for INT128_MIN. */
		val = (cffi_u128)signed_val;
		val = ~val + 1;
		if (signed_val >= 0)
			val = (cffi_u128)signed_val;
	}

	char tmp[64];
	int n = 0;
	if (val == 0) {
		tmp[n++] = '0';
	} else {
		while (val > 0) {
			tmp[n++] = (char)('0' + (int)(val % 10));
			val /= 10;
		}
	}
	if (!is_unsigned && signed_val < 0)
		tmp[n++] = '-';

	size_t need = (size_t)n + 1;
	if (sz < need) {
		if (sz > 0)
			buf[0] = '\0';
		return need;
	}
	for (int i = 0; i < n; i++)
		buf[i] = tmp[n - 1 - i];
	buf[n] = '\0';
	return need;
#else
	(void)src;
	(void)is_unsigned;
	if (sz > 0)
		buf[0] = '\0';
	return 1;
#endif
}

bool ffi_parse_ld(const char *s, long double *out)
{
	if (!s || !out)
		return false;
	char *end = NULL;
	errno = 0;
	long double v = strtold(s, &end);
	if (end == s)
		return false;
	while (end && isspace((unsigned char)*end))
		end++;
	if (*end != '\0')
		return false;
	*out = v;
	return true;
}

size_t ffi_format_ld(char *buf, size_t sz, long double v)
{
	/* LDBL_DECIMAL_DIG significant digits round-trip exactly through
	   strtold (21 for the x87 80-bit format). */
	char tmp[128];
	int n = snprintf(tmp, sizeof(tmp), "%.*Lg", (int)LDBL_DECIMAL_DIG, v);
	if (n < 0)
		n = 0;
	if (n >= (int)sizeof(tmp))
		n = (int)sizeof(tmp) - 1;
	size_t need = (size_t)n + 1;
	if (sz < need) {
		if (sz > 0)
			buf[0] = '\0';
		return need;
	}
	memcpy(buf, tmp, (size_t)n + 1);
	return need;
}

void ffi_complex_read_components(void *src, FFI_Type *type, double *re, double *im)
{
	switch (type->kind) {
	case FFI_KIND_COMPLEX_FLOAT:
		*re = (double)((float *)src)[0];
		*im = (double)((float *)src)[1];
		break;
	case FFI_KIND_COMPLEX_DOUBLE:
		*re = ((double *)src)[0];
		*im = ((double *)src)[1];
		break;
	case FFI_KIND_COMPLEX_LONGDOUBLE:
		*re = (double)((long double *)src)[0];
		*im = (double)((long double *)src)[1];
		break;
	default:
		*re = 0.0;
		*im = 0.0;
		break;
	}
}

bool ffi_complex_pack(void *dst, FFI_Type *type, double re, double im)
{
	if (!dst || !type)
		return false;
	switch (type->kind) {
	case FFI_KIND_COMPLEX_FLOAT:
		((float *)dst)[0] = (float)re;
		((float *)dst)[1] = (float)im;
		return true;
	case FFI_KIND_COMPLEX_DOUBLE:
		((double *)dst)[0] = re;
		((double *)dst)[1] = im;
		return true;
	case FFI_KIND_COMPLEX_LONGDOUBLE:
		((long double *)dst)[0] = (long double)re;
		((long double *)dst)[1] = (long double)im;
		return true;
	default:
		return false;
	}
}

double ffi_read_typed_value(void *src, FFI_Type *type)
{
	if (FFI_IS_POINTER_TYPE(type)) {
		return (double)(uintptr_t)*(void **)src;
	}
	switch (type->kind) {
	case FFI_KIND_INT8:
	case FFI_KIND_SCHAR:
	case FFI_KIND_CHAR:
		return (double)*(int8_t *)src;
	case FFI_KIND_UINT8:
	case FFI_KIND_UCHAR:
	case FFI_KIND_BOOL:
		return (double)*(uint8_t *)src;
	case FFI_KIND_INT16:
	case FFI_KIND_SHORT:
		return (double)*(int16_t *)src;
	case FFI_KIND_UINT16:
	case FFI_KIND_USHORT:
		return (double)*(uint16_t *)src;
	case FFI_KIND_INT32:
	case FFI_KIND_INT:
		return (double)*(int32_t *)src;
	case FFI_KIND_UINT32:
	case FFI_KIND_UINT:
		return (double)*(uint32_t *)src;
	case FFI_KIND_INT64:
	case FFI_KIND_LONGLONG:
	case FFI_KIND_SSIZE_T:
	case FFI_KIND_INTPTR_T:
	case FFI_KIND_PTRDIFF_T:
		return (double)*(int64_t *)src;
	case FFI_KIND_UINT64:
	case FFI_KIND_ULONGLONG:
	case FFI_KIND_SIZE_T:
	case FFI_KIND_UINTPTR_T:
		return (double)*(uint64_t *)src;
	case FFI_KIND_LONG:
		return (double)*(long *)src;
	case FFI_KIND_ULONG:
		return (double)*(unsigned long *)src;
	case FFI_KIND_FLOAT:
		return (double)*(float *)src;
	case FFI_KIND_DOUBLE:
		return *(double *)src;
	case FFI_KIND_LONGDOUBLE:
		return (double)*(long double *)src;
	default:
		return (double)*(int *)src;
	}
}

void ffi_write_typed_value(void *dst, FFI_Type *type, double val)
{
	if (FFI_IS_POINTER_TYPE(type)) {
		*(void **)dst = (void *)(uintptr_t)val;
		return;
	}
	switch (type->kind) {
	case FFI_KIND_INT8:
	case FFI_KIND_SCHAR:
	case FFI_KIND_CHAR:
		*(int8_t *)dst = (int8_t)val;
		break;
	case FFI_KIND_UINT8:
	case FFI_KIND_UCHAR:
	case FFI_KIND_BOOL:
		*(uint8_t *)dst = (uint8_t)val;
		break;
	case FFI_KIND_INT16:
	case FFI_KIND_SHORT:
		*(int16_t *)dst = (int16_t)val;
		break;
	case FFI_KIND_UINT16:
	case FFI_KIND_USHORT:
		*(uint16_t *)dst = (uint16_t)val;
		break;
	case FFI_KIND_INT32:
	case FFI_KIND_INT:
		*(int32_t *)dst = (int32_t)val;
		break;
	case FFI_KIND_UINT32:
	case FFI_KIND_UINT:
		*(uint32_t *)dst = (uint32_t)val;
		break;
	case FFI_KIND_INT64:
	case FFI_KIND_LONGLONG:
	case FFI_KIND_SSIZE_T:
	case FFI_KIND_INTPTR_T:
	case FFI_KIND_PTRDIFF_T:
		*(int64_t *)dst = (int64_t)val;
		break;
	case FFI_KIND_UINT64:
	case FFI_KIND_ULONGLONG:
	case FFI_KIND_SIZE_T:
	case FFI_KIND_UINTPTR_T:
		*(uint64_t *)dst = (uint64_t)val;
		break;
	case FFI_KIND_LONG:
		*(long *)dst = (long)val;
		break;
	case FFI_KIND_ULONG:
		*(unsigned long *)dst = (unsigned long)val;
		break;
	case FFI_KIND_FLOAT:
		*(float *)dst = (float)val;
		break;
	case FFI_KIND_DOUBLE:
		*(double *)dst = val;
		break;
	case FFI_KIND_LONGDOUBLE:
		*(long double *)dst = (long double)val;
		break;
	default:
		*(int *)dst = (int)val;
		break;
	}
}

void ffi_push_to_ring(VM *vm, void *src, FFI_Type *type, bool is_ffi_arg)
{
	if (type->kind == FFI_KIND_VOID) {
		ring_vm_api_retnumber(vm, 0);
	} else if (type->kind == FFI_KIND_STRING && type->pointer_depth == 0) {
		char *str_val = *(char **)src;
		if (str_val)
			ring_vm_api_retstring(vm, str_val);
		else
			ring_vm_api_retcpointer(vm, NULL, "FFI_Ptr");
	} else if (FFI_IS_POINTER_TYPE(type)) {
		ring_vm_api_retcpointer(vm, *(void **)src, "FFI_Ptr");
	} else if (ffi_is_int128(type->kind)) {
		char buf[64];
		ffi_format_i128(buf, sizeof(buf), src, type->kind == FFI_KIND_UINT128);
		ring_vm_api_retstring(vm, buf);
	} else if (ffi_is_64bit_int(type->kind)) {
		uint64_t uval;
		int64_t ival;
		int is_unsigned = (type->kind == FFI_KIND_UINT64 || type->kind == FFI_KIND_ULONGLONG ||
						   (type->kind == FFI_KIND_SIZE_T && sizeof(size_t) == 8) ||
						   (type->kind == FFI_KIND_UINTPTR_T && sizeof(uintptr_t) == 8) ||
						   (type->kind == FFI_KIND_ULONG && sizeof(unsigned long) == 8));
		if (is_unsigned) {
			uval = *(uint64_t *)src;
		} else {
			ival = *(int64_t *)src;
			uval = (uint64_t)ival;
		}
		if (uval <= (1ULL << 53)) {
			ring_vm_api_retnumber(vm, is_unsigned ? (double)uval : (double)ival);
		} else {
			char buf[32];
			if (is_unsigned)
				snprintf(buf, sizeof(buf), "%llu", (unsigned long long)uval);
			else
				snprintf(buf, sizeof(buf), "%lld", (long long)ival);
			ring_vm_api_retstring(vm, buf);
		}
	} else {
		if (is_ffi_arg) {
			ffi_arg res = *(ffi_arg *)src;
			switch (type->kind) {
			case FFI_KIND_FLOAT:
				ring_vm_api_retnumber(vm, (double)*(float *)src);
				break;
			case FFI_KIND_DOUBLE:
				ring_vm_api_retnumber(vm, *(double *)src);
				break;
			case FFI_KIND_LONGDOUBLE:
				ring_vm_api_retnumber(vm, (double)*(long double *)src);
				break;
			case FFI_KIND_INT8:
			case FFI_KIND_SCHAR:
			case FFI_KIND_CHAR:
				ring_vm_api_retnumber(vm, (double)(int8_t)res);
				break;
			case FFI_KIND_UINT8:
			case FFI_KIND_UCHAR:
			case FFI_KIND_BOOL:
				ring_vm_api_retnumber(vm, (double)(uint8_t)res);
				break;
			case FFI_KIND_INT16:
			case FFI_KIND_SHORT:
				ring_vm_api_retnumber(vm, (double)(int16_t)res);
				break;
			case FFI_KIND_UINT16:
			case FFI_KIND_USHORT:
				ring_vm_api_retnumber(vm, (double)(uint16_t)res);
				break;
			case FFI_KIND_INT32:
			case FFI_KIND_INT:
				ring_vm_api_retnumber(vm, (double)(int32_t)res);
				break;
			case FFI_KIND_UINT32:
			case FFI_KIND_UINT:
				ring_vm_api_retnumber(vm, (double)(uint32_t)res);
				break;
			case FFI_KIND_LONG:
				ring_vm_api_retnumber(vm, (double)(long)res);
				break;
			case FFI_KIND_ULONG:
				ring_vm_api_retnumber(vm, (double)(unsigned long)res);
				break;
			default:
				ring_vm_api_retnumber(vm, (double)(int)res);
				break;
			}
		} else {
			ring_vm_api_retnumber(vm, ffi_read_typed_value(src, type));
		}
	}
}

void ffi_push_return_value(VM *vm, void *result_ptr, FFI_Type *rtype)
{
	ffi_push_to_ring(vm, result_ptr, rtype, true);
}

void ffi_push_struct_return(FFI_Context *ctx, VM *vm, void *src, FFI_Type *rtype)
{
	/* Copy the struct bytes into a GC-managed blob and hand it to Ring as an
	   FFI pointer. Field access goes through cffi_field + cffi_get/set; the
	   same blob can be passed back into a function that takes the struct by
	   value (ffi_store_arg copies it again). */
	size_t size = rtype->size > 0 ? rtype->size : 1;
	void *copy = ring_state_malloc(ctx->ring_state, size);
	if (!copy) {
		ring_vm_error(vm, "out of memory");
		return;
	}
	memcpy(copy, src, size);
	ring_list_addcustomringpointer_gc(ctx->ring_state, ctx->gc_list, copy, ffi_gc_free_ptr);
	const char *name = "FFI_Ptr";
	if (rtype->kind == FFI_KIND_STRUCT && rtype->info.struct_type && rtype->info.struct_type->name)
		name = rtype->info.struct_type->name;
	else if (rtype->kind == FFI_KIND_UNION && rtype->info.union_type &&
			 rtype->info.union_type->name)
		name = rtype->info.union_type->name;
	ring_vm_api_retcpointer(vm, copy, name);
}

void ffi_push_complex_return(FFI_Context *ctx, VM *vm, void *src, FFI_Type *rtype)
{
	/* A C99 _Complex value is returned to Ring as a [re, im] list.
	   The list must be created through the VM (ring_vm_api_newlist): a
	   bare state-GC list is not owned by the VM frame that retlist copies
	   from, and the copy comes back empty. */
	double re = 0.0, im = 0.0;
	ffi_complex_read_components(src, rtype, &re, &im);
	List *l = ring_vm_api_newlist(vm);
	ring_list_adddouble_gc(ctx->ring_state, l, re);
	ring_list_adddouble_gc(ctx->ring_state, l, im);
	ring_vm_api_retlist(vm, l);
}

void ffi_push_i128_return(FFI_Context *ctx, VM *vm, void *src, FFI_Type *rtype)
{
	/* 128-bit integers cross the boundary as exact decimal strings. */
	(void)ctx;
	char buf[64];
	ffi_format_i128(buf, sizeof(buf), src, rtype->kind == FFI_KIND_UINT128);
	ring_vm_api_retstring(vm, buf);
}

void ffi_ret_value(VM *vm, void *src, FFI_Type *type) { ffi_push_to_ring(vm, src, type, false); }

bool ffi_parse_bitfield_tag(const char *tag, FFI_TypeKind *kind, int *bit_off, int *bit_w)
{
	if (!tag || strncmp(tag, FFI_BITFIELD_TYPE_TAG "_", 3) != 0)
		return false;
	int k = 0;
	if (sscanf(tag + 3, "%d_%d_%d", &k, bit_off, bit_w) == 3 && *bit_w > 0) {
		*kind = (FFI_TypeKind)k;
		return true;
	}
	return false;
}

void ffi_read_bitfield(VM *vm, FFI_Context *ctx, void *ptr, FFI_TypeKind bf_kind, int bit_off,
					   int bit_w)
{
	FFI_Type *bf_type = ffi_type_primitive(ctx, bf_kind);
	if (!bf_type) {
		ring_vm_error(vm, "ffi_get: bitfield type unknown");
		return;
	}

	uint64_t raw = 0;
	if (bf_type->size == 1)
		raw = *(uint8_t *)ptr;
	else if (bf_type->size == 2)
		raw = *(uint16_t *)ptr;
	else if (bf_type->size == 4)
		raw = *(uint32_t *)ptr;
	else if (bf_type->size == 8)
		raw = *(uint64_t *)ptr;

	uint64_t mask = (bit_w >= 64) ? ~(uint64_t)0 : ((uint64_t)1 << bit_w) - 1;
	uint64_t val = (raw >> bit_off) & mask;

	if (ffi_is_64bit_int(bf_kind)) {
		char buf[32];
		int is_unsigned = (bf_kind == FFI_KIND_UINT64 || bf_kind == FFI_KIND_ULONGLONG ||
						   (bf_kind == FFI_KIND_SIZE_T && sizeof(size_t) == 8) ||
						   (bf_kind == FFI_KIND_UINTPTR_T && sizeof(uintptr_t) == 8) ||
						   (bf_kind == FFI_KIND_ULONG && sizeof(unsigned long) == 8));
		if (is_unsigned) {
			snprintf(buf, sizeof(buf), "%llu", (unsigned long long)val);
		} else {
			int64_t sval = (int64_t)val;
			if (bit_w < 64 && (val & ((uint64_t)1 << (bit_w - 1))))
				sval = (int64_t)(val | ~mask);
			snprintf(buf, sizeof(buf), "%lld", (long long)sval);
		}
		ring_vm_api_retstring(vm, buf);
	} else {
		ring_vm_api_retnumber(vm, (double)val);
	}
}

void ffi_write_bitfield(VM *vm, FFI_Context *ctx, void *ptr, FFI_TypeKind bf_kind, int bit_off,
						int bit_w, uint64_t new_val)
{
	FFI_Type *bf_type = ffi_type_primitive(ctx, bf_kind);
	if (!bf_type) {
		ring_vm_error(vm, "ffi_set: bitfield type unknown");
		return;
	}

	uint64_t mask = (bit_w >= 64) ? ~(uint64_t)0 : ((uint64_t)1 << bit_w) - 1;
	new_val &= mask;

	uint64_t raw = 0;
	if (bf_type->size == 1)
		raw = *(uint8_t *)ptr;
	else if (bf_type->size == 2)
		raw = *(uint16_t *)ptr;
	else if (bf_type->size == 4)
		raw = *(uint32_t *)ptr;
	else if (bf_type->size == 8)
		raw = *(uint64_t *)ptr;

	raw &= ~(mask << bit_off);
	raw |= (new_val << bit_off);

	if (bf_type->size == 1)
		*(uint8_t *)ptr = (uint8_t)raw;
	else if (bf_type->size == 2)
		*(uint16_t *)ptr = (uint16_t)raw;
	else if (bf_type->size == 4)
		*(uint32_t *)ptr = (uint32_t)raw;
	else if (bf_type->size == 8)
		*(uint64_t *)ptr = (uint64_t)raw;
}
