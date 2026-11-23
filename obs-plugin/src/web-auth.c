#ifdef _WIN32
#define _CRT_RAND_S
#endif

#include "web-auth.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#ifndef _WIN32
#include <fcntl.h>
#include <unistd.h>
#endif

static bool is_blank(char c)
{
	return c == ' ' || c == '\t';
}

static bool is_end(char c)
{
	return c == '\0' || c == '\r' || c == '\n';
}

bool web_auth_parse_host(const char *v, bool with_scheme, char *host,
			 size_t host_size, int *port)
{
	while (is_blank(*v))
		v++;
	if (with_scheme) {
		for (int i = 0; i < 7; i++)
			if (tolower((unsigned char)v[i]) != "http://"[i])
				return false;
		v += 7;
	}
	size_t n = 0;
	while (!is_end(*v) && *v != ':' && !is_blank(*v)) {
		if (!isalnum((unsigned char)*v) && *v != '.' && *v != '-')
			return false;
		if (n + 1 >= host_size)
			return false;
		host[n++] = (char)tolower((unsigned char)*v++);
	}
	host[n] = 0;
	if (n == 0)
		return false;
	*port = -1;
	if (*v == ':') {
		v++;
		int p = 0, digits = 0;
		while (*v >= '0' && *v <= '9') {
			p = p * 10 + (*v++ - '0');
			if (++digits > 5)
				return false;
		}
		if (digits == 0 || p > 65535)
			return false;
		*port = p;
	}
	while (is_blank(*v))
		v++;
	return is_end(*v);
}

bool web_auth_is_loopback_host(const char *host)
{
	return strcmp(host, "localhost") == 0 ||
	       strcmp(host, "127.0.0.1") == 0;
}

bool web_auth_is_ipv4_literal(const char *host)
{
	int octets = 0;
	for (;;) {
		int digits = 0, val = 0;
		const char *start = host;
		while (*host >= '0' && *host <= '9') {
			val = val * 10 + (*host++ - '0');
			if (++digits > 3)
				return false;
		}
		if (digits == 0 || val > 255 || (digits > 1 && *start == '0'))
			return false;
		octets++;
		if (*host == '.') {
			host++;
			continue;
		}
		return octets == 4 && *host == 0;
	}
}

bool web_auth_key_equal(const char *a, const char *b)
{
	size_t la = strlen(a), lb = strlen(b);
	if (la == 0 || la != lb)
		return false;
	unsigned char diff = 0;
	for (size_t i = 0; i < la; i++)
		diff |= (unsigned char)(a[i] ^ b[i]);
	return diff == 0;
}

static bool copy_token(const char *p, char *out, size_t size)
{
	size_t n = 0;
	while (isalnum((unsigned char)*p)) {
		if (n + 1 >= size)
			return false;
		out[n++] = *p++;
	}
	out[n] = 0;
	return n > 0;
}

bool web_auth_query_key(const char *request, char *out, size_t size)
{
	const char *sp = strchr(request, ' ');
	const char *end = sp ? strchr(sp + 1, ' ') : NULL;
	const char *q = end ? memchr(sp, '?', (size_t)(end - sp)) : NULL;
	if (!q)
		return false;
	for (q++; q < end;) {
		if (strncmp(q, "key=", 4) == 0)
			return copy_token(q + 4, out, size);
		const char *amp = memchr(q, '&', (size_t)(end - q));
		if (!amp)
			break;
		q = amp + 1;
	}
	return false;
}

bool web_auth_cookie_key(const char *v, char *out, size_t size)
{
	while (!is_end(*v)) {
		while (is_blank(*v) || *v == ';')
			v++;
		if (strncmp(v, "ll_key=", 7) == 0)
			return copy_token(v + 7, out, size);
		while (!is_end(*v) && *v != ';')
			v++;
	}
	return false;
}

bool web_auth_content_length(const char *v, size_t max, size_t *out)
{
	while (is_blank(*v))
		v++;
	size_t n = 0;
	int digits = 0;
	while (*v >= '0' && *v <= '9') {
		n = n * 10 + (size_t)(*v++ - '0');
		if (++digits > 9)
			return false;
	}
	while (is_blank(*v))
		v++;
	if (digits == 0 || !is_end(*v) || n > max)
		return false;
	*out = n;
	return true;
}

static bool loopback_rules(const char *host, const char *origin)
{
	char h[WEB_AUTH_HOST_MAX];
	int port;
	if (!web_auth_parse_host(host, false, h, sizeof(h), &port) ||
	    !web_auth_is_loopback_host(h))
		return false;
	if (!origin)
		return true;
	return web_auth_parse_host(origin, true, h, sizeof(h), &port) &&
	       web_auth_is_loopback_host(h);
}

enum web_auth_result web_auth_check(const char *host, const char *origin,
				    const char *cookie, const char *request,
				    bool peer_loopback, bool lan_enabled,
				    const char *key)
{
	if (!host)
		return WEB_AUTH_DENY;
	if (peer_loopback || !lan_enabled)
		return loopback_rules(host, origin) ? WEB_AUTH_OK
						    : WEB_AUTH_DENY;

	char h[WEB_AUTH_HOST_MAX], o[WEB_AUTH_HOST_MAX];
	int hp, op;
	if (!web_auth_parse_host(host, false, h, sizeof(h), &hp) ||
	    !web_auth_is_ipv4_literal(h))
		return WEB_AUTH_DENY;
	if (origin && (!web_auth_parse_host(origin, true, o, sizeof(o), &op) ||
		       strcmp(o, h) != 0 || op != hp))
		return WEB_AUTH_DENY;

	char presented[WEB_AUTH_KEY_SIZE];
	if (cookie &&
	    web_auth_cookie_key(cookie, presented, sizeof(presented)) &&
	    web_auth_key_equal(presented, key))
		return WEB_AUTH_OK;
	if (request &&
	    web_auth_query_key(request, presented, sizeof(presented)) &&
	    web_auth_key_equal(presented, key))
		return WEB_AUTH_OK_QUERY_KEY;
	return WEB_AUTH_DENY;
}

bool web_auth_random_key(char out[WEB_AUTH_KEY_SIZE])
{
	uint8_t raw[16];
#ifdef _WIN32
	for (int i = 0; i < 4; i++) {
		unsigned int v;
		if (rand_s(&v) != 0)
			return false;
		memcpy(raw + i * 4, &v, 4);
	}
#else
	int fd = open("/dev/urandom", O_RDONLY);
	if (fd < 0)
		return false;
	size_t got = 0;
	while (got < sizeof(raw)) {
		ssize_t n = read(fd, raw + got, sizeof(raw) - got);
		if (n <= 0)
			break;
		got += (size_t)n;
	}
	close(fd);
	if (got < sizeof(raw))
		return false;
#endif
	for (int i = 0; i < 16; i++)
		snprintf(out + i * 2, 3, "%02x", raw[i]);
	return true;
}
