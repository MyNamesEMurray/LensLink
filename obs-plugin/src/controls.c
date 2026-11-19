#include "controls.h"
#include "json-reader.h"

#include <stdio.h>
#include <string.h>

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
		if (!truncated && !strcmp(key, "zoom"))
			target = &s->reframe_zoom;
		else if (!truncated && !strcmp(key, "x"))
			target = &s->reframe_x;
		else if (!truncated && !strcmp(key, "y"))
			target = &s->reframe_y;
		if (!target || !lenslink_json_read_number(r, target))
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
				s->zoom = num;
			else
				lenslink_json_skip(&r);
		} else if (!strcmp(key, "maxZoom")) {
			if (lenslink_json_read_number(&r, &num))
				s->max_zoom = num;
			else
				lenslink_json_skip(&r);
		} else if (!strcmp(key, "fps")) {
			if (lenslink_json_read_number(&r, &num))
				s->fps = (int)num;
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
							(int)num;
					else
						lenslink_json_skip(&r);
				}
			} else {
				lenslink_json_skip(&r);
			}
		} else if (!strcmp(key, "reframe")) {
			read_reframe(&r, s);
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
			if (!target || !lenslink_json_read_bool(&r, &flag))
				lenslink_json_skip(&r);
			else
				*target = flag;
		}
	}
	s->valid = !r.error;
	return s->valid;
}
