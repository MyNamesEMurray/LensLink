/*
 * Virtual-camera sink: where decoded frames leave the bridge and become
 * a camera the operating system offers to Teams, Zoom and friends.
 *
 * One backend is compiled in per platform. The pump in main.c is
 * backend-agnostic — it reads the newest frame from the frame queue and
 * submits it here — so adding a backend never touches the pipeline.
 *
 * Backends today:
 *   directshow  Windows. Publishes frames into shared memory, where
 *               lenslink-vcam.dll picks them up inside the app that
 *               opened the camera (Zoom, Discord, anything 32-bit).
 *   null        elsewhere. Counts frames and can write a snapshot; it
 *               is what the Linux CI build exercises and what proves
 *               the receive/decode path end to end.
 *
 * Planned (docs/DRIVERLESS.md): a Media Foundation virtual camera for
 * Teams, the Windows Camera app and Chromium. It will read the same
 * shared memory, which is why the scaling and format negotiation live
 * in vcam-shm.c rather than in the DirectShow code.
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
 * Whether an app currently has the camera open. This is the honest
 * driverless substitute for the plugin's tally light: there is no scene
 * graph out here, so "someone is watching" is the strongest true
 * statement available (docs/DRIVERLESS.md).
 */
bool vcam_consumer_attached(struct vcam_sink *sink);

/*
 * Writes the next submitted frame to `path` as a binary PPM. A
 * verification hook, not a feature: it is the one way to confirm from a
 * headless build that real pixels came off the phone. Pass NULL to
 * cancel a pending request.
 */
void vcam_request_snapshot(struct vcam_sink *sink, const char *path);

/* Implemented once in vcam-ppm.c for every backend. */
void vcam_write_ppm(const char *path, const uint8_t *nv12, uint32_t width,
		    uint32_t height);
