#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum still_layout { STILL_NV12, STILL_I420, STILL_P010, STILL_I010, STILL_BGRA };

struct still_src {
	enum still_layout layout;
	int width, height;
	const uint8_t *data[3];
	int linesize[3];
	bool full_range;
};

uint8_t *still_bmp(const struct still_src *src, int max_w, size_t *len);
