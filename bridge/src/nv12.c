#include <obs-module.h>

#include <libavutil/avutil.h>
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
#include <libavutil/pixdesc.h>
#include <libavutil/hwcontext.h>

#include <string.h>

#include "nv12.h"
#include "frame-queue.h"

struct nv12_converter {
	AVFrame *sw_frame;   /* GPU download target, reused */
	uint8_t *scratch;    /* interleaved chroma staging */
	size_t scratch_size;
	int warned_format;   /* one-shot per pixel format */
};

struct nv12_converter *nv12_converter_create(void)
{
	struct nv12_converter *conv = bzalloc(sizeof(*conv));
	conv->sw_frame = av_frame_alloc();
	conv->warned_format = AV_PIX_FMT_NONE;
	if (!conv->sw_frame) {
		bfree(conv);
		return NULL;
	}
	return conv;
}

void nv12_converter_destroy(struct nv12_converter *conv)
{
	if (!conv)
		return;
	av_frame_free(&conv->sw_frame);
	bfree(conv->scratch);
	bfree(conv);
}

static uint8_t *scratch_get(struct nv12_converter *conv, size_t size)
{
	if (size > conv->scratch_size) {
		bfree(conv->scratch);
		conv->scratch = bmalloc(size);
		conv->scratch_size = size;
	}
	return conv->scratch;
}

/* U and V planes -> one interleaved UV plane, packed to `width`. */
static void interleave_chroma_8(uint8_t *dst, const uint8_t *u, int u_stride,
				const uint8_t *v, int v_stride, uint32_t width,
				uint32_t height)
{
	uint32_t pairs = width / 2;
	for (uint32_t row = 0; row < height / 2; row++) {
		uint8_t *out = dst + (size_t)row * width;
		const uint8_t *su = u + (size_t)row * u_stride;
		const uint8_t *sv = v + (size_t)row * v_stride;
		for (uint32_t i = 0; i < pairs; i++) {
			out[i * 2] = su[i];
			out[i * 2 + 1] = sv[i];
		}
	}
}

/* 10-bit little-endian samples -> 8-bit, dropping the low 2 bits. */
static void narrow_plane_10_to_8(uint8_t *dst, size_t dst_stride,
				 const uint8_t *src, int src_stride,
				 uint32_t width, uint32_t height)
{
	for (uint32_t row = 0; row < height; row++) {
		const uint16_t *in =
			(const uint16_t *)(const void *)(src +
							 (size_t)row *
								 src_stride);
		uint8_t *out = dst + (size_t)row * dst_stride;
		for (uint32_t x = 0; x < width; x++)
			out[x] = (uint8_t)(in[x] >> 2);
	}
}

static void interleave_chroma_10(uint8_t *dst, const uint8_t *u, int u_stride,
				 const uint8_t *v, int v_stride, uint32_t width,
				 uint32_t height)
{
	uint32_t pairs = width / 2;
	for (uint32_t row = 0; row < height / 2; row++) {
		uint8_t *out = dst + (size_t)row * width;
		const uint16_t *su =
			(const uint16_t *)(const void *)(u + (size_t)row *
								     u_stride);
		const uint16_t *sv =
			(const uint16_t *)(const void *)(v + (size_t)row *
								     v_stride);
		for (uint32_t i = 0; i < pairs; i++) {
			out[i * 2] = (uint8_t)(su[i] >> 2);
			out[i * 2 + 1] = (uint8_t)(sv[i] >> 2);
		}
	}
}

static bool publish(struct nv12_converter *conv, const AVFrame *f,
		    struct frame_queue *q)
{
	uint32_t width = (uint32_t)f->width;
	uint32_t height = (uint32_t)f->height;

	/* Odd dimensions have no valid NV12 representation (chroma is
	 * exactly half in both axes); the encoder never produces them. */
	if (width < 2 || height < 2 || (width & 1) || (height & 1))
		return false;

	size_t y_size = (size_t)width * height;
	size_t uv_size = y_size / 2;

	switch (f->format) {
	case AV_PIX_FMT_NV12: {
		/* Already NV12 — the common case for GPU decode. */
		frame_queue_publish(q, f->data[0], (size_t)f->linesize[0],
				    f->data[1], (size_t)f->linesize[1], width,
				    height, (uint64_t)f->pts);
		return true;
	}
	case AV_PIX_FMT_YUV420P:
	case AV_PIX_FMT_YUVJ420P: {
		uint8_t *uv = scratch_get(conv, uv_size);
		interleave_chroma_8(uv, f->data[1], f->linesize[1], f->data[2],
				    f->linesize[2], width, height);
		frame_queue_publish(q, f->data[0], (size_t)f->linesize[0], uv,
				    width, width, height, (uint64_t)f->pts);
		return true;
	}
	case AV_PIX_FMT_P010: {
		/* Y and UV are already in NV12 layout, just 16 bits wide. */
		uint8_t *buf = scratch_get(conv, y_size + uv_size);
		narrow_plane_10_to_8(buf, width, f->data[0], f->linesize[0],
				     width, height);
		narrow_plane_10_to_8(buf + y_size, width, f->data[1],
				     f->linesize[1], width, height / 2);
		frame_queue_publish(q, buf, width, buf + y_size, width, width,
				    height, (uint64_t)f->pts);
		return true;
	}
	case AV_PIX_FMT_YUV420P10: {
		uint8_t *buf = scratch_get(conv, y_size + uv_size);
		narrow_plane_10_to_8(buf, width, f->data[0], f->linesize[0],
				     width, height);
		interleave_chroma_10(buf + y_size, f->data[1], f->linesize[1],
				     f->data[2], f->linesize[2], width, height);
		frame_queue_publish(q, buf, width, buf + y_size, width, width,
				    height, (uint64_t)f->pts);
		return true;
	}
	default:
		return false;
	}
}

bool nv12_publish_frame(struct nv12_converter *conv, AVFrame *frame,
			struct frame_queue *q)
{
	if (!conv || !frame || !q)
		return false;

	const AVFrame *src = frame;

	/* GPU-decoded frames live in GPU memory. Download, then convert:
	 * a virtual camera hands the meeting app system memory either way,
	 * so unlike the OBS GPU pipeline there is nothing to keep on the
	 * card. See docs/DRIVERLESS.md. */
	if (frame->hw_frames_ctx) {
		av_frame_unref(conv->sw_frame);
		int ret = av_hwframe_transfer_data(conv->sw_frame, frame, 0);
		if (ret < 0) {
			blog(LOG_WARNING,
			     "[lenslink] GPU frame download failed");
			return false;
		}
		av_frame_copy_props(conv->sw_frame, frame);
		src = conv->sw_frame;
	}

	if (publish(conv, src, q))
		return true;

	if (conv->warned_format != src->format) {
		conv->warned_format = src->format;
		const char *name = av_get_pix_fmt_name(src->format);
		blog(LOG_WARNING,
		     "[lenslink] cannot convert pixel format %s (%dx%d) to NV12",
		     name ? name : "?", src->width, src->height);
	}
	return false;
}
