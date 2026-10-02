/*
 * A small, strict, allocation-free JSON pull reader for the JSON payloads
 * the plugin receives from the phone (HELLO and VIDEO_CONFIG today, via
 * handshake.c).
 *
 * Why not obs_data_create_from_json: it needs a NUL-terminated copy of
 * untrusted input, allocates, and keeps only arrays of *objects*,
 * silently dropping arrays of strings and numbers (STATE's capability
 * lists). Linking jansson directly isn't an option either: OBS links it
 * privately and doesn't ship it to plugins on every platform.
 *
 * The reader walks a bounded buffer (no NUL terminator needed), never
 * reads past `len`, limits nesting depth, and decodes strings into
 * caller-owned buffers, truncating only on a UTF-8 code point boundary.
 * Decoded strings are always valid UTF-8 (malformed bytes and lone
 * surrogates become U+FFFD) and never contain a NUL: a string holding an
 * escaped \u0000 is withheld whole — "" with the truncated flag set —
 * because any C string made from it would mean something else.
 * Any syntax error latches `error`; every later call then fails, so a
 * caller can check once at the end. Pure C with no libobs dependency, so
 * it can be unit-tested standalone.
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define JSON_READER_MAX_DEPTH 16

enum json_type {
	JSON_TYPE_INVALID, /* end of input or a syntax error */
	JSON_TYPE_OBJECT,
	JSON_TYPE_ARRAY,
	JSON_TYPE_STRING,
	JSON_TYPE_NUMBER,
	JSON_TYPE_BOOL,
	JSON_TYPE_NULL,
};

struct json_reader {
	const char *p;
	const char *end;
	int depth;
	/* Bit d set: an item was already read at nesting depth d, so the
	 * next one there must be preceded by a comma. */
	unsigned int has_item;
	bool error;
};

void lenslink_json_reader_init(struct json_reader *r, const char *json,
			       size_t len);

/* The type of the next value, without consuming it. */
enum json_type lenslink_json_peek(struct json_reader *r);

/* Objects: lenslink_json_object_begin consumes '{'; then call
 * lenslink_json_object_next until it returns false (the closing '}'
 * consumed, or an error). Each true return has read one key and its ':' —
 * the caller must then consume exactly one value (read it or
 * lenslink_json_skip it). `key_truncated` reports a key that did not fit
 * (or held an escaped NUL), which callers should treat as unknown. */
bool lenslink_json_object_begin(struct json_reader *r);
bool lenslink_json_object_next(struct json_reader *r, char *key,
			       size_t key_size, bool *key_truncated);

/* Arrays: same pattern — lenslink_json_array_next returns true while
 * another element follows (the caller consumes it), false at the closing
 * ']'. */
bool lenslink_json_array_begin(struct json_reader *r);
bool lenslink_json_array_next(struct json_reader *r);

/* Scalar reads fail (without latching an error) when the next value has
 * a different type, so a caller can fall back to lenslink_json_skip.
 * lenslink_json_read_string's `truncated` means "`out` is not the whole
 * value": it did not fit (`out` holds a prefix), or it contained an escaped NUL
 * (`out` is ""). A caller that routes, matches or trusts the value must
 * treat either as invalid. Numbers beyond double range read as ±inf and
 * tiny ones as 0; callers clamp. */
bool lenslink_json_read_string(struct json_reader *r, char *out,
			       size_t out_size, bool *truncated);
bool lenslink_json_read_number(struct json_reader *r, double *out);
bool lenslink_json_read_bool(struct json_reader *r, bool *out);

/* Consumes one value of any type, nested ones included. */
bool lenslink_json_skip(struct json_reader *r);

/* True when the whole input was consumed (trailing whitespace allowed)
 * and no error occurred. */
bool lenslink_json_reader_done(struct json_reader *r);

#ifdef __cplusplus
}
#endif
