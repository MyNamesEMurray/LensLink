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
};

bool lenslink_ctl_parse(const char *json, size_t len,
			struct lenslink_ctl_state *out);

#ifdef __cplusplus
}
#endif
