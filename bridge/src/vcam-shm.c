/*
 * The Windows virtual-camera backend: publish frames where the filter
 * DLL can find them.
 *
 * The bridge does not talk to Windows' camera stack at all. It cannot:
 * a DirectShow filter is loaded into the *consuming* app's process, so
 * Zoom instantiates lenslink-vcam.dll inside Zoom. This backend's whole
 * job is to put the newest frame in shared memory, at the size the
 * filter's pin negotiated, and to report whether anyone is watching.
 *
 * The same mapping will serve the Media Foundation backend, which is
 * why the scaling and the format negotiation live here rather than in
 * the DirectShow code.
 */

#include <obs-module.h>
#include <util/threading.h>

#include <stdio.h>
#include <string.h>

#include "vcam.h"
#include "frame-shm.h"
#include "nv12-scale.h"

/* What the filter advertises when it has never been asked for anything
 * else. Matches the first entry of the pin's media-type list. */
#define DEFAULT_WIDTH 1280u
#define DEFAULT_HEIGHT 720u

struct vcam_sink {
	char name[128];
	struct llshm *shm;

	uint8_t *scaled; /* scratch for the letterbox path */
	size_t scaled_size;
	uint32_t out_width;
	uint32_t out_height;

	bool logged_reader;
	bool warned_no_shm;

	pthread_mutex_t mutex;
	char snapshot_path[512];
};

const char *vcam_backend_name(void)
{
	return "directshow";
}

struct vcam_sink *vcam_create(const char *name)
{
	struct vcam_sink *sink = bzalloc(sizeof(*sink));
	snprintf(sink->name, sizeof(sink->name), "%s",
		 name ? name : "LensLink");
	pthread_mutex_init(&sink->mutex, NULL);

	sink->shm = llshm_open_write();
	if (!sink->shm) {
		blog(LOG_ERROR,
		     "[lenslink] could not create the shared frame buffer — "
		     "the virtual camera will show no signal");
	} else {
		blog(LOG_INFO,
		     "[lenslink] virtual camera ready; select \"%s\" in "
		     "Zoom, Teams or any other app",
		     sink->name);
	}
	return sink;
}

void vcam_destroy(struct vcam_sink *sink)
{
	if (!sink)
		return;
	llshm_close(sink->shm);
	pthread_mutex_destroy(&sink->mutex);
	bfree(sink->scaled);
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

bool vcam_consumer_attached(struct vcam_sink *sink)
{
	return sink && llshm_reader_present(sink->shm);
}

/* Whatever the filter last negotiated, clamped to what the mapping can
 * hold. Zero from the filter means nothing has connected yet, in which
 * case the phone's own size is used — so the first app to open the
 * camera sees the real stream rather than a scaled guess. */
static void resolve_output_size(struct vcam_sink *sink, uint32_t src_w,
				uint32_t src_h, uint32_t *out_w,
				uint32_t *out_h)
{
	uint32_t want_w = 0, want_h = 0, want_fps = 0;
	llshm_get_wanted_format(sink->shm, &want_w, &want_h, &want_fps);

	if (!want_w || !want_h) {
		want_w = src_w;
		want_h = src_h;
	}
	if (want_w > LLSHM_MAX_WIDTH || want_h > LLSHM_MAX_HEIGHT) {
		want_w = DEFAULT_WIDTH;
		want_h = DEFAULT_HEIGHT;
	}

	*out_w = want_w & ~1u;
	*out_h = want_h & ~1u;
}

bool vcam_submit(struct vcam_sink *sink, const uint8_t *nv12, uint32_t width,
		 uint32_t height, uint64_t pts_ns)
{
	if (!sink || !nv12)
		return false;

	if (!sink->shm) {
		if (!sink->warned_no_shm) {
			sink->warned_no_shm = true;
			blog(LOG_WARNING,
			     "[lenslink] frames are being decoded but there "
			     "is nowhere to publish them");
		}
		return true; /* keep the pipeline running; the log said why */
	}

	bool reader = llshm_reader_present(sink->shm);
	if (reader != sink->logged_reader) {
		sink->logged_reader = reader;
		blog(LOG_INFO, "[lenslink] virtual camera %s",
		     reader ? "opened by an app" : "no longer in use");
	}

	uint32_t out_w = 0, out_h = 0;
	resolve_output_size(sink, width, height, &out_w, &out_h);
	if (!out_w || !out_h)
		return true;

	const uint8_t *publish = nv12;
	if (out_w != width || out_h != height) {
		size_t needed = (size_t)out_w * out_h * 3 / 2;
		if (needed > sink->scaled_size) {
			bfree(sink->scaled);
			sink->scaled = bmalloc(needed);
			sink->scaled_size = needed;
		}
		nv12_scale_letterbox(sink->scaled, out_w, out_h, nv12, width,
				     height);
		publish = sink->scaled;

		if (out_w != sink->out_width || out_h != sink->out_height)
			blog(LOG_INFO,
			     "[lenslink] scaling %ux%u to the camera's %ux%u",
			     width, height, out_w, out_h);
	}
	sink->out_width = out_w;
	sink->out_height = out_h;

	llshm_publish(sink->shm, publish, out_w, out_h, pts_ns);

	char path[512];
	pthread_mutex_lock(&sink->mutex);
	snprintf(path, sizeof(path), "%s", sink->snapshot_path);
	sink->snapshot_path[0] = 0;
	pthread_mutex_unlock(&sink->mutex);

	if (path[0])
		vcam_write_ppm(path, publish, out_w, out_h);

	return true;
}
