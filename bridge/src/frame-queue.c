#include <obs-module.h>
#include <util/threading.h>

#include <string.h>
#include <stdlib.h>

#include "frame-queue.h"

/*
 * A single slot under a mutex, not a ring: the contract is "newest frame
 * wins", so a deeper buffer would only ever add latency. The mutex is
 * held for one memcpy of a decoded frame (~3 MB at 1080p, tens of
 * microseconds) and readers are the only contenders.
 */
struct frame_queue {
	pthread_mutex_t mutex;
	uint8_t *data; /* packed NV12 */
	size_t capacity;
	size_t size;
	uint32_t width;
	uint32_t height;
	uint64_t pts_ns;
	uint64_t seq;
	uint64_t published;
	uint64_t overwritten; /* published over a frame nobody read */
	bool unread;
};

struct frame_queue *frame_queue_create(void)
{
	struct frame_queue *q = bzalloc(sizeof(*q));
	pthread_mutex_init(&q->mutex, NULL);
	return q;
}

void frame_queue_destroy(struct frame_queue *q)
{
	if (!q)
		return;
	pthread_mutex_destroy(&q->mutex);
	bfree(q->data);
	bfree(q);
}

void frame_queue_publish(struct frame_queue *q, const uint8_t *y,
			 size_t y_stride, const uint8_t *uv, size_t uv_stride,
			 uint32_t width, uint32_t height, uint64_t pts_ns)
{
	if (!q || !y || !uv || !width || !height)
		return;

	/* NV12: a full-resolution Y plane then a half-height interleaved
	 * chroma plane, both packed to `width`. */
	size_t y_size = (size_t)width * height;
	size_t needed = y_size + y_size / 2;

	pthread_mutex_lock(&q->mutex);

	if (needed > q->capacity) {
		bfree(q->data);
		q->data = bmalloc(needed);
		q->capacity = needed;
	}

	for (uint32_t row = 0; row < height; row++)
		memcpy(q->data + (size_t)row * width, y + (size_t)row * y_stride,
		       width);

	uint8_t *dst_uv = q->data + y_size;
	for (uint32_t row = 0; row < height / 2; row++)
		memcpy(dst_uv + (size_t)row * width,
		       uv + (size_t)row * uv_stride, width);

	q->size = needed;
	q->width = width;
	q->height = height;
	q->pts_ns = pts_ns;
	q->seq++;
	q->published++;
	if (q->unread)
		q->overwritten++;
	q->unread = true;

	pthread_mutex_unlock(&q->mutex);
}

bool frame_queue_read(struct frame_queue *q, uint8_t *dst, size_t dst_size,
		      uint32_t *width, uint32_t *height, uint64_t *pts_ns,
		      uint64_t *last_seq)
{
	if (!q)
		return false;

	pthread_mutex_lock(&q->mutex);

	bool have = q->size > 0;
	if (width)
		*width = q->width;
	if (height)
		*height = q->height;
	if (pts_ns)
		*pts_ns = q->pts_ns;

	bool copied = false;
	if (have && dst && dst_size >= q->size) {
		memcpy(dst, q->data, q->size);
		q->unread = false;
		copied = true;
	}
	if (last_seq)
		*last_seq = q->seq;

	pthread_mutex_unlock(&q->mutex);

	return dst ? copied : have;
}

void frame_queue_stats(struct frame_queue *q, uint64_t *published,
		       uint64_t *overwritten)
{
	if (!q)
		return;
	pthread_mutex_lock(&q->mutex);
	if (published)
		*published = q->published;
	if (overwritten)
		*overwritten = q->overwritten;
	pthread_mutex_unlock(&q->mutex);
}
