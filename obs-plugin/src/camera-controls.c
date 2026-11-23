#include <obs-module.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "camera-controls.h"
#include "controls.h"
#include "web-control.h"

#define T_(s) obs_module_text(s)

#define CTL_ZOOM "ctl_zoom"
#define CTL_LENS "ctl_lens"
#define CTL_FLASH "ctl_flashlight"
#define CTL_STAB "ctl_stabilization"
#define CTL_RF_ZOOM "ctl_reframe_zoom"
#define CTL_RF_X "ctl_reframe_x"
#define CTL_RF_Y "ctl_reframe_y"
#define CTL_RF_HQ "ctl_reframe_hq"
#define CTL_GS "ctl_green_screen"
#define CTL_RES "ctl_resolution"
#define CTL_FPS "ctl_fps"
#define CTL_CODEC "ctl_codec"

#define CTL_STATE_BUF (32 * 1024 + 1)

void lenslink_camera_controls_clear(obs_data_t *settings)
{
	static const char *const keys[] = {
		CTL_ZOOM, CTL_LENS,  CTL_FLASH, CTL_STAB,  CTL_RF_ZOOM,
		CTL_RF_X, CTL_RF_Y,  CTL_RF_HQ, CTL_GS,    CTL_RES,
		CTL_FPS,  CTL_CODEC,
	};
	for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++)
		obs_data_erase(settings, keys[i]);
}

const char *lenslink_lens_text(const char *label)
{
	static const struct {
		const char *label;
		const char *key;
	} map[] = {
		{"Front", "Web.Lens.Front"},
		{"Front (Ultra Wide)", "Web.Lens.FrontUltraWide"},
		{"Main (Wide)", "Web.Lens.MainWide"},
		{"Ultra Wide (0.5×)", "Web.Lens.UltraWide"},
		{"Telephoto", "Web.Lens.Telephoto"},
	};
	for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); i++)
		if (!strcmp(label, map[i].label))
			return T_(map[i].key);
	return label;
}

static void send(struct ios_camera_source *s, const char *json)
{
	ios_camera_enqueue_control(s, json, strlen(json));
}

static bool differs(double a, double b)
{
	return fabs(a - b) > 0.02;
}

static bool ctl_modified(obs_properties_t *props, obs_property_t *property,
			 obs_data_t *settings)
{
	struct ios_camera_source *s = obs_properties_get_param(props);
	if (!s)
		return false;

	char state[CTL_STATE_BUF];
	struct lenslink_ctl_state st;
	ios_camera_copy_state(s, state, sizeof(state));
	if (!lenslink_ctl_parse(state, strlen(state), &st) ||
	    st.lens_count == 0)
		return false;

	const char *name = obs_property_name(property);
	char json[160];

	if (!strcmp(name, CTL_ZOOM)) {
		double v = obs_data_get_double(settings, CTL_ZOOM);
		if (differs(v, st.zoom)) {
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"zoom\",\"value\":%.2f}", v);
			send(s, json);
		}
	} else if (!strcmp(name, CTL_LENS)) {
		const char *label = obs_data_get_string(settings, CTL_LENS);
		if (label[0] && strcmp(label, st.lens)) {
			obs_data_t *cmd = obs_data_create();
			obs_data_set_string(cmd, "cmd", "selectLens");
			obs_data_set_string(cmd, "label", label);
			send(s, obs_data_get_json(cmd));
			obs_data_release(cmd);
		}
	} else if (!strcmp(name, CTL_FLASH)) {
		bool on = obs_data_get_bool(settings, CTL_FLASH);
		if (on != st.flashlight) {
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"flashlight\",\"on\":%s}",
				 on ? "true" : "false");
			send(s, json);
		}
	} else if (!strcmp(name, CTL_STAB)) {
		const char *mode = obs_data_get_string(settings, CTL_STAB);
		if (mode[0] && strcmp(mode, st.stabilization)) {
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"stabilization\",\"mode\":\"%s\"}",
				 mode);
			send(s, json);
		}
	} else if (!strcmp(name, CTL_RF_ZOOM) || !strcmp(name, CTL_RF_X) ||
		   !strcmp(name, CTL_RF_Y)) {
		double z = obs_data_get_double(settings, CTL_RF_ZOOM);
		double x = obs_data_get_double(settings, CTL_RF_X);
		double y = obs_data_get_double(settings, CTL_RF_Y);
		if (differs(z, st.reframe_zoom) || differs(x, st.reframe_x) ||
		    differs(y, st.reframe_y)) {
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"reframe\",\"zoom\":%.2f,\"x\":%.3f,\"y\":%.3f}",
				 z, x, y);
			send(s, json);
		}
	} else if (!strcmp(name, CTL_RF_HQ)) {
		bool on = obs_data_get_bool(settings, CTL_RF_HQ);
		if (on != st.reframe_hq) {
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"reframe\",\"hq\":%s}",
				 on ? "true" : "false");
			send(s, json);
		}
	} else if (!strcmp(name, CTL_GS)) {
		bool on = obs_data_get_bool(settings, CTL_GS);
		if (on != st.green_screen) {
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"green_screen\",\"on\":%s}",
				 on ? "true" : "false");
			send(s, json);
		}
	} else if (!strcmp(name, CTL_RES)) {
		const char *v = obs_data_get_string(settings, CTL_RES);
		if (v[0] && strcmp(v, st.resolution)) {
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"set_format\",\"resolution\":\"%s\"}",
				 v);
			send(s, json);
		}
	} else if (!strcmp(name, CTL_FPS)) {
		long long v = obs_data_get_int(settings, CTL_FPS);
		if (v > 0 && v != st.fps) {
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"set_format\",\"fps\":%lld}", v);
			send(s, json);
		}
	} else if (!strcmp(name, CTL_CODEC)) {
		const char *v = obs_data_get_string(settings, CTL_CODEC);
		if (v[0] && strcmp(v, st.codec)) {
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"set_format\",\"codec\":\"%s\"}", v);
			send(s, json);
		}
	}
	return false;
}

static bool flip_clicked(obs_properties_t *props, obs_property_t *property,
			 void *data)
{
	UNUSED_PARAMETER(props);
	UNUSED_PARAMETER(property);
	if (data)
		send(data, "{\"cmd\":\"flip\"}");
	return false;
}

static bool refresh_clicked(obs_properties_t *props, obs_property_t *property,
			    void *data)
{
	UNUSED_PARAMETER(props);
	UNUSED_PARAMETER(property);
	UNUSED_PARAMETER(data);
	return true;
}

static obs_property_t *slider(obs_properties_t *g, const char *id,
			      const char *label, double lo, double hi,
			      double step)
{
	obs_property_t *p = obs_properties_add_float_slider(g, id, label, lo,
							     hi, step);
	obs_property_set_modified_callback(p, ctl_modified);
	return p;
}

static obs_property_t *toggle(obs_properties_t *g, const char *id,
			      const char *label)
{
	obs_property_t *p = obs_properties_add_bool(g, id, label);
	obs_property_set_modified_callback(p, ctl_modified);
	return p;
}

static obs_property_t *choice(obs_properties_t *g, const char *id,
			      const char *label, enum obs_combo_format fmt)
{
	obs_property_t *p = obs_properties_add_list(
		g, id, label, OBS_COMBO_TYPE_LIST, fmt);
	obs_property_set_modified_callback(p, ctl_modified);
	return p;
}

void lenslink_camera_controls_add(obs_properties_t *props,
				  struct ios_camera_source *s,
				  obs_data_t *settings)
{
	obs_properties_t *g = obs_properties_create();
	obs_properties_set_param(g, s, NULL);

	char state[CTL_STATE_BUF];
	struct lenslink_ctl_state st;
	ios_camera_copy_state(s, state, sizeof(state));
	bool live = lenslink_ctl_parse(state, strlen(state), &st) &&
		    st.lens_count > 0;

	if (!live) {
		obs_properties_add_text(g, "ctl_none",
					T_("Controls.NotConnected"),
					OBS_TEXT_INFO);
		obs_properties_add_button(g, "ctl_refresh",
					  T_("Controls.Refresh"),
					  refresh_clicked);
		obs_properties_add_group(props, "ctl_group", T_("Controls"),
					 OBS_GROUP_NORMAL, g);
		return;
	}

	if (st.max_zoom > 1.0) {
		slider(g, CTL_ZOOM, T_("Web.Zoom"), 1.0, st.max_zoom, 0.1);
		obs_data_set_double(settings, CTL_ZOOM, st.zoom);
	}

	if (st.lens_count > 1) {
		obs_property_t *lens =
			choice(g, CTL_LENS, T_("Web.Lens"),
			       OBS_COMBO_FORMAT_STRING);
		for (int i = 0; i < st.lens_count; i++)
			obs_property_list_add_string(
				lens, lenslink_lens_text(st.lenses[i]),
				st.lenses[i]);
		obs_data_set_string(settings, CTL_LENS, st.lens);
	}

	if (st.has_flashlight) {
		toggle(g, CTL_FLASH, T_("Web.Flashlight"));
		obs_data_set_bool(settings, CTL_FLASH, st.flashlight);
	}
	obs_properties_add_button2(g, "ctl_flip", T_("Web.Flip"), flip_clicked,
				   s);

	if (st.stabilization[0]) {
		obs_property_t *stab = choice(g, CTL_STAB,
					      T_("Web.Stabilization"),
					      OBS_COMBO_FORMAT_STRING);
		obs_property_list_add_string(stab, T_("Web.Stabilization.Off"),
					     "off");
		obs_property_list_add_string(
			stab, T_("Web.Stabilization.Standard"), "standard");
		obs_property_list_add_string(
			stab, T_("Web.Stabilization.Cinematic"), "cinematic");
		obs_data_set_string(settings, CTL_STAB, st.stabilization);
	}

	if (st.supports_reframe) {
		slider(g, CTL_RF_ZOOM, T_("Web.Reframe"), 1.0, 4.0, 0.1);
		slider(g, CTL_RF_X, T_("Controls.ReframeX"), 0.0, 1.0, 0.01);
		slider(g, CTL_RF_Y, T_("Controls.ReframeY"), 0.0, 1.0, 0.01);
		obs_data_set_double(settings, CTL_RF_ZOOM, st.reframe_zoom);
		obs_data_set_double(settings, CTL_RF_X, st.reframe_x);
		obs_data_set_double(settings, CTL_RF_Y, st.reframe_y);
		if (st.supports_reframe_hq || st.reframe_hq) {
			obs_property_t *hq = toggle(g, CTL_RF_HQ,
						    T_("Web.Reframe.HQ"));
			obs_property_set_long_description(
				hq, T_("Web.Reframe.HQ.Tip"));
			obs_data_set_bool(settings, CTL_RF_HQ, st.reframe_hq);
		}
	}

	if (st.supports_green_screen) {
		toggle(g, CTL_GS, T_("Web.GreenScreen"));
		obs_data_set_bool(settings, CTL_GS, st.green_screen);
	}

	if (st.resolution_count && st.frame_rate_count) {
		obs_property_t *res = choice(g, CTL_RES, T_("Web.Resolution"),
					     OBS_COMBO_FORMAT_STRING);
		for (int i = 0; i < st.resolution_count; i++)
			obs_property_list_add_string(res, st.resolutions[i],
						     st.resolutions[i]);
		obs_data_set_string(settings, CTL_RES, st.resolution);

		obs_property_t *fps = choice(g, CTL_FPS, T_("Web.FrameRate"),
					     OBS_COMBO_FORMAT_INT);
		for (int i = 0; i < st.frame_rate_count; i++) {
			char label[16];
			snprintf(label, sizeof(label), "%d fps",
				 st.frame_rates[i]);
			obs_property_list_add_int(fps, label,
						  st.frame_rates[i]);
		}
		obs_data_set_int(settings, CTL_FPS, st.fps);
	}

	if (st.codec_count > 1) {
		obs_property_t *codec = choice(g, CTL_CODEC, T_("Web.Codec"),
					       OBS_COMBO_FORMAT_STRING);
		for (int i = 0; i < st.codec_count; i++)
			obs_property_list_add_string(
				codec,
				!strcmp(st.codecs[i], "hevc") ? "HEVC"
				: !strcmp(st.codecs[i], "h264") ? "H.264"
								: st.codecs[i],
				st.codecs[i]);
		obs_data_set_string(settings, CTL_CODEC, st.codec);
	}

	obs_properties_add_button(g, "ctl_refresh", T_("Controls.Refresh"),
				  refresh_clicked);
	obs_properties_add_group(props, "ctl_group", T_("Controls"),
				 OBS_GROUP_NORMAL, g);
}
