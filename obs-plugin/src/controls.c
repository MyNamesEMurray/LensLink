#include "controls.h"
#include "json-reader.h"

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

static bool clamp_num(double in, double lo, double hi, double *out)
{
	if (isnan(in))
		return false;
	*out = in < lo ? lo : in > hi ? hi : in;
	return true;
}

static int clamp_rate(double in)
{
	double v;
	return clamp_num(in, 0, 1000, &v) ? (int)v : 0;
}

static void read_strings(struct json_reader *r, char (*out)[LL_CTL_STR],
			 size_t size, int *count)
{
	*count = 0;
	if (!lenslink_json_array_begin(r)) {
		lenslink_json_skip(r);
		return;
	}
	while (lenslink_json_array_next(r)) {
		char tmp[LL_CTL_STR];
		bool truncated = false;
		if (*count < LL_CTL_LIST &&
		    lenslink_json_read_string(r, tmp, sizeof(tmp), &truncated) &&
		    !truncated) {
			snprintf(out[*count], size, "%s", tmp);
			(*count)++;
		} else {
			lenslink_json_skip(r);
		}
	}
}

static void read_reframe(struct json_reader *r, struct lenslink_ctl_state *s)
{
	char key[24];
	bool truncated;
	if (!lenslink_json_object_begin(r)) {
		lenslink_json_skip(r);
		return;
	}
	while (lenslink_json_object_next(r, key, sizeof(key), &truncated)) {
		double *target = NULL;
		double lo = 0, hi = 1, num;
		if (!truncated && !strcmp(key, "zoom")) {
			target = &s->reframe_zoom;
			lo = 1;
			hi = 4;
		} else if (!truncated && !strcmp(key, "x"))
			target = &s->reframe_x;
		else if (!truncated && !strcmp(key, "y"))
			target = &s->reframe_y;
		if (!target || !lenslink_json_read_number(r, &num))
			lenslink_json_skip(r);
		else
			clamp_num(num, lo, hi, target);
	}
}

static void read_str(struct json_reader *r, char *out, size_t size);

static void read_monitor(struct json_reader *r, struct lenslink_ctl_state *s)
{
	char key[24];
	bool truncated;
	if (!lenslink_json_object_begin(r)) {
		lenslink_json_skip(r);
		return;
	}
	s->has_monitor = true;
	while (lenslink_json_object_next(r, key, sizeof(key), &truncated)) {
		if (!truncated && !strcmp(key, "guide"))
			read_str(r, s->guide, sizeof(s->guide));
		else
			lenslink_json_skip(r);
	}
}

static void read_str(struct json_reader *r, char *out, size_t size)
{
	bool truncated = false;
	if (!lenslink_json_read_string(r, out, size, &truncated) || truncated)
		out[0] = 0;
}

bool lenslink_ctl_parse(const char *json, size_t len,
			struct lenslink_ctl_state *s)
{
	memset(s, 0, sizeof(*s));
	s->max_zoom = 1;
	s->zoom = 1;
	s->reframe_zoom = 1;
	s->reframe_x = 0.5;
	s->reframe_y = 0.5;
	s->lens_position = 0.5;
	s->wb_temperature = 5000;
	snprintf(s->color, sizeof(s->color), "sdr");
	snprintf(s->guide, sizeof(s->guide), "off");

	/* Apps before isoMode/shutterMode report one exposureMode for both. */
	char mode[16];
	bool exposure_manual = false, split_modes = false;

	struct json_reader r;
	lenslink_json_reader_init(&r, json, len);
	if (!lenslink_json_object_begin(&r))
		return false;

	char key[32];
	bool truncated;
	while (lenslink_json_object_next(&r, key, sizeof(key), &truncated)) {
		double num;
		bool flag;
		if (truncated) {
			lenslink_json_skip(&r);
		} else if (!strcmp(key, "zoom")) {
			if (lenslink_json_read_number(&r, &num))
				clamp_num(num, 1, 1e9, &s->zoom);
			else
				lenslink_json_skip(&r);
		} else if (!strcmp(key, "maxZoom")) {
			if (lenslink_json_read_number(&r, &num))
				clamp_num(num, 1, 20, &s->max_zoom);
			else
				lenslink_json_skip(&r);
		} else if (!strcmp(key, "fps")) {
			if (lenslink_json_read_number(&r, &num))
				s->fps = clamp_rate(num);
			else
				lenslink_json_skip(&r);
		} else if (!strcmp(key, "lens")) {
			read_str(&r, s->lens, sizeof(s->lens));
		} else if (!strcmp(key, "lenses")) {
			read_strings(&r, s->lenses, LL_CTL_STR, &s->lens_count);
		} else if (!strcmp(key, "stabilization")) {
			read_str(&r, s->stabilization, sizeof(s->stabilization));
		} else if (!strcmp(key, "resolution")) {
			read_str(&r, s->resolution, sizeof(s->resolution));
		} else if (!strcmp(key, "codec")) {
			read_str(&r, s->codec, sizeof(s->codec));
		} else if (!strcmp(key, "resolutions")) {
			read_strings(&r, s->resolutions, LL_CTL_STR,
				     &s->resolution_count);
		} else if (!strcmp(key, "codecs")) {
			read_strings(&r, s->codecs, LL_CTL_STR, &s->codec_count);
		} else if (!strcmp(key, "frameRates")) {
			if (lenslink_json_array_begin(&r)) {
				while (lenslink_json_array_next(&r)) {
					if (s->frame_rate_count < LL_CTL_LIST &&
					    lenslink_json_read_number(&r, &num))
						s->frame_rates[s->frame_rate_count++] =
							clamp_rate(num);
					else
						lenslink_json_skip(&r);
				}
			} else {
				lenslink_json_skip(&r);
			}
		} else if (!strcmp(key, "reframe")) {
			read_reframe(&r, s);
		} else if (!strcmp(key, "monitor")) {
			read_monitor(&r, s);
		} else if (!strcmp(key, "colors")) {
			read_strings(&r, s->colors, LL_CTL_STR, &s->color_count);
		} else if (!strcmp(key, "color")) {
			read_str(&r, s->color, sizeof(s->color));
			if (!s->color[0])
				snprintf(s->color, sizeof(s->color), "sdr");
		} else if (!strcmp(key, "hdr")) {
			if (lenslink_json_read_bool(&r, &flag) && flag)
				snprintf(s->color, sizeof(s->color), "hlg");
		} else if (!strcmp(key, "exposureMode") ||
			   !strcmp(key, "isoMode") ||
			   !strcmp(key, "shutterMode") ||
			   !strcmp(key, "whiteBalanceMode") ||
			   !strcmp(key, "focusMode")) {
			read_str(&r, mode, sizeof(mode));
			bool manual = !strcmp(mode, "manual") ||
				      !strcmp(mode, "locked");
			if (!strcmp(key, "exposureMode")) {
				exposure_manual = manual;
			} else if (!strcmp(key, "isoMode")) {
				s->iso_manual = manual;
				split_modes = true;
			} else if (!strcmp(key, "shutterMode")) {
				s->shutter_manual = manual;
				split_modes = true;
			} else if (!strcmp(key, "whiteBalanceMode")) {
				s->wb_locked = manual;
			} else {
				s->focus_locked = manual;
			}
		} else if (!strcmp(key, "exposureBias") || !strcmp(key, "iso") ||
			   !strcmp(key, "minISO") || !strcmp(key, "maxISO") ||
			   !strcmp(key, "shutterSeconds") ||
			   !strcmp(key, "minShutterSeconds") ||
			   !strcmp(key, "maxShutterSeconds") ||
			   !strcmp(key, "whiteBalanceTemperature") ||
			   !strcmp(key, "whiteBalanceTint") ||
			   !strcmp(key, "lensPosition")) {
			static const struct {
				const char *key;
				size_t offset;
				double lo, hi;
			} nums[] = {
				{"exposureBias",
				 offsetof(struct lenslink_ctl_state, exposure_bias),
				 -8, 8},
				{"iso", offsetof(struct lenslink_ctl_state, iso), 0,
				 1e6},
				{"minISO",
				 offsetof(struct lenslink_ctl_state, min_iso), 0,
				 1e6},
				{"maxISO",
				 offsetof(struct lenslink_ctl_state, max_iso), 0,
				 1e6},
				{"shutterSeconds",
				 offsetof(struct lenslink_ctl_state, shutter), 0,
				 60},
				{"minShutterSeconds",
				 offsetof(struct lenslink_ctl_state, min_shutter),
				 0, 60},
				{"maxShutterSeconds",
				 offsetof(struct lenslink_ctl_state, max_shutter),
				 0, 60},
				{"whiteBalanceTemperature",
				 offsetof(struct lenslink_ctl_state,
					  wb_temperature),
				 1000, 20000},
				{"whiteBalanceTint",
				 offsetof(struct lenslink_ctl_state, wb_tint),
				 -150, 150},
				{"lensPosition",
				 offsetof(struct lenslink_ctl_state,
					  lens_position),
				 0, 1},
			};
			size_t i = 0;
			while (strcmp(nums[i].key, key))
				i++;
			if (lenslink_json_read_number(&r, &num))
				clamp_num(num, nums[i].lo, nums[i].hi,
					  (double *)((char *)s +
						     nums[i].offset));
			else
				lenslink_json_skip(&r);
		} else {
			bool *target = NULL;
			if (!strcmp(key, "paused"))
				target = &s->paused;
			else if (!strcmp(key, "hasFlashlight"))
				target = &s->has_flashlight;
			else if (!strcmp(key, "flashlight"))
				target = &s->flashlight;
			else if (!strcmp(key, "supportsReframe"))
				target = &s->supports_reframe;
			else if (!strcmp(key, "supportsReframeHQ"))
				target = &s->supports_reframe_hq;
			else if (!strcmp(key, "reframeHQ"))
				target = &s->reframe_hq;
			else if (!strcmp(key, "supportsGreenScreen"))
				target = &s->supports_green_screen;
			else if (!strcmp(key, "greenScreen"))
				target = &s->green_screen;
			else if (!strcmp(key, "supportsManualExposure"))
				target = &s->supports_manual_exposure;
			else if (!strcmp(key, "supportsWhiteBalanceLock"))
				target = &s->supports_wb_lock;
			if (!target || !lenslink_json_read_bool(&r, &flag))
				lenslink_json_skip(&r);
			else
				*target = flag;
		}
	}
	if (s->zoom > s->max_zoom)
		s->zoom = s->max_zoom;
	if (!split_modes)
		s->iso_manual = s->shutter_manual = exposure_manual;
	s->valid = !r.error;
	return s->valid;
}
