/*
 * Virtual-camera sink: where decoded frames leave the bridge and become
 * a camera the operating system offers to Teams, Zoom and friends.
 *
 * One backend is compiled in per platform. The pump in main.c is
 * backend-agnostic — it reads the newest frame from the frame queue and
 * submits it here — so adding a backend never touches the pipeline.
 *
 * Backends today:
 *   null     everywhere. Counts frames and can write a snapshot; this
 *            is what the Linux CI build exercises and what --snapshot
 *            uses to prove the receive/decode path end to end.
 *
 * Planned (docs/DRIVERLESS.md): a DirectShow filter (Zoom, Discord,
 * 32-bit apps) and a Media Foundation virtual camera (Teams, the
 * Windows Camera app, Chromium).
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

struct vcam_sink;

/* `name` is what the camera is called in the OS camera list. */
struct vcam_sink *vcam_create(const char *name);
void vcam_destroy(struct vcam_sink *sink);

/*
 * Hands over one packed NV12 frame (Y plane of w*h, then interleaved UV
 * of w*h/2). The buffer is owned by the caller and valid only for the
 * call. Returns false if the backend has failed and the pump should
 * stop.
 */
bool vcam_submit(struct vcam_sink *sink, const uint8_t *nv12, uint32_t width,
		 uint32_t height, uint64_t pts_ns);

/* Short backend name for logs and the status line. */
const char *vcam_backend_name(void);

/*
 * Writes the next submitted frame to `path` as a binary PPM. A
 * verification hook, not a feature: it is the one way to confirm from a
 * headless build that real pixels came off the phone. Pass NULL to
 * cancel a pending request.
 */
void vcam_request_snapshot(struct vcam_sink *sink, const char *path);
