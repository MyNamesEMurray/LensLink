/*
 * Typed parsers for the phone's small JSON handshake packets: HELLO
 * (type 1) and VIDEO_CONFIG (type 2), on the bounded json-reader.c.
 * docs/PROTOCOL.md defines the fields; only the ones the plugin acts on
 * are read.
 *
 * Failure is per field where it can be, whole where it must be:
 *
 *   - A known field with the wrong type or an unusable value (a string
 *     holding an escaped NUL, say) is treated as absent; the other fields
 *     are unaffected.
 *   - A syntax error, a payload over the size cap, a non-object, or a
 *     known key given twice (parsers disagree on which copy wins, so the
 *     sender's intent is ambiguous) invalidates the whole packet: every
 *     field reads as absent and `valid` is false. Nothing half-parsed
 *     leaks out.
 *
 * Only top-level keys count, and unknown keys are skipped (nested values
 * included), so new fields stay backwards-compatible. Pure C with no
 * libobs dependency, so it is unit-tested standalone.
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Larger payloads are malformed. Real HELLOs are ~150 bytes. */
#define LENSLINK_HANDSHAKE_MAX 4096

#define LENSLINK_HELLO_NAME_SIZE 128

struct lenslink_hello {
	bool valid; /* one well-formed JSON object within the size cap */

	/* Phone display name, for status lines only. `has_name` is false
	 * when the key is absent or not a usable string; the caller then
	 * keeps whatever name it had. Truncated on a UTF-8 boundary if
	 * long. */
	bool has_name;
	char name[LENSLINK_HELLO_NAME_SIZE];

	/* `kind`: "screen" is a screen mirror; "camera", absent, or any
	 * other value is a camera (the historical reading). */
	bool is_screen;

	/* "standby": true, the app is idle and waiting for start_stream.
	 * Only the literal true counts. */
	bool standby;

	/* "armed": false, remote start is not armed on the phone (it will
	 * refuse start_stream). Only the literal false counts: absent means
	 * armed, as apps from before arming behaved. */
	bool unarmed;
};

/* Parses `len` bytes (no NUL terminator needed). Always fills `out`;
 * returns out->valid. */
bool lenslink_hello_parse(const char *json, size_t len,
			  struct lenslink_hello *out);

enum lenslink_codec {
	LENSLINK_CODEC_H264, /* "h264", absent, or unknown (historical) */
	LENSLINK_CODEC_HEVC, /* "hevc" */
};

struct lenslink_video_config {
	bool valid;
	enum lenslink_codec codec;
	/* `kind` present as a non-empty string: then `is_screen` says
	 * which ("screen", or a camera for any other value). Absent, empty
	 * or not a string leaves the connection's kind (from HELLO)
	 * unchanged. */
	bool has_kind;
	bool is_screen;
};

bool lenslink_video_config_parse(const char *json, size_t len,
				 struct lenslink_video_config *out);

#ifdef __cplusplus
}
#endif
