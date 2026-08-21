/*
 * The hand-off between the decode thread and a virtual-camera sink.
 *
 * Backpressure follows the plugin's rule from docs/PERFORMANCE.md:
 * drop, don't queue. A consumer that reads slower than the phone sends
 * (a paused meeting window, a stalled app) must never grow a backlog
 * that turns into latency — it gets the newest frame or nothing.
 *
 * One writer (the decode thread), many readers (each attached sink).
 * Readers never block the writer.
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

struct frame_queue;

struct frame_queue *frame_queue_create(void);
void frame_queue_destroy(struct frame_queue *q);

/*
 * Publishes one NV12 frame, copied in. Dimensions may change between
 * calls (a set_format mid-stream); the buffer grows to fit and readers
 * see the new size atomically with the new pixels.
 */
void frame_queue_publish(struct frame_queue *q, const uint8_t *y,
			 size_t y_stride, const uint8_t *uv, size_t uv_stride,
			 uint32_t width, uint32_t height, uint64_t pts_ns);

/*
 * Copies the most recent frame out, tightly packed (stride == width).
 * `dst` must hold width*height*3/2 bytes; pass NULL to query the
 * current size only. Returns false when no frame has been published, or
 * when the caller's buffer is too small (the out params still carry the
 * real dimensions so the caller can resize and retry).
 *
 * `last_seq` is the sequence number the caller last saw; pass 0 the
 * first time. On return it carries the sequence of the frame copied,
 * so a caller can tell a fresh frame from a repeat of the same one.
 */
bool frame_queue_read(struct frame_queue *q, uint8_t *dst, size_t dst_size,
		      uint32_t *width, uint32_t *height, uint64_t *pts_ns,
		      uint64_t *last_seq);

/* Frames published and frames dropped for want of a reader — the
 * numbers the status readout and /api/state report. */
void frame_queue_stats(struct frame_queue *q, uint64_t *published,
		       uint64_t *overwritten);
