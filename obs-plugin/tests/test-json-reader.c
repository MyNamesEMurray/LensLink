#include "json-reader.h"
#include "test.h"

#include <stdlib.h>

static struct json_reader reader(const char *json)
{
	struct json_reader r;
	lenslink_json_reader_init(&r, json, strlen(json));
	return r;
}

/* Consumes one whole value; true if it was valid JSON with nothing after. */
static bool valid(const char *json)
{
	struct json_reader r = reader(json);
	return lenslink_json_skip(&r) && lenslink_json_reader_done(&r);
}

static void test_scalars(void)
{
	struct json_reader r;
	double d;
	bool b;

	r = reader("42");
	CHECK(lenslink_json_read_number(&r, &d) && d == 42.0);
	r = reader("-0.5");
	CHECK(lenslink_json_read_number(&r, &d));
	CHECK_NEAR(d, -0.5);
	r = reader("1.25e2");
	CHECK(lenslink_json_read_number(&r, &d));
	CHECK_NEAR(d, 125.0);
	r = reader("2.5E-3");
	CHECK(lenslink_json_read_number(&r, &d));
	CHECK_NEAR(d, 0.0025);
	r = reader("0.000123");
	CHECK(lenslink_json_read_number(&r, &d));
	CHECK_NEAR(d, 0.000123);
	r = reader("0.016666666666666666");
	CHECK(lenslink_json_read_number(&r, &d));
	CHECK_NEAR(d, 1.0 / 60.0);
	r = reader("1e999");
	CHECK(lenslink_json_read_number(&r, &d) && d > 1e300); /* inf, not a crash */
	r = reader("1e-999");
	CHECK(lenslink_json_read_number(&r, &d) && d == 0.0);

	r = reader(" true ");
	CHECK(lenslink_json_read_bool(&r, &b) && b && lenslink_json_reader_done(&r));
	r = reader("false");
	CHECK(lenslink_json_read_bool(&r, &b) && !b);

	/* Type mismatch fails without latching an error. */
	r = reader("\"x\"");
	CHECK(!lenslink_json_read_number(&r, &d) && !r.error);
	CHECK(lenslink_json_skip(&r) && lenslink_json_reader_done(&r));
}

static void test_invalid_numbers(void)
{
	CHECK(!valid("01"));
	CHECK(!valid("1."));
	CHECK(!valid(".5"));
	CHECK(!valid("-"));
	CHECK(!valid("1e"));
	CHECK(!valid("+1"));
	CHECK(!valid("0x10"));
	CHECK(!valid("NaN"));
	CHECK(!valid("Infinity"));
}

static void test_strings(void)
{
	struct json_reader r;
	char buf[32];
	bool trunc;

	r = reader("\"a\\\"b\\\\c\\/d\\n\"");
	CHECK(lenslink_json_read_string(&r, buf, sizeof(buf), &trunc) && !trunc);
	CHECK_STR(buf, "a\"b\\c/d\n");

	/* \u escapes, including a surrogate pair (U+1F600). */
	r = reader("\"\\u00d7\\u20ac\\ud83d\\ude00\"");
	CHECK(lenslink_json_read_string(&r, buf, sizeof(buf), &trunc));
	CHECK_STR(buf, "\xC3\x97\xE2\x82\xAC\xF0\x9F\x98\x80");

	/* Lone surrogates become U+FFFD. */
	r = reader("\"\\ud83dx\\ude00\"");
	CHECK(lenslink_json_read_string(&r, buf, sizeof(buf), &trunc));
	CHECK_STR(buf, "\xEF\xBF\xBDx\xEF\xBF\xBD");

	/* Raw UTF-8 passes through; malformed bytes become U+FFFD. */
	r = reader("\"0.5\xC3\x97 \xFF\"");
	CHECK(lenslink_json_read_string(&r, buf, sizeof(buf), &trunc));
	CHECK_STR(buf, "0.5\xC3\x97 \xEF\xBF\xBD");

	/* Truncation lands on a code point boundary: "ab×" in 4 bytes
	 * (3 + NUL) keeps "ab" rather than half of the ×. */
	char small[4];
	r = reader("\"ab\xC3\x97z\"");
	CHECK(lenslink_json_read_string(&r, small, sizeof(small), &trunc) && trunc);
	CHECK_STR(small, "ab");
	CHECK(lenslink_json_reader_done(&r)); /* still consumed the whole string */

	CHECK(!valid("\"unterminated"));
	CHECK(!valid("\"bad \\x escape\""));
	CHECK(!valid("\"\\u12\""));
	CHECK(!valid("\"raw\ncontrol\""));
}

static void test_structures(void)
{
	CHECK(valid("{}"));
	CHECK(valid("[]"));
	CHECK(valid("{\"a\":[1,2,{\"b\":null}],\"c\":\"d\"}"));
	CHECK(valid(" { \"a\" : 1 , \"b\" : [ ] } "));

	CHECK(!valid("{\"a\":1,}"));
	CHECK(!valid("[1,]"));
	CHECK(!valid("[,1]"));
	CHECK(!valid("{,}"));
	CHECK(!valid("{\"a\" 1}"));
	CHECK(!valid("{\"a\":}"));
	CHECK(!valid("{\"a\":1"));
	CHECK(!valid("{\"a\":1}}"));
	CHECK(!valid("{\"a\":1} x"));
	CHECK(!valid("[1 2]"));
	CHECK(!valid("{1:2}"));
	CHECK(!valid(""));
	CHECK(!valid("   "));
	CHECK(!valid("nul"));
	CHECK(!valid("tru"));

	/* Nesting deeper than the limit is an error, not a stack overflow. */
	char deep[256];
	size_t n = 0;
	for (int i = 0; i < 100; i++)
		deep[n++] = '[';
	for (int i = 0; i < 100; i++)
		deep[n++] = ']';
	deep[n] = 0;
	CHECK(!valid(deep));

	/* Within the limit is fine. */
	CHECK(valid("[[[[[[[[1]]]]]]]]"));
}

static void test_object_walk(void)
{
	struct json_reader r = reader(
		"{\"name\":\"Stage Left\",\"n\":3,\"list\":[\"x\",\"y\"]}");
	char key[8], val[32];
	bool trunc = false;
	int keys = 0;

	CHECK(lenslink_json_object_begin(&r));
	while (lenslink_json_object_next(&r, key, sizeof(key), &trunc)) {
		keys++;
		if (strcmp(key, "name") == 0) {
			CHECK(lenslink_json_read_string(&r, val, sizeof(val), NULL));
			CHECK_STR(val, "Stage Left");
		} else if (strcmp(key, "list") == 0) {
			int items = 0;
			CHECK(lenslink_json_array_begin(&r));
			while (lenslink_json_array_next(&r)) {
				CHECK(lenslink_json_read_string(&r, val, sizeof(val),
						       NULL));
				items++;
			}
			CHECK(items == 2);
		} else {
			CHECK(lenslink_json_skip(&r));
		}
	}
	CHECK(keys == 3);
	CHECK(lenslink_json_reader_done(&r));

	/* A key longer than the buffer reports truncation. */
	r = reader("{\"averyveryverylongkey\":1}");
	CHECK(lenslink_json_object_begin(&r));
	CHECK(lenslink_json_object_next(&r, key, sizeof(key), &trunc) && trunc);
	CHECK(lenslink_json_skip(&r));
	CHECK(!lenslink_json_object_next(&r, key, sizeof(key), &trunc));
	CHECK(lenslink_json_reader_done(&r));
}

static void test_bounds(void)
{
	/* The reader must stop at `len`, not at a NUL: the payload is a
	 * packet buffer. Everything after the 7th byte is out of bounds. */
	const char buf[] = "{\"a\":1}GARBAGE";
	struct json_reader r;
	lenslink_json_reader_init(&r, buf, 7);
	CHECK(lenslink_json_skip(&r) && lenslink_json_reader_done(&r));

	/* A NUL inside the bounds is invalid JSON, not a terminator. */
	const char nul[] = {'{', '}', 0, ' '};
	lenslink_json_reader_init(&r, nul, sizeof(nul));
	CHECK(lenslink_json_skip(&r) && !lenslink_json_reader_done(&r));

	lenslink_json_reader_init(&r, NULL, 0);
	CHECK(!lenslink_json_skip(&r));

	/* Every prefix of a valid document is rejected cleanly. */
	const char doc[] = "{\"a\":[1,\"\\u00d7\",true,null],\"b\":{\"c\":-2.5e1}}";
	for (size_t len = 0; len + 1 < sizeof(doc); len++) {
		lenslink_json_reader_init(&r, doc, len);
		CHECK(!(lenslink_json_skip(&r) && lenslink_json_reader_done(&r)));
	}
	lenslink_json_reader_init(&r, doc, sizeof(doc) - 1);
	CHECK(lenslink_json_skip(&r) && lenslink_json_reader_done(&r));
}

/* Reads the single string value of `json` (which may contain NULs, hence
 * the explicit length). */
static bool read_one(const char *json, size_t len, char *buf, size_t size,
		     bool *trunc)
{
	struct json_reader r;
	lenslink_json_reader_init(&r, json, len);
	bool ok = lenslink_json_read_string(&r, buf, size, trunc);
	return ok && lenslink_json_reader_done(&r);
}

#define READ_LIT(lit, buf, trunc) \
	read_one((lit), sizeof(lit) - 1, (buf), sizeof(buf), (trunc))

static void test_escaped_nul(void)
{
	char buf[32];
	bool trunc;

	/* An escaped NUL never yields a shorter C string that means
	 * something else: the value is withheld ("") and flagged. */
	CHECK(READ_LIT("\"camera\\u0000screen\"", buf, &trunc));
	CHECK(trunc && buf[0] == 0);
	CHECK(READ_LIT("\"\\u0000\"", buf, &trunc));
	CHECK(trunc && buf[0] == 0);
	CHECK(READ_LIT("\"abc\\u0000\"", buf, &trunc));
	CHECK(trunc && buf[0] == 0);

	/* Same for keys: "kind\u0000x" must not match "kind". */
	struct json_reader r;
	const char obj[] = "{\"kind\\u0000x\":\"screen\"}";
	char key[16];
	lenslink_json_reader_init(&r, obj, sizeof(obj) - 1);
	CHECK(lenslink_json_object_begin(&r));
	CHECK(lenslink_json_object_next(&r, key, sizeof(key), &trunc));
	CHECK(trunc && key[0] == 0);
	CHECK(lenslink_json_skip(&r));
	CHECK(!lenslink_json_object_next(&r, key, sizeof(key), &trunc));
	CHECK(lenslink_json_reader_done(&r));

	/* Skipping (no buffer) a NUL-bearing string is fine. */
	CHECK(valid("[\"\\u0000\",1]"));

	/* \u0001 is a real, representable code point. */
	CHECK(READ_LIT("\"a\\u0001b\"", buf, &trunc));
	CHECK(!trunc && strcmp(buf, "a\x01" "b") == 0);
}

static void test_control_and_unicode(void)
{
	char buf[32];
	bool trunc;

	/* Literal control characters (including a raw NUL inside the
	 * bounds, and DEL-free C0) are syntax errors. */
	for (int c = 0; c < 0x20; c++) {
		char doc[4] = {'"', (char)c, '"', 0};
		CHECK(!read_one(doc, 3, buf, sizeof(buf), &trunc));
	}
	/* DEL (0x7F) is not a JSON control character. */
	CHECK(READ_LIT("\"\x7F\"", buf, &trunc) && strcmp(buf, "\x7F") == 0);

	/* Valid escapes, BMP and astral. */
	CHECK(READ_LIT("\"\\u0041\\u00e9\\uFFFD\"", buf, &trunc) && !trunc);
	CHECK_STR(buf, "A\xC3\xA9\xEF\xBF\xBD");
	CHECK(READ_LIT("\"\\uD834\\uDD1E\"", buf, &trunc)); /* U+1D11E */
	CHECK_STR(buf, "\xF0\x9D\x84\x9E");
	CHECK(READ_LIT("\"\\udbff\\udfff\"", buf, &trunc)); /* U+10FFFF */
	CHECK_STR(buf, "\xF4\x8F\xBF\xBF");

	/* Lone high surrogate: at the end, before text, before a
	 * non-surrogate escape, before another high surrogate. */
	CHECK(READ_LIT("\"\\ud800\"", buf, &trunc));
	CHECK_STR(buf, "\xEF\xBF\xBD");
	CHECK(READ_LIT("\"\\ud800a\"", buf, &trunc));
	CHECK_STR(buf, "\xEF\xBF\xBD" "a");
	CHECK(READ_LIT("\"\\ud800\\u0041\"", buf, &trunc));
	CHECK_STR(buf, "\xEF\xBF\xBD" "A");
	CHECK(READ_LIT("\"\\ud800\\ud800\\udc00\"", buf, &trunc));
	CHECK_STR(buf, "\xEF\xBF\xBD\xF0\x90\x80\x80");
	/* High surrogate followed by an escaped NUL: still withheld. */
	CHECK(READ_LIT("\"\\ud800\\u0000\"", buf, &trunc));
	CHECK(trunc && buf[0] == 0);

	/* Lone low surrogate, and a reversed pair. */
	CHECK(READ_LIT("\"\\udc00\"", buf, &trunc));
	CHECK_STR(buf, "\xEF\xBF\xBD");
	CHECK(READ_LIT("\"\\udc00\\ud800\"", buf, &trunc));
	CHECK_STR(buf, "\xEF\xBF\xBD\xEF\xBF\xBD");

	/* Malformed pairs: bad hex in the low half, truncated low half. */
	CHECK(!valid("\"\\ud800\\udcXX\""));
	CHECK(!valid("\"\\ud800\\udc\""));
	CHECK(!valid("\"\\ud800\\u\""));
	CHECK(!valid("\"\\ud800\\"));

	/* Invalid UTF-8 → U+FFFD per bad byte, never passed through:
	 * overlong (C0 80 = NUL!), surrogate-range (ED A0 80), > U+10FFFF
	 * (F5..), stray continuation, truncated sequence at the quote. */
	CHECK(READ_LIT("\"\xC0\x80\"", buf, &trunc));
	CHECK(memchr(buf, 0, strlen(buf) + 1) == buf + strlen(buf));
	CHECK(strstr(buf, "\xEF\xBF\xBD") == buf);
	CHECK(READ_LIT("\"\xF5\x80\x80\x80\"", buf, &trunc));
	CHECK(strncmp(buf, "\xEF\xBF\xBD", 3) == 0);
	CHECK(READ_LIT("\"\x80x\"", buf, &trunc));
	CHECK_STR(buf, "\xEF\xBF\xBD" "x");
	CHECK(READ_LIT("\"\xE2\x82\"", buf, &trunc));
	CHECK_STR(buf, "\xEF\xBF\xBD\xEF\xBF\xBD");
}

static void test_number_extremes(void)
{
	struct json_reader r;
	double d;

	r = reader("1e999999999999999999");
	CHECK(lenslink_json_read_number(&r, &d) && d > 1e308);
	r = reader("-1e999999999999999999");
	CHECK(lenslink_json_read_number(&r, &d) && d < -1e308);
	r = reader("1e-999999999999999999");
	CHECK(lenslink_json_read_number(&r, &d) && d == 0.0);
	/* Zero with a huge exponent is zero, not NaN (0 * inf). */
	r = reader("0e999");
	CHECK(lenslink_json_read_number(&r, &d) && d == 0.0);
	r = reader("-0.0e400");
	CHECK(lenslink_json_read_number(&r, &d) && d == 0.0);
	/* Integer overflow: far past int64, still a finite double. */
	r = reader("123456789012345678901234567890");
	CHECK(lenslink_json_read_number(&r, &d));
	CHECK_NEAR(d, 1.2345678901234568e29);
	r = reader("-9223372036854775809");
	CHECK(lenslink_json_read_number(&r, &d) && d < -9.2e18 && d > -9.3e18);
	/* Floating-point overflow by mantissa x exponent. */
	r = reader("9999999999e300");
	CHECK(lenslink_json_read_number(&r, &d) && d > 1e308);
	/* A very long digit string is consumed, not overflowed. */
	char big[700];
	big[0] = '1';
	for (int i = 1; i < 699; i++)
		big[i] = '0';
	big[699] = 0;
	r = reader(big);
	CHECK(lenslink_json_read_number(&r, &d) && d > 1e308 &&
	      lenslink_json_reader_done(&r));
}

static void test_duplicate_keys(void)
{
	/* The reader reports every occurrence; policy (reject, first or
	 * last wins) is the caller's, and each parser documents it. */
	struct json_reader r = reader("{\"a\":1,\"a\":2}");
	char key[8];
	double d;
	int seen = 0;
	CHECK(lenslink_json_object_begin(&r));
	while (lenslink_json_object_next(&r, key, sizeof(key), NULL)) {
		CHECK_STR(key, "a");
		CHECK(lenslink_json_read_number(&r, &d));
		seen++;
	}
	CHECK(seen == 2 && lenslink_json_reader_done(&r));
}

static void test_oversized(void)
{
	/* A string far larger than the buffer is consumed whole and
	 * reported truncated; a huge array is walked without limit on
	 * element count (callers cap what they keep). */
	static char doc[70000];
	size_t n = 0;
	doc[n++] = '[';
	doc[n++] = '"';
	for (int i = 0; i < 40000; i++)
		doc[n++] = 'x';
	doc[n++] = '"';
	for (int i = 0; i < 5000; i++) {
		doc[n++] = ',';
		doc[n++] = '1';
	}
	doc[n++] = ']';
	doc[n] = 0;

	struct json_reader r;
	lenslink_json_reader_init(&r, doc, n);
	char buf[16];
	bool trunc = false;
	int items = 0;
	CHECK(lenslink_json_array_begin(&r));
	CHECK(lenslink_json_array_next(&r));
	CHECK(lenslink_json_read_string(&r, buf, sizeof(buf), &trunc) && trunc);
	CHECK(strlen(buf) == 15);
	while (lenslink_json_array_next(&r)) {
		CHECK(lenslink_json_skip(&r));
		items++;
	}
	CHECK(items == 5000 && lenslink_json_reader_done(&r));

	/* Nesting exactly at the limit fails; one below succeeds. */
	char deep[64];
	for (int depth = JSON_READER_MAX_DEPTH - 2; depth <= JSON_READER_MAX_DEPTH;
	     depth++) {
		size_t k = 0;
		for (int i = 0; i < depth; i++)
			deep[k++] = '[';
		for (int i = 0; i < depth; i++)
			deep[k++] = ']';
		deep[k] = 0;
		CHECK(valid(deep) == (depth < JSON_READER_MAX_DEPTH));
	}
}

static void test_truncation_everywhere(void)
{
	/* Every prefix of a document exercising every token kind (escapes,
	 * surrogates, exponents, literals, nesting) is rejected cleanly,
	 * and never reads past the prefix (ASan checks the latter: each
	 * prefix is copied into an exact-size heap block). */
	const char doc[] =
		"{\"s\":\"a\\\"\\\\\\/\\b\\f\\n\\r\\t\\u00e9\\ud83d\\ude00\","
		"\"n\":[-0.5e-3,12,0,1E+2],\"t\":true,\"f\":false,"
		"\"z\":null,\"o\":{\"k\":[[]]}}";
	struct json_reader r;
	for (size_t len = 0; len + 1 < sizeof(doc); len++) {
		char *copy = malloc(len ? len : 1);
		memcpy(copy, doc, len);
		lenslink_json_reader_init(&r, copy, len);
		CHECK(!(lenslink_json_skip(&r) && lenslink_json_reader_done(&r)));
		free(copy);
	}
	lenslink_json_reader_init(&r, doc, sizeof(doc) - 1);
	CHECK(lenslink_json_skip(&r) && lenslink_json_reader_done(&r));

	/* Truncated escapes specifically. */
	CHECK(!valid("\"\\"));
	CHECK(!valid("\"\\u"));
	CHECK(!valid("\"\\u0"));
	CHECK(!valid("\"\\u00"));
	CHECK(!valid("\"\\u004"));
	CHECK(!valid("\"\\u0041"));
}

int main(void)
{
	test_scalars();
	test_invalid_numbers();
	test_strings();
	test_structures();
	test_object_walk();
	test_bounds();
	test_escaped_nul();
	test_control_and_unicode();
	test_number_extremes();
	test_duplicate_keys();
	test_oversized();
	test_truncation_everywhere();
	TEST_MAIN_END();
}
