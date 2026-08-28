/*
 * NV12 scaling with letterboxing, for the virtual camera.
 *
 * A DirectShow or Media Foundation pin negotiates one fixed frame size
 * up front and the app expects exactly that size for the life of the
 * connection — but the phone streams whatever the user picked, and can
 * change it mid-call. Something has to reconcile the two, and doing it
 * here means one scaler in one place rather than one per backend.
 *
 * Aspect ratio is preserved and the remainder filled with black bars: a
 * stretched face is worse than a letterboxed one, and a portrait phone
 * feed into a 16:9 camera would otherwise be unwatchable.
 *
 * Bilinear, and deliberately not swscale — the static FFmpeg the bridge
 * links is decode-only and has none.
 */

#pragma once

#include <stdint.h>

/*
 * Scales packed NV12 `src` (sw x sh) into packed NV12 `dst` (dw x dh),
 * centred, aspect preserved, bars filled with limited-range black.
 * All dimensions must be even and non-zero. A same-size call is a
 * straight copy, which is the common path — the phone usually streams
 * exactly what the camera advertises.
 */
void nv12_scale_letterbox(uint8_t *dst, uint32_t dw, uint32_t dh,
			  const uint8_t *src, uint32_t sw, uint32_t sh);

/* Fills a packed NV12 frame with limited-range black. */
void nv12_fill_black(uint8_t *dst, uint32_t width, uint32_t height);
