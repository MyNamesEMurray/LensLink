/*
 * The slice of <obs-module.h> the reused plugin sources need, so they
 * compile into the standalone bridge unmodified.
 *
 * Keeping the plugin sources byte-identical between the two builds is
 * the point: the bridge cannot drift from — or regress — the OBS
 * plugin's transport, discovery and decode behaviour, because it is
 * literally the same code. Anything here that grows a real
 * implementation lives in obs-shim.c.
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include <util/bmem.h>
#include <util/platform.h>
#include <media-io/video-io.h>

enum obs_log_level {
	LOG_ERROR = 100,
	LOG_WARNING = 200,
	LOG_INFO = 300,
	LOG_DEBUG = 400,
};

/*
 * The bridge's logger. Writes to stderr and, when a log file is opened
 * (lenslink_log_open), to that too — the tray build has no console, so
 * the file is the only record a user can send with a bug report.
 */
void blog(int log_level, const char *format, ...)
#ifdef __GNUC__
	__attribute__((format(printf, 2, 3)))
#endif
	;

/* Opaque: the bridge never creates one. Present so the reused
 * declarations that mention it still type-check. */
typedef struct obs_source obs_source_t;

struct obs_source_frame {
	uint8_t *data[MAX_AV_PLANES];
	uint32_t linesize[MAX_AV_PLANES];
	uint32_t width;
	uint32_t height;
	uint64_t timestamp;

	enum video_format format;
	float color_matrix[16];
	bool full_range;
	uint8_t trc;
	float color_range_min[3];
	float color_range_max[3];
	bool flip;
	uint8_t flags;
	uint8_t mask_shift;
};

/* Unreachable in the bridge (a frame sink is always installed); defined
 * in obs-shim.c so the dead branch links. */
void obs_source_output_video(obs_source_t *source,
			     const struct obs_source_frame *frame);
