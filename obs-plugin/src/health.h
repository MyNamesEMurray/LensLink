/*
 * Per-source health snapshots for the frontend UI (status-bar readout and
 * the LensLink dock). Implemented in ios-camera-source.c; consumed by
 * frontend-ui.cpp on the Qt UI thread.
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

struct lenslink_health {
	char source_name[128]; /* the OBS source's name */
	char device[64];       /* phone name from HELLO; "" if unknown */
	char status[256];      /* the source's status line */
	bool connected;        /* a device connection is live */
	bool standby;          /* connected, camera idle (remote start) */
	bool is_screen;        /* LensLink Screen vs LensLink Camera */
	uint64_t frames;       /* decoded frames, cumulative */
	uint64_t bytes;        /* wire video bytes, cumulative */
	int latency_ms;        /* avg capture→decode; 0 until measured */

	/* Added for the diagnostics report (diagnostics.c). The dock and
	 * status bar ignore these; they exist so a bug report can say what
	 * the connection was doing rather than only that it failed. */
	char transport[16];    /* "USB" / "Wi-Fi"; "" when not dialling */
	bool gpu_pipeline;     /* this source is on the zero-copy path */
	int last_dial_error;   /* errno/WSA code of the last failed dial */

	/* Per-connection decode counters, mirrored from the server thread
	 * once a second. Their *relationship* is the diagnosis: packets
	 * climbing while frames_output sits still is a stalled decoder, and
	 * a picture that froze or went green; both stalled is a dead link. */
	uint64_t video_packets;
	uint64_t keyframes;
	uint64_t decode_errors;
	int hw_retries;        /* hardware decode fell back this many times */
	char decoder[32];      /* "VideoToolbox", "D3D11VA", "software", … */
	bool green_screen;     /* the phone is painting its background green */
};

/* Snapshots every live LensLink source (thread-safe); returns the count,
 * at most `max`. Rates (fps / Mb/s) are for the caller to derive from
 * successive cumulative snapshots. */
size_t lenslink_health_enum(struct lenslink_health *out, size_t max);

#ifdef __cplusplus
}
#endif
