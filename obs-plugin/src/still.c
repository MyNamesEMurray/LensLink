#include "still.h"

#include <stdlib.h>
#include <string.h>

static void put_le32(uint8_t *p, uint32_t v)
{
	p[0] = (uint8_t)v;
	p[1] = (uint8_t)(v >> 8);
	p[2] = (uint8_t)(v >> 16);
	p[3] = (uint8_t)(v >> 24);
}

static uint8_t clamp8(int v)
{
	return (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
}

static int sample16(const uint8_t *row, int i, bool high)
{
	int v = row[2 * i] | (row[2 * i + 1] << 8);
	return high ? v >> 8 : v >> 2;
}

static void yuv_at(const struct still_src *s, int x, int y, int *Y, int *U,
		   int *V)
{
	const uint8_t *yr = s->data[0] + (size_t)y * s->linesize[0];
	int cx = x / 2, cy = y / 2;

	switch (s->layout) {
	case STILL_NV12: {
		const uint8_t *c = s->data[1] + (size_t)cy * s->linesize[1];
		*Y = yr[x];
		*U = c[2 * cx];
		*V = c[2 * cx + 1];
		break;
	}
	case STILL_I420:
		*Y = yr[x];
		*U = s->data[1][(size_t)cy * s->linesize[1] + cx];
		*V = s->data[2][(size_t)cy * s->linesize[2] + cx];
		break;
	case STILL_P010: {
		const uint8_t *c = s->data[1] + (size_t)cy * s->linesize[1];
		*Y = sample16(yr, x, true);
		*U = sample16(c, 2 * cx, true);
		*V = sample16(c, 2 * cx + 1, true);
		break;
	}
	case STILL_I010:
		*Y = sample16(yr, x, false);
		*U = sample16(s->data[1] + (size_t)cy * s->linesize[1], cx,
			      false);
		*V = sample16(s->data[2] + (size_t)cy * s->linesize[2], cx,
			      false);
		break;
	default:
		*Y = *U = *V = 0;
	}
}

uint8_t *still_bmp(const struct still_src *s, int max_w, size_t *len)
{
	if (!s || s->width <= 0 || s->height <= 0 || max_w <= 0 || !s->data[0])
		return NULL;

	int w = s->width < max_w ? s->width : max_w;
	int h = (int)((long long)s->height * w / s->width);
	if (h < 1)
		h = 1;
	int stride = (w * 3 + 3) & ~3;
	size_t size = 54 + (size_t)stride * h;
	uint8_t *bmp = calloc(1, size);
	if (!bmp)
		return NULL;

	bmp[0] = 'B';
	bmp[1] = 'M';
	put_le32(bmp + 2, (uint32_t)size);
	put_le32(bmp + 10, 54);
	put_le32(bmp + 14, 40);
	put_le32(bmp + 18, (uint32_t)w);
	put_le32(bmp + 22, (uint32_t)h);
	bmp[26] = 1;
	bmp[28] = 24;
	put_le32(bmp + 34, (uint32_t)(stride * h));

	for (int oy = 0; oy < h; oy++) {
		int y = (int)((long long)oy * s->height / h);
		uint8_t *out = bmp + 54 + (size_t)(h - 1 - oy) * stride;
		for (int ox = 0; ox < w; ox++) {
			int x = (int)((long long)ox * s->width / w);
			uint8_t *px = out + 3 * ox;
			if (s->layout == STILL_BGRA) {
				const uint8_t *in = s->data[0] +
						    (size_t)y * s->linesize[0] +
						    4 * x;
				memcpy(px, in, 3);
				continue;
			}
			int Y, U, V;
			yuv_at(s, x, y, &Y, &U, &V);
			int c = s->full_range ? (Y << 10) : (Y - 16) * 1197;
			int d = U - 128, e = V - 128;
			if (!s->full_range) {
				d = d * 1167 >> 10;
				e = e * 1167 >> 10;
			}
			px[2] = clamp8((c + 1613 * e) >> 10);
			px[1] = clamp8((c - 192 * d - 479 * e) >> 10);
			px[0] = clamp8((c + 1900 * d) >> 10);
		}
	}
	if (len)
		*len = size;
	return bmp;
}
