/* HELLO / VIDEO_CONFIG parsing (handshake.c), including parity with the
 * substring extraction it replaced. */

#include "handshake.h"
#include "test.h"

#include <stdlib.h>

static bool hello(const char *json, struct lenslink_hello *h)
{
	return lenslink_hello_parse(json, strlen(json), h);
}

static bool all_absent(const struct lenslink_hello *h)
{
	return !h->valid && !h->has_name && !h->name[0] && !h->is_screen &&
	       !h->standby && !h->unarmed;
}

/* Captured from tools/fake-phone.py (default, --standby, --unarmed,
 * --screen), and the start_stream re-send without standby. */
static void test_hello_fake_phone(void)
{
	struct lenslink_hello h;

	CHECK(hello("{\"name\":\"Fake iPhone\",\"app\":\"LensLink\","
		    "\"protocol\":1,\"kind\":\"camera\"}",
		    &h));
	CHECK(h.has_name);
	CHECK_STR(h.name, "Fake iPhone");
	CHECK(!h.is_screen && !h.standby && !h.unarmed);

	CHECK(hello("{\"name\":\"Fake iPhone\",\"app\":\"LensLink\","
		    "\"protocol\":1,\"kind\":\"camera\",\"standby\":true,"
		    "\"armed\":true}",
		    &h));
	CHECK(!h.is_screen && h.standby && !h.unarmed);

	CHECK(hello("{\"name\":\"Fake iPhone\",\"app\":\"LensLink\","
		    "\"protocol\":1,\"kind\":\"camera\",\"standby\":true,"
		    "\"armed\":false}",
		    &h));
	CHECK(!h.is_screen && h.standby && h.unarmed);

	CHECK(hello("{\"name\":\"Fake iPhone\",\"app\":\"LensLink\","
		    "\"protocol\":1,\"kind\":\"screen\"}",
		    &h));
	CHECK(h.is_screen && !h.standby && !h.unarmed);
}

static void test_hello_basic(void)
{
	struct lenslink_hello h;

	/* The app's JSONSerialization escapes '/' and passes UTF-8 raw. */
	CHECK(hello("{\"kind\":\"camera\",\"name\":\"Emma\\/Gibson\xE2\x80\x99s "
		    "iPhone\",\"app\":\"LensLink\",\"protocol\":1}",
		    &h));
	CHECK_STR(h.name, "Emma/Gibson\xE2\x80\x99s iPhone");
	CHECK(hello("{\"name\":\"Gibson\\u2019s iPhone\"}", &h));
	CHECK_STR(h.name, "Gibson\xE2\x80\x99s iPhone");

	/* Whitespace anywhere JSON allows it. */
	CHECK(hello(" { \"standby\" : true ,\n\"armed\"\t:false } ", &h));
	CHECK(h.standby && h.unarmed && !h.has_name);

	/* Kind: absent, unknown, empty or mistyped all read as camera. */
	CHECK(hello("{\"kind\":\"screen\"}", &h) && h.is_screen);
	CHECK(hello("{}", &h) && !h.is_screen && !h.has_name);
	CHECK(hello("{\"kind\":\"toaster\"}", &h) && !h.is_screen);
	CHECK(hello("{\"kind\":\"\"}", &h) && !h.is_screen);
	CHECK(hello("{\"kind\":5}", &h) && !h.is_screen);
	CHECK(hello("{\"kind\":\"Screen\"}", &h) && !h.is_screen);
	CHECK(hello("{\"kind\":\"screenscreenscreen\"}", &h) && !h.is_screen);

	/* standby: only the literal true. */
	CHECK(hello("{\"standby\":false}", &h) && !h.standby);
	CHECK(hello("{\"standby\":\"true\"}", &h) && !h.standby);
	CHECK(hello("{\"standby\":1}", &h) && !h.standby);
	CHECK(hello("{\"standby\":null}", &h) && !h.standby);

	/* armed: only the literal false; absent means armed. */
	CHECK(hello("{\"standby\":true}", &h) && h.standby && !h.unarmed);
	CHECK(hello("{\"armed\":true}", &h) && !h.unarmed);
	CHECK(hello("{\"armed\":\"false\"}", &h) && !h.unarmed);
	CHECK(hello("{\"armed\":0}", &h) && !h.unarmed);
	CHECK(hello("{\"armed\":null}", &h) && !h.unarmed);
	/* The parser reports it whatever standby says; the caller only
	 * honours it in standby (and never for a screen mirror). */
	CHECK(hello("{\"armed\":false}", &h) && h.unarmed && !h.standby);
	CHECK(hello("{\"kind\":\"screen\",\"standby\":true,\"armed\":false}",
		    &h));
	CHECK(h.is_screen && h.standby && h.unarmed);

	/* Name: present-but-empty is a name (""); mistyped is absent. */
	CHECK(hello("{\"name\":\"\"}", &h) && h.has_name && !h.name[0]);
	CHECK(hello("{\"name\":null}", &h) && !h.has_name);
	CHECK(hello("{\"name\":7,\"kind\":\"screen\"}", &h));
	CHECK(!h.has_name && h.is_screen);

	/* Unknown keys, including nested values and nested copies of known
	 * keys, are skipped: only the top level counts. */
	CHECK(hello("{\"future\":{\"standby\":true,\"kind\":\"screen\","
		    "\"a\":[1,{\"b\":null}]},\"name\":\"X\",\"more\":[\"s\"],"
		    "\"deviceID\":\"B1092868-1234-5678-ABCD-0123456789AB\"}",
		    &h));
	CHECK_STR(h.name, "X");
	CHECK(!h.standby && !h.is_screen);
	/* Duplicate *unknown* keys are harmless. */
	CHECK(hello("{\"x\":1,\"x\":2,\"standby\":true}", &h) && h.standby);
}

static void test_hello_field_isolation(void)
{
	struct lenslink_hello h;

	/* Wrong types don't disturb the other fields. */
	CHECK(hello("{\"name\":[],\"kind\":\"screen\",\"standby\":\"yes\","
		    "\"armed\":{}}",
		    &h));
	CHECK(!h.has_name && h.is_screen && !h.standby && !h.unarmed);

	/* A kind holding an escaped NUL can't smuggle "screen". */
	CHECK(hello("{\"kind\":\"screen\\u0000camera\"}", &h));
	CHECK(!h.is_screen);
	CHECK(hello("{\"kind\\u0000\":\"screen\"}", &h) && !h.is_screen);
	/* A name holding one is withheld, not cut short. */
	CHECK(hello("{\"name\":\"Stage\\u0000Left\",\"standby\":true}", &h));
	CHECK(!h.has_name && !h.name[0] && h.standby);

	/* A long name keeps a UTF-8-safe prefix (display only). */
	char doc[512];
	size_t n = (size_t)snprintf(doc, sizeof(doc), "{\"name\":\"");
	for (int i = 0; i < 100; i++)
		n += (size_t)snprintf(doc + n, sizeof(doc) - n, "\xC3\x97");
	snprintf(doc + n, sizeof(doc) - n, "\"}");
	CHECK(hello(doc, &h));
	CHECK(h.has_name);
	CHECK(strlen(h.name) == 126); /* 63 whole x signs, not 63.5 */

	/* A HELLO past the old 512-byte copy still reads its last field. */
	n = (size_t)snprintf(doc, sizeof(doc), "{\"pad\":\"");
	while (n < 480)
		doc[n++] = 'x';
	snprintf(doc + n, sizeof(doc) - n, "\",\"standby\":true}");
	CHECK(hello(doc, &h) && h.standby);
}

static void test_hello_invalid(void)
{
	struct lenslink_hello h;
	static const char *const bad[] = {
		"",
		"[]",
		"null",
		"\"hello\"",
		"{",
		"{\"name\":\"a\"",
		"{\"name\":\"a\",}",
		"{\"name\" \"a\"}",
		"{\"name\":\"a\"}{}",
		"{\"name\":\"a\"} x",
		"{name:\"a\"}",
		"{\"name\":\"unterminated}",
		"{\"name\":\"bad \\x escape\"}",
		"{\"name\":\"raw\ncontrol\"}",
		"{\"standby\":tru}",
		"{\"standby\":true,\"armed\":fals}",
		/* Duplicate known keys: ambiguous, whole packet rejected. */
		"{\"kind\":\"camera\",\"kind\":\"screen\"}",
		"{\"standby\":false,\"standby\":true}",
		"{\"standby\":true,\"armed\":true,\"armed\":false}",
		"{\"name\":\"a\",\"name\":\"b\"}",
	};
	for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++) {
		memset(&h, 0xAB, sizeof(h));
		CHECK(!hello(bad[i], &h));
		CHECK(all_absent(&h));
	}

	/* Over the size cap. */
	char *big = malloc(LENSLINK_HANDSHAKE_MAX + 64);
	size_t n = (size_t)snprintf(big, 64, "{\"pad\":\"");
	while (n < LENSLINK_HANDSHAKE_MAX + 8)
		big[n++] = 'x';
	memcpy(big + n, "\"}", 3);
	CHECK(!lenslink_hello_parse(big, strlen(big), &h) && all_absent(&h));
	free(big);

	CHECK(!lenslink_hello_parse(NULL, 0, &h) && all_absent(&h));

	/* Every truncation of a real HELLO fails whole. */
	const char full[] = "{\"name\":\"Gibson\\u2019s iPhone\",\"app\":"
			    "\"LensLink\",\"protocol\":1,\"kind\":\"camera\","
			    "\"standby\":true,\"armed\":false}";
	for (size_t len = 0; len + 1 < sizeof(full); len++) {
		char *copy = malloc(len ? len : 1);
		memcpy(copy, full, len);
		memset(&h, 0xAB, sizeof(h));
		CHECK(!lenslink_hello_parse(copy, len, &h));
		CHECK(all_absent(&h));
		free(copy);
	}
	CHECK(lenslink_hello_parse(full, sizeof(full) - 1, &h));
	CHECK(h.standby && h.unarmed);

	/* The payload is a packet buffer: bytes past `len` are never read,
	 * and a NUL inside `len` is invalid, not a terminator. */
	const char trailing[] = "{\"kind\":\"screen\"}GARBAGE";
	CHECK(lenslink_hello_parse(trailing, 17, &h) && h.is_screen);
	const char nul[] = "{\"kind\":\"screen\"}\0";
	CHECK(!lenslink_hello_parse(nul, sizeof(nul) - 1, &h));
}

static bool vc(const char *json, struct lenslink_video_config *c)
{
	return lenslink_video_config_parse(json, strlen(json), c);
}

static void test_video_config(void)
{
	struct lenslink_video_config c;

	/* Captured from tools/fake-phone.py. */
	CHECK(vc("{\"codec\":\"h264\",\"width\":320,\"height\":240,\"fps\":30,"
		 "\"kind\":\"camera\"}",
		 &c));
	CHECK(c.codec == LENSLINK_CODEC_H264 && c.has_kind && !c.is_screen);
	CHECK(vc("{\"codec\":\"h264\",\"width\":320,\"height\":240,\"fps\":30,"
		 "\"kind\":\"screen\"}",
		 &c));
	CHECK(c.codec == LENSLINK_CODEC_H264 && c.has_kind && c.is_screen);

	CHECK(vc("{\"codec\":\"hevc\",\"width\":1920,\"height\":1080,"
		 "\"fps\":30,\"kind\":\"camera\",\"color\":\"hlg\"}",
		 &c));
	CHECK(c.codec == LENSLINK_CODEC_HEVC && c.has_kind && !c.is_screen);
	/* Absent/empty/mistyped kind leaves the connection's kind alone. */
	CHECK(vc("{\"codec\":\"hevc\"}", &c) && !c.has_kind);
	CHECK(vc("{\"kind\":\"\"}", &c) && !c.has_kind);
	CHECK(vc("{\"kind\":5}", &c) && !c.has_kind);
	CHECK(vc("{\"kind\":null}", &c) && !c.has_kind);
	/* Any other word is a camera, as it always was. */
	CHECK(vc("{\"kind\":\"toaster\"}", &c) && c.has_kind && !c.is_screen);
	CHECK(vc("{\"kind\":\"screen\\u0000x\"}", &c));
	CHECK(c.has_kind && !c.is_screen);
	/* Absent or unknown codec: H.264, as always. */
	CHECK(vc("{}", &c) && c.codec == LENSLINK_CODEC_H264);
	CHECK(vc("{\"codec\":\"av1\"}", &c) && c.codec == LENSLINK_CODEC_H264);
	CHECK(vc("{\"codec\":\"HEVC\"}", &c) && c.codec == LENSLINK_CODEC_H264);
	CHECK(vc("{\"codec\":5}", &c) && c.codec == LENSLINK_CODEC_H264);
	CHECK(vc("{\"codec\":\"hevc\\u0000\"}", &c) &&
	      c.codec == LENSLINK_CODEC_H264);
	/* Nested copies don't count. */
	CHECK(vc("{\"x\":{\"codec\":\"hevc\",\"kind\":\"screen\"}}", &c));
	CHECK(c.codec == LENSLINK_CODEC_H264 && !c.has_kind);
	/* Malformed / duplicated: defaults, invalid. */
	CHECK(!vc("{\"codec\":\"hevc\"", &c) && !c.valid &&
	      c.codec == LENSLINK_CODEC_H264 && !c.has_kind);
	CHECK(!vc("{\"codec\":\"h264\",\"codec\":\"hevc\"}", &c));
	CHECK(!vc("{\"kind\":\"camera\",\"kind\":\"screen\"}", &c) &&
	      !c.has_kind);
	CHECK(!lenslink_video_config_parse(NULL, 0, &c) && !c.valid);
}

/* ------------------------------------------------------------------ */
/* Parity: the substring extraction ios-camera-source.c used before,
 * verbatim, against the parser, over every combination of the fields
 * the plugin reads, in both key orders and both spacing styles a real
 * sender produces (the app's compact JSONSerialization, Python's
 * json.dumps). For well-formed input the two must agree exactly. */

static void legacy_string(const char *json, const char *key, char *out,
			  size_t out_size)
{
	char pattern[64];
	snprintf(pattern, sizeof(pattern), "\"%s\"", key);

	const char *p = strstr(json, pattern);
	if (!p)
		return;
	p = strchr(p + strlen(pattern), ':');
	if (!p)
		return;
	p++;
	while (*p == ' ' || *p == '\t')
		p++;
	if (*p != '"')
		return;
	p++;

	size_t i = 0;
	while (*p && *p != '"' && i + 1 < out_size)
		out[i++] = *p++;
	out[i] = 0;
}

static bool legacy_literal(const char *json, const char *key,
			   const char *lit)
{
	char pattern[64];
	snprintf(pattern, sizeof(pattern), "\"%s\":", key);

	const char *p = strstr(json, pattern);
	if (!p)
		return false;
	p += strlen(pattern);
	while (*p == ' ' || *p == '\t')
		p++;
	return strncmp(p, lit, strlen(lit)) == 0;
}

struct conn {
	char name[128];
	bool is_screen, standby, unarmed;
	bool hevc;
};

static void legacy_hello(const char *payload, struct conn *c)
{
	char json[512] = {0};
	size_t n = strlen(payload) < sizeof(json) - 1 ? strlen(payload)
						      : sizeof(json) - 1;
	memcpy(json, payload, n);
	legacy_string(json, "name", c->name, sizeof(c->name));
	char kind[16] = {0};
	legacy_string(json, "kind", kind, sizeof(kind));
	c->is_screen = strcmp(kind, "screen") == 0;
	c->standby = !c->is_screen && legacy_literal(json, "standby", "true");
	c->unarmed = c->standby && legacy_literal(json, "armed", "false");
}

/* The new handle_packet HELLO logic, minus the I/O. */
static void new_hello(const char *payload, struct conn *c)
{
	struct lenslink_hello h;
	lenslink_hello_parse(payload, strlen(payload), &h);
	if (h.has_name)
		snprintf(c->name, sizeof(c->name), "%s", h.name);
	c->is_screen = h.is_screen;
	c->standby = !c->is_screen && h.standby;
	c->unarmed = c->standby && h.unarmed;
}

static void legacy_video_config(const char *payload, struct conn *c)
{
	char json[512] = {0};
	size_t n = strlen(payload) < sizeof(json) - 1 ? strlen(payload)
						      : sizeof(json) - 1;
	memcpy(json, payload, n);
	char codec[32] = {0};
	legacy_string(json, "codec", codec, sizeof(codec));
	char kind[16] = {0};
	legacy_string(json, "kind", kind, sizeof(kind));
	if (kind[0])
		c->is_screen = strcmp(kind, "screen") == 0;
	c->hevc = strcmp(codec, "hevc") == 0;
}

static void new_video_config(const char *payload, struct conn *c)
{
	struct lenslink_video_config cfg;
	lenslink_video_config_parse(payload, strlen(payload), &cfg);
	if (cfg.has_kind)
		c->is_screen = cfg.is_screen;
	if (cfg.valid)
		c->hevc = cfg.codec == LENSLINK_CODEC_HEVC;
}

static bool same(const struct conn *a, const struct conn *b)
{
	return strcmp(a->name, b->name) == 0 && a->is_screen == b->is_screen &&
	       a->standby == b->standby && a->unarmed == b->unarmed &&
	       a->hevc == b->hevc;
}

/* Joins the non-NULL "key": value members, forwards or reversed. */
static void build(char *out, size_t size, const char *const *members,
		  size_t count, bool reverse, bool spaced)
{
	size_t n = (size_t)snprintf(out, size, "{");
	bool first = true;
	for (size_t i = 0; i < count; i++) {
		const char *m = members[reverse ? count - 1 - i : i];
		if (!m)
			continue;
		n += (size_t)snprintf(out + n, size - n, "%s%s",
				      first ? "" : (spaced ? ", " : ","), m);
		first = false;
	}
	snprintf(out + n, size - n, "}");
}

static int parity_cases;

static void check_hello_parity(const char *doc)
{
	struct conn a, b;
	memset(&a, 0, sizeof(a));
	memset(&b, 0, sizeof(b));
	/* A re-sent HELLO keeps the earlier name when it has none. */
	strcpy(a.name, "Earlier");
	strcpy(b.name, "Earlier");
	legacy_hello(doc, &a);
	new_hello(doc, &b);
	parity_cases++;
	if (!same(&a, &b)) {
		fprintf(stderr, "HELLO parity: %s\n", doc);
		CHECK(same(&a, &b));
	}
}

static void test_hello_parity(void)
{
	static const char *const names[][2] = {
		{NULL, NULL},
		{"\"name\":\"Emma's iPhone\"", "\"name\": \"Emma's iPhone\""},
		{"\"name\":\"\"", "\"name\": \"\""},
		{"\"name\":\"Gibson\xE2\x80\x99s iPad\"",
		 "\"name\": \"Gibson\xE2\x80\x99s iPad\""},
		{"\"name\":42", "\"name\": 42"},
	};
	static const char *const kinds[][2] = {
		{NULL, NULL},
		{"\"kind\":\"camera\"", "\"kind\": \"camera\""},
		{"\"kind\":\"screen\"", "\"kind\": \"screen\""},
		{"\"kind\":\"toaster\"", "\"kind\": \"toaster\""},
		{"\"kind\":\"\"", "\"kind\": \"\""},
		{"\"kind\":7", "\"kind\": 7"},
	};
	static const char *const standbys[][2] = {
		{NULL, NULL},
		{"\"standby\":true", "\"standby\": true"},
		{"\"standby\":false", "\"standby\": false"},
		{"\"standby\":\"true\"", "\"standby\": \"true\""},
		{"\"standby\":1", "\"standby\": 1"},
	};
	static const char *const armeds[][2] = {
		{NULL, NULL},
		{"\"armed\":true", "\"armed\": true"},
		{"\"armed\":false", "\"armed\": false"},
		{"\"armed\":null", "\"armed\": null"},
		{"\"armed\":\"false\"", "\"armed\": \"false\""},
	};
#define COUNT(a) (sizeof(a) / sizeof(a[0]))
	for (int sp = 0; sp < 2; sp++)
		for (size_t i = 0; i < COUNT(names); i++)
			for (size_t k = 0; k < COUNT(kinds); k++)
				for (size_t s = 0; s < COUNT(standbys); s++)
					for (size_t a = 0; a < COUNT(armeds);
					     a++) {
						const char *m[] = {
							names[i][sp],
							sp ? "\"app\": \"LensLink\""
							   : "\"app\":\"LensLink\"",
							sp ? "\"protocol\": 1"
							   : "\"protocol\":1",
							kinds[k][sp],
							standbys[s][sp],
							armeds[a][sp],
						};
						char doc[256];
						for (int rev = 0; rev < 2;
						     rev++) {
							build(doc, sizeof(doc),
							      m, COUNT(m),
							      rev, sp);
							check_hello_parity(doc);
						}
					}
}

static void check_vc_parity(const char *doc)
{
	for (int start = 0; start < 2; start++) {
		struct conn a, b;
		memset(&a, 0, sizeof(a));
		a.is_screen = start;
		a.hevc = !start;
		b = a;
		legacy_video_config(doc, &a);
		new_video_config(doc, &b);
		parity_cases++;
		if (!same(&a, &b)) {
			fprintf(stderr, "VIDEO_CONFIG parity: %s\n", doc);
			CHECK(same(&a, &b));
		}
	}
}

static void test_video_config_parity(void)
{
	static const char *const codecs[][2] = {
		{NULL, NULL},
		{"\"codec\":\"h264\"", "\"codec\": \"h264\""},
		{"\"codec\":\"hevc\"", "\"codec\": \"hevc\""},
		{"\"codec\":\"av1\"", "\"codec\": \"av1\""},
		{"\"codec\":5", "\"codec\": 5"},
	};
	static const char *const kinds[][2] = {
		{NULL, NULL},
		{"\"kind\":\"camera\"", "\"kind\": \"camera\""},
		{"\"kind\":\"screen\"", "\"kind\": \"screen\""},
		{"\"kind\":\"toaster\"", "\"kind\": \"toaster\""},
		{"\"kind\":\"\"", "\"kind\": \"\""},
		{"\"kind\":7", "\"kind\": 7"},
	};
	static const char *const colors[][2] = {
		{NULL, NULL},
		{"\"color\":\"hlg\"", "\"color\": \"hlg\""},
		{"\"color\":\"log\"", "\"color\": \"log\""},
	};
	for (int sp = 0; sp < 2; sp++)
		for (size_t i = 0; i < COUNT(codecs); i++)
			for (size_t k = 0; k < COUNT(kinds); k++)
				for (size_t l = 0; l < COUNT(colors); l++) {
					const char *m[] = {
						codecs[i][sp],
						sp ? "\"width\": 1920"
						   : "\"width\":1920",
						sp ? "\"height\": 1080"
						   : "\"height\":1080",
						sp ? "\"fps\": 60" : "\"fps\":60",
						kinds[k][sp],
						colors[l][sp],
					};
					char doc[256];
					for (int rev = 0; rev < 2; rev++) {
						build(doc, sizeof(doc), m,
						      COUNT(m), rev, sp);
						check_vc_parity(doc);
					}
				}
#undef COUNT
}

int main(void)
{
	test_hello_fake_phone();
	test_hello_basic();
	test_hello_field_isolation();
	test_hello_invalid();
	test_video_config();
	test_hello_parity();
	test_video_config_parity();
	printf("%d parity cases\n", parity_cases);
	TEST_MAIN_END();
}
