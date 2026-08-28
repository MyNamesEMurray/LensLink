#include <string.h>

#include "nv12-scale.h"

/* Limited-range black: Y=16, chroma centred at 128. Full-range 0 here
 * would read as a slightly glowing dark grey on a limited-range path. */
#define BLACK_Y 16
#define BLACK_C 128

void nv12_fill_black(uint8_t *dst, uint32_t width, uint32_t height)
{
	size_t y_size = (size_t)width * height;
	memset(dst, BLACK_Y, y_size);
	memset(dst + y_size, BLACK_C, y_size / 2);
}

/* Bilinear sample of a single-byte plane, 16.16 fixed point. */
static uint8_t sample_plane(const uint8_t *plane, uint32_t stride,
			    uint32_t width, uint32_t height, uint32_t fx,
			    uint32_t fy)
{
	uint32_t x0 = fx >> 16;
	uint32_t y0 = fy >> 16;
	uint32_t x1 = x0 + 1 < width ? x0 + 1 : x0;
	uint32_t y1 = y0 + 1 < height ? y0 + 1 : y0;
	uint32_t ax = fx & 0xFFFF;
	uint32_t ay = fy & 0xFFFF;

	const uint8_t *row0 = plane + (size_t)y0 * stride;
	const uint8_t *row1 = plane + (size_t)y1 * stride;

	uint32_t top = row0[x0] * (0x10000 - ax) + row0[x1] * ax;
	uint32_t bottom = row1[x0] * (0x10000 - ax) + row1[x1] * ax;

	return (uint8_t)(((uint64_t)top * (0x10000 - ay) +
			  (uint64_t)bottom * ay) >>
			 32);
}

/* Same, for one component of the interleaved chroma plane. */
static uint8_t sample_chroma(const uint8_t *plane, uint32_t stride,
			     uint32_t width, uint32_t height, uint32_t fx,
			     uint32_t fy, uint32_t component)
{
	uint32_t x0 = fx >> 16;
	uint32_t y0 = fy >> 16;
	uint32_t x1 = x0 + 1 < width ? x0 + 1 : x0;
	uint32_t y1 = y0 + 1 < height ? y0 + 1 : y0;
	uint32_t ax = fx & 0xFFFF;
	uint32_t ay = fy & 0xFFFF;

	const uint8_t *row0 = plane + (size_t)y0 * stride;
	const uint8_t *row1 = plane + (size_t)y1 * stride;

	uint32_t top = row0[x0 * 2 + component] * (0x10000 - ax) +
		       row0[x1 * 2 + component] * ax;
	uint32_t bottom = row1[x0 * 2 + component] * (0x10000 - ax) +
			  row1[x1 * 2 + component] * ax;

	return (uint8_t)(((uint64_t)top * (0x10000 - ay) +
			  (uint64_t)bottom * ay) >>
			 32);
}

void nv12_scale_letterbox(uint8_t *dst, uint32_t dw, uint32_t dh,
			  const uint8_t *src, uint32_t sw, uint32_t sh)
{
	if (!dst || !src || !dw || !dh || !sw || !sh)
		return;

	if (dw == sw && dh == sh) {
		memcpy(dst, src, (size_t)dw * dh * 3 / 2);
		return;
	}

	/* Largest even-sized box with the source's aspect that fits. Even
	 * because NV12 chroma is exactly half in both axes; an odd offset
	 * or extent would split a chroma pair. */
	uint32_t target_w = dw;
	uint32_t target_h = (uint32_t)((uint64_t)dw * sh / sw);
	if (target_h > dh) {
		target_h = dh;
		target_w = (uint32_t)((uint64_t)dh * sw / sh);
	}
	target_w &= ~1u;
	target_h &= ~1u;
	if (!target_w || !target_h) {
		nv12_fill_black(dst, dw, dh);
		return;
	}

	uint32_t off_x = ((dw - target_w) / 2) & ~1u;
	uint32_t off_y = ((dh - target_h) / 2) & ~1u;

	nv12_fill_black(dst, dw, dh);

	/* 16.16 step across the source per destination pixel. */
	uint32_t step_x = (uint32_t)(((uint64_t)(sw - 1) << 16) / target_w);
	uint32_t step_y = (uint32_t)(((uint64_t)(sh - 1) << 16) / target_h);

	const uint8_t *src_y = src;
	const uint8_t *src_uv = src + (size_t)sw * sh;
	uint8_t *dst_y = dst;
	uint8_t *dst_uv = dst + (size_t)dw * dh;

	for (uint32_t y = 0; y < target_h; y++) {
		uint8_t *row = dst_y + (size_t)(y + off_y) * dw + off_x;
		uint32_t fy = y * step_y;
		uint32_t fx = 0;
		for (uint32_t x = 0; x < target_w; x++, fx += step_x)
			row[x] = sample_plane(src_y, sw, sw, sh, fx, fy);
	}

	uint32_t cw = sw / 2, ch = sh / 2;
	uint32_t step_cx = (uint32_t)(((uint64_t)(cw - 1) << 16) /
				      (target_w / 2));
	uint32_t step_cy = (uint32_t)(((uint64_t)(ch - 1) << 16) /
				      (target_h / 2));

	for (uint32_t y = 0; y < target_h / 2; y++) {
		uint8_t *row = dst_uv + (size_t)(y + off_y / 2) * dw + off_x;
		uint32_t fy = y * step_cy;
		uint32_t fx = 0;
		for (uint32_t x = 0; x < target_w / 2; x++, fx += step_cx) {
			row[x * 2] = sample_chroma(src_uv, sw, cw, ch, fx, fy,
						   0);
			row[x * 2 + 1] = sample_chroma(src_uv, sw, cw, ch, fx,
						       fy, 1);
		}
	}
}
