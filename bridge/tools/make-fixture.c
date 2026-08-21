/*
 * Regenerates tools/testdata/pattern.h264, the fixture fake-phone.py
 * streams at the bridge.
 *
 * Not part of the build and not needed to run the tests — the fixture is
 * checked in. It exists so the fixture is reproducible rather than a
 * mystery blob:
 *
 *   cc make-fixture.c -o make-fixture $(pkg-config --cflags --libs \
 *       libavcodec libavutil) && ./make-fixture testdata/pattern.h264
 *
 * Needs a distro FFmpeg with libx264. The decode-only static FFmpeg the
 * bridge itself links cannot build this, which is the whole reason the
 * output is committed.
 *
 * Annex B with parameter sets repeated on every keyframe, matching what
 * the iOS app sends (docs/PROTOCOL.md: keyframes must be
 * self-contained so a decoder can join mid-stream).
 */

#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WIDTH 320
#define HEIGHT 240
#define FRAMES 30

int main(int argc, char **argv)
{
	const char *out_path = argc > 1 ? argv[1] : "pattern.h264";

	const AVCodec *codec = avcodec_find_encoder_by_name("libx264");
	if (!codec) {
		fprintf(stderr, "libx264 encoder not available\n");
		return 1;
	}

	AVCodecContext *ctx = avcodec_alloc_context3(codec);
	ctx->width = WIDTH;
	ctx->height = HEIGHT;
	ctx->pix_fmt = AV_PIX_FMT_YUV420P;
	ctx->time_base = (AVRational){1, 30};
	ctx->framerate = (AVRational){30, 1};
	ctx->gop_size = 10;
	ctx->max_b_frames = 0;
	/* One slice per frame keeps access-unit splitting in
	 * fake-phone.py trivial: a new AU starts at each VCL NAL. */
	ctx->thread_count = 1;
	ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
	av_opt_set(ctx->priv_data, "preset", "ultrafast", 0);
	av_opt_set(ctx->priv_data, "tune", "zerolatency", 0);
	/* Repeat SPS/PPS before every keyframe, like the app does. */
	av_opt_set(ctx->priv_data, "x264-params", "repeat-headers=1:sliced-threads=0:slices=1", 0);

	if (avcodec_open2(ctx, codec, NULL) < 0) {
		fprintf(stderr, "avcodec_open2 failed\n");
		return 1;
	}

	AVFrame *frame = av_frame_alloc();
	frame->format = ctx->pix_fmt;
	frame->width = ctx->width;
	frame->height = ctx->height;
	av_frame_get_buffer(frame, 0);

	AVPacket *pkt = av_packet_alloc();
	FILE *out = fopen(out_path, "wb");
	if (!out) {
		fprintf(stderr, "cannot write %s\n", out_path);
		return 1;
	}

	for (int i = 0; i < FRAMES; i++) {
		av_frame_make_writable(frame);
		/* A moving diagonal ramp: every frame differs, so a decoder
		 * that silently repeats one frame is visible in the PPM. */
		for (int y = 0; y < HEIGHT; y++)
			for (int x = 0; x < WIDTH; x++)
				frame->data[0][y * frame->linesize[0] + x] =
					(uint8_t)(x + y + i * 8);
		for (int y = 0; y < HEIGHT / 2; y++)
			for (int x = 0; x < WIDTH / 2; x++) {
				frame->data[1][y * frame->linesize[1] + x] =
					(uint8_t)(128 + i * 3);
				frame->data[2][y * frame->linesize[2] + x] =
					(uint8_t)(128 - i * 3);
			}
		frame->pts = i;

		if (avcodec_send_frame(ctx, frame) < 0)
			break;
		while (avcodec_receive_packet(ctx, pkt) == 0) {
			fwrite(pkt->data, 1, (size_t)pkt->size, out);
			av_packet_unref(pkt);
		}
	}

	avcodec_send_frame(ctx, NULL);
	while (avcodec_receive_packet(ctx, pkt) == 0) {
		fwrite(pkt->data, 1, (size_t)pkt->size, out);
		av_packet_unref(pkt);
	}

	fclose(out);
	av_packet_free(&pkt);
	av_frame_free(&frame);
	avcodec_free_context(&ctx);
	printf("wrote %s\n", out_path);
	return 0;
}
