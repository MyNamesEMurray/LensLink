#include <stdio.h>
#include <string.h>

#include "web-auth.h"

static int failures;

#define CHECK(cond)                                                       \
	do {                                                              \
		if (!(cond)) {                                            \
			printf("FAIL %s:%d: %s\n", __FILE__, __LINE__,   \
			       #cond);                                    \
			failures++;                                       \
		}                                                         \
	} while (0)

static bool host_ok(const char *v, bool scheme)
{
	char h[WEB_AUTH_HOST_MAX];
	int port;
	return web_auth_parse_host(v, scheme, h, sizeof(h), &port);
}

static bool loopback(const char *v, bool scheme)
{
	char h[WEB_AUTH_HOST_MAX];
	int port;
	return web_auth_parse_host(v, scheme, h, sizeof(h), &port) &&
	       web_auth_is_loopback_host(h);
}

static void test_parse(void)
{
	char h[WEB_AUTH_HOST_MAX];
	int port;
	CHECK(web_auth_parse_host(" LocalHost:9980\r\n", false, h, sizeof(h),
				  &port));
	CHECK(strcmp(h, "localhost") == 0 && port == 9980);
	CHECK(web_auth_parse_host("http://10.0.0.5", true, h, sizeof(h),
				  &port));
	CHECK(strcmp(h, "10.0.0.5") == 0 && port == -1);
	CHECK(!host_ok("", false));
	CHECK(!host_ok("localhost:", false));
	CHECK(!host_ok("localhost:99999", false));
	CHECK(!host_ok("localhost:80x", false));
	CHECK(!host_ok("localhost:80 junk", false));
	CHECK(!host_ok("localhost/path", false));
	CHECK(!host_ok("a@b", false));
	CHECK(!host_ok("http://localhost", false));
	CHECK(!host_ok("localhost", true));
	CHECK(!host_ok("https://localhost", true));
	CHECK(!host_ok("null", true) || !loopback("null", true));
}

static void test_loopback(void)
{
	CHECK(loopback("localhost", false));
	CHECK(loopback("localhost:9980", false));
	CHECK(loopback("127.0.0.1:9980\r\n", false));
	CHECK(loopback("http://127.0.0.1:9980", true));
	CHECK(!loopback("localhost.evil.com", false));
	CHECK(!loopback("127.0.0.1.evil.com:9980", false));
	CHECK(!loopback("http://127.0.0.1.evil.com", true));
	CHECK(!loopback("localhostx", false));
	CHECK(!loopback("localhost@evil.com", false));
	CHECK(!loopback("127.0.0.2", false));
}

static void test_ipv4(void)
{
	CHECK(web_auth_is_ipv4_literal("192.168.1.20"));
	CHECK(web_auth_is_ipv4_literal("0.0.0.0"));
	CHECK(!web_auth_is_ipv4_literal("192.168.1"));
	CHECK(!web_auth_is_ipv4_literal("192.168.1.256"));
	CHECK(!web_auth_is_ipv4_literal("192.168.01.1"));
	CHECK(!web_auth_is_ipv4_literal("1.2.3.4.5"));
	CHECK(!web_auth_is_ipv4_literal("1.2.3.4.evil.com"));
	CHECK(!web_auth_is_ipv4_literal("pc.local"));
	CHECK(!web_auth_is_ipv4_literal(""));
}

static void test_key(void)
{
	char k[WEB_AUTH_KEY_SIZE];
	CHECK(web_auth_key_equal("abc123", "abc123"));
	CHECK(!web_auth_key_equal("abc123", "abc124"));
	CHECK(!web_auth_key_equal("abc123", "abc12"));
	CHECK(!web_auth_key_equal("", ""));

	CHECK(web_auth_query_key("GET /?key=abc HTTP/1.1\r\n", k, sizeof(k)));
	CHECK(strcmp(k, "abc") == 0);
	CHECK(web_auth_query_key("GET /api/state?src=1&key=f0 HTTP/1.1", k,
				 sizeof(k)));
	CHECK(strcmp(k, "f0") == 0);
	CHECK(!web_auth_query_key("GET / HTTP/1.1", k, sizeof(k)));
	CHECK(!web_auth_query_key("GET /?monkey=abc HTTP/1.1", k, sizeof(k)));
	CHECK(!web_auth_query_key("GET /?key= HTTP/1.1", k, sizeof(k)));
	CHECK(!web_auth_query_key("GET /?key=abc", k, sizeof(k)));
	CHECK(!web_auth_query_key(
		"GET /?key=0123456789012345678901234567890123456789 HTTP/1.1",
		k, sizeof(k)));

	CHECK(web_auth_cookie_key(" a=b; ll_key=beef; c=d\r\n", k, sizeof(k)));
	CHECK(strcmp(k, "beef") == 0);
	CHECK(web_auth_cookie_key("ll_key=beef", k, sizeof(k)));
	CHECK(!web_auth_cookie_key("xll_key=beef", k, sizeof(k)));
	CHECK(!web_auth_cookie_key("a=b", k, sizeof(k)));

	CHECK(web_auth_random_key(k));
	CHECK(strlen(k) == 32);
	char k2[WEB_AUTH_KEY_SIZE];
	CHECK(web_auth_random_key(k2));
	CHECK(strcmp(k, k2) != 0);
}

static void test_content_length(void)
{
	size_t n = 99;
	CHECK(web_auth_content_length(" 12\r\n", 512, &n) && n == 12);
	CHECK(web_auth_content_length("0", 512, &n) && n == 0);
	CHECK(web_auth_content_length("512", 512, &n) && n == 512);
	CHECK(!web_auth_content_length("513", 512, &n));
	CHECK(!web_auth_content_length("", 512, &n));
	CHECK(!web_auth_content_length("-1", 512, &n));
	CHECK(!web_auth_content_length("12abc", 512, &n));
	CHECK(!web_auth_content_length("1 2", 512, &n));
	CHECK(!web_auth_content_length("99999999999999999999", 512, &n));
}

static void test_check(void)
{
	const char *key = "0123456789abcdef0123456789abcdef";
	const char *get = "GET / HTTP/1.1\r\n";
	const char *getkey =
		"GET /?key=0123456789abcdef0123456789abcdef HTTP/1.1\r\n";

	CHECK(web_auth_check("localhost:9980", NULL, NULL, get, true, false,
			     key) == WEB_AUTH_OK);
	CHECK(web_auth_check("localhost:9980", "http://127.0.0.1:9980", NULL,
			     get, true, false, key) == WEB_AUTH_OK);
	CHECK(web_auth_check("localhost.evil.com", NULL, NULL, get, true,
			     false, key) == WEB_AUTH_DENY);
	CHECK(web_auth_check("localhost:9980", "http://127.0.0.1.evil.com",
			     NULL, get, true, false, key) == WEB_AUTH_DENY);
	CHECK(web_auth_check(NULL, NULL, NULL, get, true, false, key) ==
	      WEB_AUTH_DENY);
	CHECK(web_auth_check("192.168.1.5:9980", NULL, NULL, getkey, true,
			     false, key) == WEB_AUTH_DENY);
	CHECK(web_auth_check("localhost", NULL, NULL, get, true, true, key) ==
	      WEB_AUTH_OK);

	CHECK(web_auth_check("192.168.1.5:9980", NULL, NULL, getkey, false,
			     false, key) == WEB_AUTH_DENY);
	CHECK(web_auth_check("192.168.1.5:9980", NULL, NULL, get, false, true,
			     key) == WEB_AUTH_DENY);
	CHECK(web_auth_check("192.168.1.5:9980", NULL, NULL, getkey, false,
			     true, key) == WEB_AUTH_OK_QUERY_KEY);
	CHECK(web_auth_check("192.168.1.5:9980", NULL,
			     "ll_key=0123456789abcdef0123456789abcdef", get,
			     false, true, key) == WEB_AUTH_OK);
	CHECK(web_auth_check("192.168.1.5:9980", "http://192.168.1.5:9980",
			     "ll_key=0123456789abcdef0123456789abcdef", get,
			     false, true, key) == WEB_AUTH_OK);
	CHECK(web_auth_check("192.168.1.5:9980", "http://192.168.1.6:9980",
			     "ll_key=0123456789abcdef0123456789abcdef", get,
			     false, true, key) == WEB_AUTH_DENY);
	CHECK(web_auth_check("192.168.1.5:9980", "http://evil.com",
			     "ll_key=0123456789abcdef0123456789abcdef", get,
			     false, true, key) == WEB_AUTH_DENY);
	CHECK(web_auth_check("pc.evil.com:9980", NULL,
			     "ll_key=0123456789abcdef0123456789abcdef", get,
			     false, true, key) == WEB_AUTH_DENY);
	CHECK(web_auth_check("localhost:9980", NULL,
			     "ll_key=0123456789abcdef0123456789abcdef", get,
			     false, true, key) == WEB_AUTH_DENY);
	CHECK(web_auth_check("192.168.1.5", NULL, "ll_key=wrong", get, false,
			     true, key) == WEB_AUTH_DENY);
	CHECK(web_auth_check("192.168.1.5", NULL, "ll_key=x", getkey, false,
			     true, "") == WEB_AUTH_DENY);
}

int main(void)
{
	test_parse();
	test_loopback();
	test_ipv4();
	test_key();
	test_content_length();
	test_check();
	if (failures) {
		printf("%d failure(s)\n", failures);
		return 1;
	}
	printf("web-auth: all tests passed\n");
	return 0;
}
