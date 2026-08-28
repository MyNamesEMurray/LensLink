/*
 * Snapshot writer, shared by every virtual-camera backend.
 *
 * A verification hook, not a feature: --snapshot is the one way to
 * confirm from a headless run that real pixels came off the phone,
 * which is exactly what the smoke test asserts.
 */

#include <obs-module.h>

#include <stdio.h>

#include "vcam.h"

/* BT.601 limited-range YCbCr -> RGB. Good enough for an eyeball check;
 * this never touches the frames an app actually receives. */
static void nv12_to_rgb_row(const uint8_t *y_row, const uint8_t *uv_row,
			    uint8_t *rgb, uint32_t width)
{
	for (uint32_t x = 0; x < width; x++) {
		int y = (int)y_row[x] - 16;
		int u = (int)uv_row[(x / 2) * 2] - 128;
		int v = (int)uv_row[(x / 2) * 2 + 1] - 128;

		int r = (298 * y + 409 * v + 128) >> 8;
		int g = (298 * y - 100 * u - 208 * v + 128) >> 8;
		int b = (298 * y + 516 * u + 128) >> 8;

		rgb[x * 3 + 0] = (uint8_t)(r < 0 ? 0 : r > 255 ? 255 : r);
		rgb[x * 3 + 1] = (uint8_t)(g < 0 ? 0 : g > 255 ? 255 : g);
		rgb[x * 3 + 2] = (uint8_t)(b < 0 ? 0 : b > 255 ? 255 : b);
	}
}

void vcam_write_ppm(const char *path, const uint8_t *nv12, uint32_t width,
		    uint32_t height)
{
	FILE *f = fopen(path, "wb");
	if (!f) {
		blog(LOG_WARNING, "[lenslink] cannot write snapshot to %s",
		     path);
		return;
	}

	fprintf(f, "P6\n%u %u\n255\n", width, height);

	const uint8_t *uv = nv12 + (size_t)width * height;
	uint8_t *rgb = bmalloc((size_t)width * 3);
	for (uint32_t row = 0; row < height; row++) {
		nv12_to_rgb_row(nv12 + (size_t)row * width,
				uv + (size_t)(row / 2) * width, rgb, width);
		fwrite(rgb, 1, (size_t)width * 3, f);
	}
	bfree(rgb);

	fclose(f);
	blog(LOG_INFO, "[lenslink] wrote %ux%u snapshot to %s", width, height,
	     path);
}
