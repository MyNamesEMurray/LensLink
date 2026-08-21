/*
 * The no-op virtual-camera backend: accepts frames, counts them, and
 * can write one out as a PPM.
 *
 * It is what the non-Windows builds use, and it is the reason the whole
 * receive/decode/convert path is verifiable on a CI runner with no
 * camera subsystem at all.
 */

#include <obs-module.h>
#include <util/threading.h>

#include <stdio.h>
#include <string.h>

#include "vcam.h"

struct vcam_sink {
	char name[128];
	uint64_t frames;

	pthread_mutex_t mutex;
	char snapshot_path[512]; /* empty = none pending */
};

const char *vcam_backend_name(void)
{
	return "null";
}

struct vcam_sink *vcam_create(const char *name)
{
	struct vcam_sink *sink = bzalloc(sizeof(*sink));
	snprintf(sink->name, sizeof(sink->name), "%s", name ? name : "LensLink");
	pthread_mutex_init(&sink->mutex, NULL);
	blog(LOG_INFO,
	     "[lenslink] virtual camera backend 'null' — frames are decoded "
	     "and counted but not published to the system");
	return sink;
}

void vcam_destroy(struct vcam_sink *sink)
{
	if (!sink)
		return;
	pthread_mutex_destroy(&sink->mutex);
	bfree(sink);
}

void vcam_request_snapshot(struct vcam_sink *sink, const char *path)
{
	if (!sink)
		return;
	pthread_mutex_lock(&sink->mutex);
	snprintf(sink->snapshot_path, sizeof(sink->snapshot_path), "%s",
		 path ? path : "");
	pthread_mutex_unlock(&sink->mutex);
}

/* BT.601 limited-range YCbCr -> RGB, enough for an eyeball check. */
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

static void write_ppm(const char *path, const uint8_t *nv12, uint32_t width,
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

bool vcam_submit(struct vcam_sink *sink, const uint8_t *nv12, uint32_t width,
		 uint32_t height, uint64_t pts_ns)
{
	(void)pts_ns;
	if (!sink)
		return false;

	sink->frames++;

	char path[512];
	pthread_mutex_lock(&sink->mutex);
	snprintf(path, sizeof(path), "%s", sink->snapshot_path);
	sink->snapshot_path[0] = 0;
	pthread_mutex_unlock(&sink->mutex);

	if (path[0])
		write_ppm(path, nv12, width, height);

	return true;
}
