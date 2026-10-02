#include "json-reader.h"

#include <stdint.h>
#include <string.h>

#define LEVEL_BIT(depth) (1u << (unsigned)(depth))

void lenslink_json_reader_init(struct json_reader *r, const char *json,
			       size_t len)
{
	r->p = json;
	r->end = json ? json + len : json;
	r->depth = 0;
	r->has_item = 0;
	r->error = json == NULL;
}

static void skip_ws(struct json_reader *r)
{
	while (r->p < r->end && (*r->p == ' ' || *r->p == '\t' ||
				 *r->p == '\n' || *r->p == '\r'))
		r->p++;
}

static bool fail(struct json_reader *r)
{
	r->error = true;
	return false;
}

enum json_type lenslink_json_peek(struct json_reader *r)
{
	if (r->error)
		return JSON_TYPE_INVALID;
	skip_ws(r);
	if (r->p >= r->end)
		return JSON_TYPE_INVALID;
	switch (*r->p) {
	case '{':
		return JSON_TYPE_OBJECT;
	case '[':
		return JSON_TYPE_ARRAY;
	case '"':
		return JSON_TYPE_STRING;
	case 't':
	case 'f':
		return JSON_TYPE_BOOL;
	case 'n':
		return JSON_TYPE_NULL;
	default:
		if (*r->p == '-' || (*r->p >= '0' && *r->p <= '9'))
			return JSON_TYPE_NUMBER;
		return JSON_TYPE_INVALID;
	}
}

/* ------------------------------------------------------------------ */
/* Strings */

struct out_buf {
	char *data;
	size_t size; /* 0 = discard everything */
	size_t len;
	bool truncated;
	bool has_nul; /* an escaped \u0000 was decoded */
};

/* Appends a whole UTF-8 sequence or nothing: once one sequence doesn't
 * fit, the buffer is marked truncated and later ones are dropped too, so
 * the result is always a valid prefix. */
static void out_append(struct out_buf *o, const char *bytes, size_t n)
{
	if (!o->size || o->truncated)
		return;
	if (o->len + n + 1 > o->size) {
		o->truncated = true;
		return;
	}
	memcpy(o->data + o->len, bytes, n);
	o->len += n;
}

static void out_append_codepoint(struct out_buf *o, uint32_t cp)
{
	char b[4];
	size_t n;
	if (cp < 0x80) {
		b[0] = (char)cp;
		n = 1;
	} else if (cp < 0x800) {
		b[0] = (char)(0xC0 | (cp >> 6));
		b[1] = (char)(0x80 | (cp & 0x3F));
		n = 2;
	} else if (cp < 0x10000) {
		b[0] = (char)(0xE0 | (cp >> 12));
		b[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
		b[2] = (char)(0x80 | (cp & 0x3F));
		n = 3;
	} else {
		b[0] = (char)(0xF0 | (cp >> 18));
		b[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
		b[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
		b[3] = (char)(0x80 | (cp & 0x3F));
		n = 4;
	}
	out_append(o, b, n);
}

static int hex_value(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

/* Reads the 4 hex digits after "\u". */
static bool read_hex4(struct json_reader *r, uint32_t *out)
{
	if (r->end - r->p < 4)
		return false;
	uint32_t v = 0;
	for (int i = 0; i < 4; i++) {
		int h = hex_value(r->p[i]);
		if (h < 0)
			return false;
		v = (v << 4) | (uint32_t)h;
	}
	r->p += 4;
	*out = v;
	return true;
}

#define REPLACEMENT_CHAR 0xFFFD

/* Expects the opening quote at r->p. */
static bool parse_string(struct json_reader *r, struct out_buf *o)
{
	if (r->p >= r->end || *r->p != '"')
		return fail(r);
	r->p++;

	while (r->p < r->end) {
		unsigned char c = (unsigned char)*r->p;

		if (c == '"') {
			r->p++;
			if (o->size) {
				/* An escaped NUL can't be represented in a C
				 * string: keeping the part before it would hand
				 * the caller a *different* value ("a\u0000b"
				 * read as "a"). The whole value is withheld
				 * instead, and reported as not representable. */
				if (o->has_nul) {
					o->len = 0;
					o->truncated = true;
				}
				o->data[o->len] = 0;
			}
			return true;
		}
		if (c < 0x20)
			return fail(r); /* raw control characters are invalid */

		if (c == '\\') {
			r->p++;
			if (r->p >= r->end)
				return fail(r);
			char e = *r->p++;
			switch (e) {
			case '"':
			case '\\':
			case '/':
				out_append(o, &e, 1);
				break;
			case 'b':
				out_append(o, "\b", 1);
				break;
			case 'f':
				out_append(o, "\f", 1);
				break;
			case 'n':
				out_append(o, "\n", 1);
				break;
			case 'r':
				out_append(o, "\r", 1);
				break;
			case 't':
				out_append(o, "\t", 1);
				break;
			case 'u': {
				uint32_t cp;
				if (!read_hex4(r, &cp))
					return fail(r);
				if (cp == 0) {
					o->has_nul = true;
					break;
				}
				if (cp >= 0xD800 && cp <= 0xDBFF) {
					/* A high surrogate needs its low half
					 * right after; alone it's replaced. */
					uint32_t lo;
					if (r->end - r->p >= 6 &&
					    r->p[0] == '\\' && r->p[1] == 'u') {
						const char *save = r->p;
						r->p += 2;
						if (read_hex4(r, &lo) &&
						    lo >= 0xDC00 && lo <= 0xDFFF) {
							cp = 0x10000 +
							     ((cp - 0xD800)
							      << 10) +
							     (lo - 0xDC00);
						} else {
							r->p = save;
							cp = REPLACEMENT_CHAR;
						}
					} else {
						cp = REPLACEMENT_CHAR;
					}
				} else if (cp >= 0xDC00 && cp <= 0xDFFF) {
					cp = REPLACEMENT_CHAR;
				}
				out_append_codepoint(o, cp);
				break;
			}
			default:
				return fail(r);
			}
			continue;
		}

		/* Raw UTF-8: copy whole, well-formed sequences; anything
		 * malformed becomes U+FFFD so consumers only ever see valid
		 * UTF-8. Continuation bytes are >= 0x80, so a sequence can
		 * never swallow the closing quote. */
		size_t n = c < 0x80   ? 1
			   : c < 0xC2 ? 0
			   : c < 0xE0 ? 2
			   : c < 0xF0 ? 3
			   : c < 0xF5 ? 4
				      : 0;
		bool ok = n > 0 && (size_t)(r->end - r->p) >= n;
		for (size_t i = 1; ok && i < n; i++)
			ok = ((unsigned char)r->p[i] & 0xC0) == 0x80;
		if (ok) {
			out_append(o, r->p, n);
			r->p += n;
		} else {
			out_append_codepoint(o, REPLACEMENT_CHAR);
			r->p++;
		}
	}
	return fail(r); /* unterminated */
}

bool lenslink_json_read_string(struct json_reader *r, char *out,
			       size_t out_size, bool *truncated)
{
	if (lenslink_json_peek(r) != JSON_TYPE_STRING)
		return false;
	struct out_buf o = {out, out ? out_size : 0, 0, false, false};
	if (out && out_size)
		out[0] = 0;
	bool ok = parse_string(r, &o);
	if (truncated)
		*truncated = o.truncated;
	return ok;
}

/* ------------------------------------------------------------------ */
/* Numbers — parsed by hand rather than with strtod, whose decimal point
 * follows the process locale (which Qt sets from the user's). */

static double pow10_int(int e)
{
	double result = 1.0, base = 10.0;
	unsigned int n = (unsigned int)(e < 0 ? -e : e);
	while (n) {
		if (n & 1)
			result *= base;
		base *= base;
		n >>= 1;
	}
	return e < 0 ? 1.0 / result : result;
}

static bool is_digit(const struct json_reader *r)
{
	return r->p < r->end && *r->p >= '0' && *r->p <= '9';
}

bool lenslink_json_read_number(struct json_reader *r, double *out)
{
	if (lenslink_json_peek(r) != JSON_TYPE_NUMBER)
		return false;

	bool negative = false;
	if (*r->p == '-') {
		negative = true;
		r->p++;
	}
	if (!is_digit(r))
		return fail(r);

	double mantissa = 0.0;
	int digits = 0;   /* significant digits accumulated */
	int exponent = 0; /* decimal exponent adjustment */

	if (*r->p == '0') {
		r->p++;
	} else {
		while (is_digit(r)) {
			if (digits < 18) {
				mantissa = mantissa * 10.0 + (*r->p - '0');
				digits++;
			} else {
				exponent++;
			}
			r->p++;
		}
	}
	if (r->p < r->end && *r->p == '.') {
		r->p++;
		if (!is_digit(r))
			return fail(r);
		while (is_digit(r)) {
			if (digits < 18) {
				mantissa = mantissa * 10.0 + (*r->p - '0');
				if (mantissa != 0.0)
					digits++;
				exponent--;
			}
			r->p++;
		}
	}
	if (r->p < r->end && (*r->p == 'e' || *r->p == 'E')) {
		r->p++;
		bool exp_negative = false;
		if (r->p < r->end && (*r->p == '+' || *r->p == '-')) {
			exp_negative = *r->p == '-';
			r->p++;
		}
		if (!is_digit(r))
			return fail(r);
		int e = 0;
		while (is_digit(r)) {
			if (e < 10000)
				e = e * 10 + (*r->p - '0');
			r->p++;
		}
		exponent += exp_negative ? -e : e;
	}

	/* Beyond these the result is 0 or infinite anyway; clamping keeps
	 * pow10_int's loop bounded. */
	if (exponent > 400)
		exponent = 400;
	if (exponent < -400)
		exponent = -400;

	/* Zero stays zero whatever the exponent: "0e999" would otherwise be
	 * 0 * inf = NaN, which no caller's range clamp catches. */
	double v = mantissa == 0.0 ? 0.0
		   : exponent < -300
			   ? mantissa * pow10_int(-300) *
				     pow10_int(exponent + 300)
			   : mantissa * pow10_int(exponent);
	*out = negative ? -v : v;
	return true;
}

/* ------------------------------------------------------------------ */

static bool match_literal(struct json_reader *r, const char *lit)
{
	size_t n = strlen(lit);
	if ((size_t)(r->end - r->p) < n || memcmp(r->p, lit, n) != 0)
		return fail(r);
	r->p += n;
	return true;
}

bool lenslink_json_read_bool(struct json_reader *r, bool *out)
{
	if (lenslink_json_peek(r) != JSON_TYPE_BOOL)
		return false;
	if (*r->p == 't') {
		if (!match_literal(r, "true"))
			return false;
		*out = true;
	} else {
		if (!match_literal(r, "false"))
			return false;
		*out = false;
	}
	return true;
}

static bool enter(struct json_reader *r, char open)
{
	if (r->error)
		return false;
	skip_ws(r);
	if (r->p >= r->end || *r->p != open)
		return false;
	if (r->depth + 1 >= JSON_READER_MAX_DEPTH)
		return fail(r);
	r->p++;
	r->depth++;
	r->has_item &= ~LEVEL_BIT(r->depth);
	return true;
}

/* Shared by objects and arrays: consumes the closing bracket (returning
 * false) or the separating comma before the next item (returning true). */
static bool next_item(struct json_reader *r, char close)
{
	if (r->error || r->depth <= 0)
		return false;
	skip_ws(r);
	if (r->p >= r->end)
		return fail(r);
	if (*r->p == close) {
		r->p++;
		r->has_item &= ~LEVEL_BIT(r->depth);
		r->depth--;
		return false;
	}
	if (r->has_item & LEVEL_BIT(r->depth)) {
		if (*r->p != ',')
			return fail(r);
		r->p++;
		skip_ws(r);
		/* "[1,]" / "{"a":1,}": a comma must introduce an item. */
		if (r->p >= r->end || *r->p == close)
			return fail(r);
	}
	r->has_item |= LEVEL_BIT(r->depth);
	return true;
}

bool lenslink_json_object_begin(struct json_reader *r)
{
	return enter(r, '{');
}

bool lenslink_json_object_next(struct json_reader *r, char *key,
			       size_t key_size, bool *key_truncated)
{
	if (!next_item(r, '}'))
		return false;
	struct out_buf o = {key, key ? key_size : 0, 0, false, false};
	if (key && key_size)
		key[0] = 0;
	if (!parse_string(r, &o))
		return false;
	if (key_truncated)
		*key_truncated = o.truncated;
	skip_ws(r);
	if (r->p >= r->end || *r->p != ':')
		return fail(r);
	r->p++;
	/* A key must be followed by a value. */
	if (lenslink_json_peek(r) == JSON_TYPE_INVALID)
		return fail(r);
	return true;
}

bool lenslink_json_array_begin(struct json_reader *r)
{
	return enter(r, '[');
}

bool lenslink_json_array_next(struct json_reader *r)
{
	if (!next_item(r, ']'))
		return false;
	if (lenslink_json_peek(r) == JSON_TYPE_INVALID)
		return fail(r);
	return true;
}

bool lenslink_json_skip(struct json_reader *r)
{
	switch (lenslink_json_peek(r)) {
	case JSON_TYPE_OBJECT:
		if (!lenslink_json_object_begin(r))
			return false;
		while (lenslink_json_object_next(r, NULL, 0, NULL))
			if (!lenslink_json_skip(r))
				return false;
		return !r->error;
	case JSON_TYPE_ARRAY:
		if (!lenslink_json_array_begin(r))
			return false;
		while (lenslink_json_array_next(r))
			if (!lenslink_json_skip(r))
				return false;
		return !r->error;
	case JSON_TYPE_STRING:
		return lenslink_json_read_string(r, NULL, 0, NULL);
	case JSON_TYPE_NUMBER: {
		double ignored;
		return lenslink_json_read_number(r, &ignored);
	}
	case JSON_TYPE_BOOL: {
		bool ignored;
		return lenslink_json_read_bool(r, &ignored);
	}
	case JSON_TYPE_NULL:
		return match_literal(r, "null");
	case JSON_TYPE_INVALID:
	default:
		return fail(r);
	}
}

bool lenslink_json_reader_done(struct json_reader *r)
{
	if (r->error)
		return false;
	skip_ws(r);
	return r->p == r->end && r->depth == 0;
}
