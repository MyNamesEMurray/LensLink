#pragma once

#include <obs-module.h>
#include <stdint.h>
#include <stdbool.h>

#include <libavcodec/avcodec.h>

struct h264_decoder;

/*
 * codec_id: AV_CODEC_ID_H264 or AV_CODEC_ID_HEVC.
 * allow_hw: try GPU decoding (D3D11VA/DXVA2/VideoToolbox/VAAPI/VDPAU),
 * silently falling back to software when unavailable.
 * hw_start: index into the platform's hardware-API priority list to start
 * from (0 = best). A caller that watched hardware API N fail on the live
 * stream recreates with hw_start = N + 1 to try the next one — a decoder
 * that *initializes* is no proof it can decode this stream (a driver can
 * accept the codec yet reject the stream, erroring or emitting nothing).
 * Past the end of the list, the decoder is software.
 */
struct h264_decoder *h264_decoder_create(enum AVCodecID codec_id,
					 bool allow_hw, int hw_start);

/*
 * GPU pipeline: route decoded frames to `sink` as AVFrames instead of
 * downloading and pushing them via obs_source_output_video. Hardware
 * frames arrive still on the GPU; software-decoded frames pass through
 * unchanged (the sink uploads them itself). The sink OWNS each frame
 * (av_frame_free when done) and is called on the decode thread.
 *
 * Set immediately after create, before the first decode: on macOS it
 * also switches the VideoToolbox surface pool to BGRA (chosen in the
 * first get_format callback) so frames map to a single OBS texture.
 */
void h264_decoder_set_frame_sink(struct h264_decoder *dec,
				 void (*sink)(void *ud, struct AVFrame *frame),
				 void *ud);

/* Whether this instance actually decodes on the GPU. */
bool h264_decoder_is_hw(const struct h264_decoder *dec);

/* Which hardware-API priority slot this instance uses (-1 = software);
 * feed slot + 1 back into h264_decoder_create's hw_start to advance. */
int h264_decoder_hw_index(const struct h264_decoder *dec);

/* Human-readable name of the hardware API in use ("d3d11va", …), or
 * "software". */
const char *h264_decoder_hw_name(const struct h264_decoder *dec);
void h264_decoder_destroy(struct h264_decoder *dec);

/*
 * Decodes one Annex B access unit and pushes any resulting frames to the
 * source via obs_source_output_video(). Returns false on a hard decoder
 * error (caller should recreate the decoder and wait for a keyframe).
 */
bool h264_decoder_decode(struct h264_decoder *dec, obs_source_t *source,
			 const uint8_t *data, size_t size, uint64_t pts_ns);

/* Diagnostics: total frames pushed to OBS over this decoder's lifetime.
 * A keyframe going in but this staying at 0 means decode is silently
 * producing nothing (e.g. a GPU path that dislikes the stream). */
uint64_t h264_decoder_frames_output(const struct h264_decoder *dec);

/* Diagnostics: dimensions and pixel-format name of the most recently
 * decoded frame (all outputs are optional). Returns false if no frame has
 * been decoded yet. */
/* A tiny luma thumbnail of the last decoded frame, kept so the source can
 * draw a paused still without holding on to a full frame (or copying one
 * per frame). Sampled sparsely — a few thousand reads whatever the
 * resolution — and upscaled back to frame size when needed, which is
 * where the blur comes from. */
#define LENSLINK_THUMB_W 64
#define LENSLINK_THUMB_H 36

/* Copies LENSLINK_THUMB_W * LENSLINK_THUMB_H bytes into dst. False when
 * nothing has been decoded yet, or the frames never reached system
 * memory (the GPU pipeline keeps them in textures). */
bool h264_decoder_thumbnail(const struct h264_decoder *dec, uint8_t *dst);

/* Presentation time of the last frame handed to OBS, for anything that
 * needs to place a frame after it on the same timeline. */
uint64_t h264_decoder_last_pts(const struct h264_decoder *dec);

bool h264_decoder_last_frame(const struct h264_decoder *dec, int *width,
			     int *height, const char **format_name);
