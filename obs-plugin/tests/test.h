/* Minimal assertion helpers for the plugin's standalone unit tests. */

#pragma once

#include <stdio.h>
#include <string.h>

static int test_failures;

#define CHECK(cond)                                                        \
	do {                                                               \
		if (!(cond)) {                                             \
			fprintf(stderr, "%s:%d: CHECK failed: %s\n",        \
				__FILE__, __LINE__, #cond);                \
			test_failures++;                                   \
		}                                                          \
	} while (0)

#define CHECK_STR(a, b)                                                    \
	do {                                                               \
		if (strcmp((a), (b)) != 0) {                               \
			fprintf(stderr,                                    \
				"%s:%d: CHECK_STR failed: \"%s\" != \"%s\"\n", \
				__FILE__, __LINE__, (a), (b));             \
			test_failures++;                                   \
		}                                                          \
	} while (0)

#define CHECK_NEAR(a, b)                                                   \
	do {                                                               \
		double _a = (a), _b = (b);                                 \
		double _d = _a > _b ? _a - _b : _b - _a;                   \
		if (_d > 1e-9 * (1.0 + (_a < 0 ? -_a : _a))) {             \
			fprintf(stderr, "%s:%d: CHECK_NEAR failed: %g != %g\n", \
				__FILE__, __LINE__, _a, _b);               \
			test_failures++;                                   \
		}                                                          \
	} while (0)

#define TEST_MAIN_END()                                                    \
	do {                                                               \
		if (test_failures)                                         \
			fprintf(stderr, "%d failure(s)\n", test_failures); \
		else                                                       \
			printf("ok\n");                                    \
		return test_failures ? 1 : 0;                              \
	} while (0)
