#pragma once

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LL_CTL_LIST 8
#define LL_CTL_STR 48

struct lenslink_ctl_state {
	bool valid;
	bool paused;
	double zoom;
	double max_zoom;
	char lens[LL_CTL_STR];
	char lenses[LL_CTL_LIST][LL_CTL_STR];
	int lens_count;
	bool has_flashlight;
	bool flashlight;
	char stabilization[16];
	bool supports_reframe;
	bool supports_reframe_hq;
	bool reframe_hq;
	double reframe_zoom;
	double reframe_x;
	double reframe_y;
	bool supports_green_screen;
	bool green_screen;
	char resolution[8];
	int fps;
	char codec[8];
	char resolutions[LL_CTL_LIST][LL_CTL_STR];
	int resolution_count;
	int frame_rates[LL_CTL_LIST];
	int frame_rate_count;
	char codecs[LL_CTL_LIST][LL_CTL_STR];
	int codec_count;

	/* Exposure, white balance and focus (docs/PROTOCOL.md §8). */
	double exposure_bias;
	bool supports_manual_exposure;
	bool iso_manual;
	bool shutter_manual;
	double iso, min_iso, max_iso;
	double shutter, min_shutter, max_shutter; /* seconds */
	bool supports_wb_lock;
	bool wb_locked;
	double wb_temperature, wb_tint;
	bool focus_locked;
	double lens_position;

	/* Colour pipeline: "sdr", "hlg" or "log", and what the phone offers. */
	char color[8];
	char colors[LL_CTL_LIST][LL_CTL_STR];
	int color_count;

	/* Monitoring tools drawn on the phone (the STATE "monitor" object). */
	bool has_monitor;
	bool zebra;
	int zebra_level;
	bool peaking;
	bool false_color;
	char guide[8];
};

bool lenslink_ctl_parse(const char *json, size_t len,
			struct lenslink_ctl_state *out);

#ifdef __cplusplus
}
#endif
