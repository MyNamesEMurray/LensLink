/*
 * Deterministic stand-in for libFuzzer: mutates the harness's seed corpus
 * with a fixed-seed PRNG for N iterations (argv[1], default 200000).
 * Every input is handed to the harness in an exact-size heap block, so
 * ASan catches a read one byte past the end.
 */

#include "fuzz.h"

#include <string.h>

static uint64_t g_state = 0x9E3779B97F4A7C15ull;

static uint32_t next_rand(void)
{
	/* xorshift64*: portable and identical on every platform. */
	g_state ^= g_state >> 12;
	g_state ^= g_state << 25;
	g_state ^= g_state >> 27;
	return (uint32_t)((g_state * 0x2545F4914F6CDD1Dull) >> 32);
}

/* Tokens worth splicing in: JSON syntax, escapes, the handshake keys,
 * malformed UTF-8. */
static const char *const dict[] = {
	"{", "}", "[", "]", ",", ":", "\"", "\\", "\\u0000", "\\ud800",
	"\\udc00", "\\u00e9", "true", "false", "null", "1e999", "-0",
	"\"kind\"", "\"screen\"", "\"name\"", "\"standby\"", "\"armed\"",
	"\"codec\"", "\"hevc\"", "\xC0\x80", "\xFF", "\xED\xA0\x80",
};

#define MAX_INPUT 4096

int main(int argc, char **argv)
{
	long iterations = argc > 1 ? atol(argv[1]) : 200000;
	size_t seed_count;
	const struct fuzz_seed *seeds = fuzz_seeds(&seed_count);
	uint8_t buf[MAX_INPUT];

	/* The corpus itself, and every prefix of it, first. */
	for (size_t s = 0; s < seed_count; s++) {
		for (size_t n = 0; n <= seeds[s].len; n++) {
			uint8_t *copy = malloc(n ? n : 1);
			memcpy(copy, seeds[s].data, n);
			LLVMFuzzerTestOneInput(copy, n);
			free(copy);
		}
	}

	for (long it = 0; it < iterations; it++) {
		const struct fuzz_seed *sd = &seeds[next_rand() % seed_count];
		size_t len = sd->len < MAX_INPUT ? sd->len : MAX_INPUT;
		memcpy(buf, sd->data, len);

		int mutations = 1 + (int)(next_rand() % 8);
		for (int m = 0; m < mutations; m++) {
			size_t pos = len ? next_rand() % len : 0;
			switch (next_rand() % 7) {
			case 0: /* flip a bit */
				if (len)
					buf[pos] ^= (uint8_t)(1u << (next_rand() % 8));
				break;
			case 1: /* random byte */
				if (len)
					buf[pos] = (uint8_t)next_rand();
				break;
			case 2: /* insert a random byte */
				if (len < MAX_INPUT) {
					memmove(buf + pos + 1, buf + pos,
						len - pos);
					buf[pos] = (uint8_t)next_rand();
					len++;
				}
				break;
			case 3: /* delete a byte */
				if (len) {
					memmove(buf + pos, buf + pos + 1,
						len - pos - 1);
					len--;
				}
				break;
			case 4: /* truncate */
				len = pos;
				break;
			case 5: { /* splice a dictionary token */
				const char *t = dict[next_rand() %
						     (sizeof(dict) / sizeof(dict[0]))];
				size_t tl = strlen(t);
				if (len + tl <= MAX_INPUT) {
					memmove(buf + pos + tl, buf + pos,
						len - pos);
					memcpy(buf + pos, t, tl);
					len += tl;
				}
				break;
			}
			case 6: /* duplicate a chunk */
				if (len && len < MAX_INPUT / 2) {
					size_t from = next_rand() % len;
					size_t n = 1 + next_rand() % (len - from);
					if (len + n <= MAX_INPUT) {
						memmove(buf + pos + n, buf + pos,
							len - pos);
						memmove(buf + pos,
							buf + (from < pos ? from
									  : from + n),
							n);
						len += n;
					}
				}
				break;
			}
		}

		uint8_t *copy = malloc(len ? len : 1);
		memcpy(copy, buf, len);
		LLVMFuzzerTestOneInput(copy, len);
		free(copy);
	}
	printf("ok (%ld iterations over %zu seeds)\n", iterations, seed_count);
	return 0;
}
