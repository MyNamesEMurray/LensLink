/*
 * Decoded frame -> NV12, the pixel format every Windows virtual-camera
 * API takes without a further conversion.
 *
 * Deliberately not swscale: the static FFmpeg the bridge links is a
 * decode-only build (.github/actions/static-ffmpeg) with swscale
 * disabled, and the conversions actually needed here — plane copies,
 * a chroma interleave, a 10->8 bit shift — are a few lines each.
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

struct AVFrame;
struct frame_queue;

struct nv12_converter;

struct nv12_converter *nv12_converter_create(void);
void nv12_converter_destroy(struct nv12_converter *conv);

/*
 * Converts `frame` and publishes it to `q`. Hardware frames are
 * downloaded first. Returns false for a pixel format the converter
 * doesn't handle — logged once per format, not per frame.
 *
 * 10-bit input (P010 / YUV420P10, i.e. HLG or Apple Log streams) is
 * truncated to 8-bit NV12: a webcam feed has nowhere to put the extra
 * bits. See docs/DRIVERLESS.md for what that means for HDR streams.
 */
bool nv12_publish_frame(struct nv12_converter *conv, struct AVFrame *frame,
			struct frame_queue *q);
