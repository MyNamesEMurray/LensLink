/*
 * libobs video-format types, shimmed for the standalone bridge.
 *
 * h264-decoder.c can hand decoded frames to OBS *or* to a frame sink
 * (h264_decoder_set_frame_sink). The bridge always installs a sink, so
 * the obs_source_output_video branch is dead code here — but it still
 * has to compile, which is what these declarations are for. Enum
 * values mirror libobs so a misread here would be visible rather than
 * silently wrong.
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>

#define MAX_AV_PLANES 8

enum video_format {
	VIDEO_FORMAT_NONE,
	VIDEO_FORMAT_I420,
	VIDEO_FORMAT_NV12,
	VIDEO_FORMAT_YVYU,
	VIDEO_FORMAT_YUY2,
	VIDEO_FORMAT_UYVY,
	VIDEO_FORMAT_RGBA,
	VIDEO_FORMAT_BGRA,
	VIDEO_FORMAT_BGRX,
	VIDEO_FORMAT_Y800,
	VIDEO_FORMAT_I444,
	VIDEO_FORMAT_BGR3,
	VIDEO_FORMAT_I422,
	VIDEO_FORMAT_I40A,
	VIDEO_FORMAT_I42A,
	VIDEO_FORMAT_YUVA,
	VIDEO_FORMAT_AYUV,
	VIDEO_FORMAT_I010,
	VIDEO_FORMAT_P010,
	VIDEO_FORMAT_I210,
	VIDEO_FORMAT_I412,
	VIDEO_FORMAT_YA2L,
	VIDEO_FORMAT_P216,
	VIDEO_FORMAT_P416,
	VIDEO_FORMAT_V210,
	VIDEO_FORMAT_R10L,
};

enum video_colorspace {
	VIDEO_CS_DEFAULT,
	VIDEO_CS_601,
	VIDEO_CS_709,
	VIDEO_CS_SRGB,
	VIDEO_CS_2100_PQ,
	VIDEO_CS_2100_HLG,
};

enum video_range_type {
	VIDEO_RANGE_DEFAULT,
	VIDEO_RANGE_PARTIAL,
	VIDEO_RANGE_FULL,
};

enum video_trc {
	VIDEO_TRC_DEFAULT,
	VIDEO_TRC_SRGB,
	VIDEO_TRC_PQ,
	VIDEO_TRC_HLG,
};

bool video_format_get_parameters_for_format(enum video_colorspace color_space,
					    enum video_range_type range,
					    enum video_format format,
					    float matrix[16], float min_range[3],
					    float max_range[3]);
