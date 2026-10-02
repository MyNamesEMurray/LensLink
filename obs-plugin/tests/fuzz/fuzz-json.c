/*
 * The phone's handshake packets, HELLO and VIDEO_CONFIG, through their
 * real parsers, plus a raw reader walk. Invariants: every string that
 * comes out is terminated, valid UTF-8, and NUL-free; an invalid packet
 * leaves nothing behind.
 */

#include "fuzz.h"

#include "handshake.h"
#include "json-reader.h"

#include <string.h>

static const struct fuzz_seed seeds[] = {
	FUZZ_SEED("{\"name\":\"Gibson\\u2019s iPhone\",\"app\":\"LensLink\","
		  "\"protocol\":1,\"kind\":\"camera\",\"standby\":true,"
		  "\"armed\":false}"),
	FUZZ_SEED("{\"name\":\"Emma's iPhone\",\"app\":\"LensLink\","
		  "\"protocol\":1,\"kind\":\"screen\"}"),
	FUZZ_SEED("{\"codec\":\"hevc\",\"width\":1920,\"height\":1080,"
		  "\"fps\":30,\"kind\":\"camera\",\"color\":\"hlg\"}"),
	FUZZ_SEED("{\"paused\":false,\"zoom\":2.5,\"lenses\":[\"Ultra Wide "
		  "(0.5\xC3\x97)\",\"Main\"],\"frameRates\":[24,30,60],"
		  "\"mics\":[{\"id\":\"auto\",\"name\":\"A\\u00d7\\ud83d"
		  "\\ude00\"}],\"iso\":1e3,\"future\":{\"a\":[1,{\"b\":null}]}}"),
	FUZZ_SEED("[[[[{\"a\":\"\\\"\\u0000\"}]]]]"),
	FUZZ_SEED("{\"minISO\":34,\"maxISO\":3072,\"color\":\"log\"}"),
};

const struct fuzz_seed *fuzz_seeds(size_t *count)
{
	*count = sizeof(seeds) / sizeof(seeds[0]);
	return seeds;
}

static void check_hello(const uint8_t *data, size_t size)
{
	struct lenslink_hello h;
	bool ok = lenslink_hello_parse((const char *)data, size, &h);
	FUZZ_ASSERT(ok == h.valid);
	FUZZ_ASSERT(fuzz_utf8_field_ok(h.name, sizeof(h.name)));
	FUZZ_ASSERT(h.has_name || !h.name[0]);
	if (!ok)
		FUZZ_ASSERT(!h.has_name && !h.name[0] && !h.is_screen &&
			    !h.standby && !h.unarmed);
}

static void check_video_config(const uint8_t *data, size_t size)
{
	struct lenslink_video_config c;
	bool ok = lenslink_video_config_parse((const char *)data, size, &c);
	FUZZ_ASSERT(ok == c.valid);
	FUZZ_ASSERT(c.codec == LENSLINK_CODEC_H264 ||
		    c.codec == LENSLINK_CODEC_HEVC);
	FUZZ_ASSERT(c.has_kind || !c.is_screen);
	if (!ok)
		FUZZ_ASSERT(!c.has_kind && c.codec == LENSLINK_CODEC_H264);
}

/* A raw walk that reads every string into a small buffer. */
static void walk(struct json_reader *r, int budget)
{
	char buf[8];
	bool trunc;
	if (budget <= 0) {
		lenslink_json_skip(r);
		return;
	}
	switch (lenslink_json_peek(r)) {
	case JSON_TYPE_OBJECT:
		if (!lenslink_json_object_begin(r))
			return;
		while (lenslink_json_object_next(r, buf, sizeof(buf), &trunc)) {
			FUZZ_ASSERT(fuzz_utf8_field_ok(buf, sizeof(buf)));
			walk(r, budget - 1);
		}
		break;
	case JSON_TYPE_ARRAY:
		if (!lenslink_json_array_begin(r))
			return;
		while (lenslink_json_array_next(r))
			walk(r, budget - 1);
		break;
	case JSON_TYPE_STRING:
		if (lenslink_json_read_string(r, buf, sizeof(buf), &trunc))
			FUZZ_ASSERT(fuzz_utf8_field_ok(buf, sizeof(buf)));
		break;
	default:
		lenslink_json_skip(r);
		break;
	}
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	check_hello(data, size);
	check_video_config(data, size);

	struct json_reader r;
	lenslink_json_reader_init(&r, (const char *)data, size);
	walk(&r, 64);
	(void)lenslink_json_reader_done(&r);
	return 0;
}
