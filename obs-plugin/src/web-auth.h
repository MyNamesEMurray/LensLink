/*
 * Request authorization for the web control panel: exact Host/Origin
 * parsing, loopback and IPv4-literal checks, the LAN access key. Pure C
 * with no libobs dependency, so it is unit-tested standalone.
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WEB_AUTH_KEY_SIZE 33
#define WEB_AUTH_HOST_MAX 64

enum web_auth_result {
	WEB_AUTH_DENY,
	WEB_AUTH_OK,
	WEB_AUTH_OK_QUERY_KEY,
};

/* Parses a Host or Origin header value (leading blanks skipped; ends at
 * CR/LF/NUL after optional trailing blanks): [http://]host[:port]. `host`
 * is lowercased; *port is -1 when absent. Anything else fails. */
bool web_auth_parse_host(const char *value, bool with_scheme, char *host,
			 size_t host_size, int *port);

bool web_auth_is_loopback_host(const char *host);
bool web_auth_is_ipv4_literal(const char *host);

/* Constant-time equality for equal-length keys; false for empty input. */
bool web_auth_key_equal(const char *a, const char *b);

/* Key from the request target's "?key=" parameter / a Cookie header's
 * "ll_key" cookie. */
bool web_auth_query_key(const char *request, char *out, size_t size);
bool web_auth_cookie_key(const char *cookie_value, char *out, size_t size);

/* A Content-Length header value: digits only, at most `max`. */
bool web_auth_content_length(const char *value, size_t max, size_t *out);

/* Decides one request. `host`/`origin`/`cookie` are raw header values
 * (origin and cookie NULL when absent); `request` is the request line.
 * Loopback peers, and every peer while LAN access is off, need an exact
 * loopback Host and (if sent) an exact loopback Origin. Other peers need
 * an IPv4-literal Host, an Origin equal to http://<Host> and the key. */
enum web_auth_result web_auth_check(const char *host, const char *origin,
				    const char *cookie, const char *request,
				    bool peer_loopback, bool lan_enabled,
				    const char *key);

/* 128 random bits from the platform CSPRNG as 32 hex chars. */
bool web_auth_random_key(char out[WEB_AUTH_KEY_SIZE]);

#ifdef __cplusplus
}
#endif
