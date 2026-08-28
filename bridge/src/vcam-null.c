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

/* Nothing can attach to a backend that publishes nowhere. */
bool vcam_consumer_attached(struct vcam_sink *sink)
{
	(void)sink;
	return false;
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
		vcam_write_ppm(path, nv12, width, height);

	return true;
}
