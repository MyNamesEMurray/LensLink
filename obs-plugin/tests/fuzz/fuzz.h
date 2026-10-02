/*
 * Fuzz harness contract. Each fuzz-*.c defines LLVMFuzzerTestOneInput
 * (libFuzzer's entry point, so a harness links against -fsanitize=fuzzer
 * unchanged) and a seed corpus. Without libFuzzer, fuzz-driver.c runs a
 * deterministic, seeded mutation loop over the corpus instead — that is
 * what ctest runs. A harness aborts on any broken invariant, so both
 * drivers (and the sanitizers) report it.
 */

#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

struct fuzz_seed {
	const char *data;
	size_t len;
};

#define FUZZ_SEED(lit) {(lit), sizeof(lit) - 1}

/* Implemented by each harness. */
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);
const struct fuzz_seed *fuzz_seeds(size_t *count);

#define FUZZ_ASSERT(cond)                                                  \
	do {                                                               \
		if (!(cond)) {                                             \
			fprintf(stderr, "%s:%d: fuzz invariant failed: %s\n", \
				__FILE__, __LINE__, #cond);                \
			abort();                                           \
		}                                                          \
	} while (0)

/* A NUL-terminated field of `size` bytes that is valid UTF-8 with no
 * NUL before its terminator. */
static inline int fuzz_utf8_field_ok(const char *s, size_t size)
{
	size_t n = 0;
	while (n < size && s[n])
		n++;
	if (n == size)
		return 0; /* unterminated */
	for (size_t i = 0; i < n;) {
		unsigned char c = (unsigned char)s[i];
		size_t len = c < 0x80   ? 1
			     : c < 0xC2 ? 0
			     : c < 0xE0 ? 2
			     : c < 0xF0 ? 3
			     : c < 0xF5 ? 4
					: 0;
		if (!len || i + len > n)
			return 0;
		for (size_t k = 1; k < len; k++)
			if (((unsigned char)s[i + k] & 0xC0) != 0x80)
				return 0;
		i += len;
	}
	return 1;
}
