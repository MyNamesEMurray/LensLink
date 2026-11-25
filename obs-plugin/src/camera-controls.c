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
#define CTL_EV "ctl_ev"
#define CTL_ISO_AUTO "ctl_iso_auto"
#define CTL_ISO "ctl_iso"
#define CTL_SH_AUTO "ctl_shutter_auto"
#define CTL_SH "ctl_shutter"
#define CTL_WB_AUTO "ctl_wb_auto"
#define CTL_WB "ctl_wb"
#define CTL_TINT "ctl_tint"
#define CTL_FOCUS_AUTO "ctl_focus_auto"
#define CTL_FOCUS "ctl_focus"
#define CTL_COLOR "ctl_color"
#define CTL_ZEBRA "ctl_zebra"
#define CTL_PEAK "ctl_peaking"
#define CTL_FALSE "ctl_false_color"
#define CTL_GUIDE "ctl_guide"

#define CTL_STATE_BUF (32 * 1024 + 1)

void lenslink_camera_controls_clear(obs_data_t *settings)
{
	static const char *const keys[] = {
		CTL_ZOOM, CTL_LENS,  CTL_FLASH, CTL_STAB,  CTL_RF_ZOOM,
		CTL_RF_X, CTL_RF_Y,  CTL_RF_HQ, CTL_GS,    CTL_RES,
		CTL_FPS,  CTL_CODEC, CTL_EV,    CTL_ISO_AUTO, CTL_ISO,
		CTL_SH_AUTO, CTL_SH, CTL_WB_AUTO, CTL_WB, CTL_TINT,
		CTL_FOCUS_AUTO, CTL_FOCUS, CTL_COLOR, CTL_ZEBRA, CTL_PEAK,
		CTL_FALSE, CTL_GUIDE,
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

static const char *bool_str(bool on)
{
	return on ? "true" : "false";
}

/* The exposure, white balance, focus, colour and monitoring properties.
 * Each sends only when the value differs from the phone's, so the
 * properties dialog filling itself from STATE never echoes a command. */
static void pro_modified(struct ios_camera_source *s, const char *name,
			 obs_data_t *settings,
			 const struct lenslink_ctl_state *st)
{
	char json[160];
	json[0] = 0;

	if (!strcmp(name, CTL_EV)) {
		double v = obs_data_get_double(settings, CTL_EV);
		if (differs(v, st->exposure_bias))
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"exposure_bias\",\"value\":%.2f}", v);
	} else if (!strcmp(name, CTL_ISO_AUTO)) {
		bool manual = !obs_data_get_bool(settings, CTL_ISO_AUTO);
		if (manual != st->iso_manual)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"lock\",\"target\":\"iso\",\"on\":%s}",
				 bool_str(manual));
	} else if (!strcmp(name, CTL_ISO)) {
		double v = obs_data_get_double(settings, CTL_ISO);
		if (fabs(v - st->iso) >= 1)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"exposure\",\"isoMode\":\"manual\",\"iso\":%.0f}",
				 v);
	} else if (!strcmp(name, CTL_SH_AUTO)) {
		bool manual = !obs_data_get_bool(settings, CTL_SH_AUTO);
		if (manual != st->shutter_manual)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"lock\",\"target\":\"shutter\",\"on\":%s}",
				 bool_str(manual));
	} else if (!strcmp(name, CTL_SH)) {
		long long d = obs_data_get_int(settings, CTL_SH);
		if (d > 0 && st->shutter > 0 &&
		    llround(1.0 / st->shutter) != d)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"exposure\",\"shutterMode\":\"manual\","
				 "\"shutterSeconds\":%.6f}",
				 1.0 / (double)d);
	} else if (!strcmp(name, CTL_WB_AUTO)) {
		bool locked = !obs_data_get_bool(settings, CTL_WB_AUTO);
		if (locked != st->wb_locked)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"lock\",\"target\":\"whiteBalance\",\"on\":%s}",
				 bool_str(locked));
	} else if (!strcmp(name, CTL_WB) || !strcmp(name, CTL_TINT)) {
		double k = obs_data_get_double(settings, CTL_WB);
		double tint = obs_data_get_double(settings, CTL_TINT);
		if (fabs(k - st->wb_temperature) >= 10 ||
		    fabs(tint - st->wb_tint) >= 1)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"white_balance\",\"mode\":\"locked\","
				 "\"temperature\":%.0f,\"tint\":%.0f}",
				 k, tint);
	} else if (!strcmp(name, CTL_FOCUS_AUTO)) {
		bool locked = !obs_data_get_bool(settings, CTL_FOCUS_AUTO);
		if (locked != st->focus_locked)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"lock\",\"target\":\"focus\",\"on\":%s}",
				 bool_str(locked));
	} else if (!strcmp(name, CTL_FOCUS)) {
		double v = obs_data_get_double(settings, CTL_FOCUS);
		if (fabs(v - st->lens_position) >= 0.005)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"focus\",\"mode\":\"locked\",\"lensPosition\":%.3f}",
				 v);
	} else if (!strcmp(name, CTL_COLOR)) {
		const char *v = obs_data_get_string(settings, CTL_COLOR);
		if (v[0] && strcmp(v, st->color))
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"set_format\",\"color\":\"%s\"}", v);
	} else if (!strcmp(name, CTL_ZEBRA)) {
		bool on = obs_data_get_bool(settings, CTL_ZEBRA);
		if (on != st->zebra)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"monitor\",\"zebra\":%s}", bool_str(on));
	} else if (!strcmp(name, CTL_PEAK)) {
		bool on = obs_data_get_bool(settings, CTL_PEAK);
		if (on != st->peaking)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"monitor\",\"peaking\":%s}",
				 bool_str(on));
	} else if (!strcmp(name, CTL_FALSE)) {
		bool on = obs_data_get_bool(settings, CTL_FALSE);
		if (on != st->false_color)
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"monitor\",\"falseColor\":%s}",
				 bool_str(on));
	} else if (!strcmp(name, CTL_GUIDE)) {
		const char *v = obs_data_get_string(settings, CTL_GUIDE);
		if (v[0] && strcmp(v, st->guide))
			snprintf(json, sizeof(json),
				 "{\"cmd\":\"monitor\",\"guide\":\"%s\"}", v);
	}
	if (json[0])
		send(s, json);
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
	} else {
		pro_modified(s, name, settings, &st);
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

static const int shutter_denominators[] = {
	2,   3,    4,    5,    6,    8,    10,   13,   15,   20,
	24,  25,   30,   40,   48,   50,   60,   80,   96,   100,
	120, 125,  160,  200,  250,  320,  400,  500,  640,  800,
	1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000,
};

static void add_pro_controls(obs_properties_t *g, obs_data_t *settings,
			     const struct lenslink_ctl_state *st)
{
	slider(g, CTL_EV, T_("Controls.EV"), -3.0, 3.0, 0.1);
	obs_data_set_double(settings, CTL_EV, st->exposure_bias);

	if (st->supports_manual_exposure && st->max_iso > st->min_iso) {
		toggle(g, CTL_ISO_AUTO, T_("Controls.ISOAuto"));
		obs_data_set_bool(settings, CTL_ISO_AUTO, !st->iso_manual);
		slider(g, CTL_ISO, "ISO", st->min_iso, st->max_iso, 1);
		obs_data_set_double(settings, CTL_ISO, st->iso);

		toggle(g, CTL_SH_AUTO, T_("Controls.ShutterAuto"));
		obs_data_set_bool(settings, CTL_SH_AUTO, !st->shutter_manual);
		obs_property_t *sh = choice(g, CTL_SH, T_("Web.Shutter"),
					    OBS_COMBO_FORMAT_INT);
		size_t n = sizeof(shutter_denominators) /
			   sizeof(shutter_denominators[0]);
		for (size_t i = 0; i < n; i++) {
			double secs = 1.0 / shutter_denominators[i];
			if (st->max_shutter > 0 &&
			    (secs > st->max_shutter * 1.001 ||
			     secs < st->min_shutter * 0.999))
				continue;
			char label[16];
			snprintf(label, sizeof(label), "1/%d",
				 shutter_denominators[i]);
			obs_property_list_add_int(sh, label,
						  shutter_denominators[i]);
		}
		if (st->shutter > 0)
			obs_data_set_int(settings, CTL_SH,
					 llround(1.0 / st->shutter));
	}

	if (st->supports_wb_lock) {
		toggle(g, CTL_WB_AUTO, T_("Controls.WBAuto"));
		obs_data_set_bool(settings, CTL_WB_AUTO, !st->wb_locked);
		slider(g, CTL_WB, T_("Web.WB"), 2500, 8000, 50);
		obs_data_set_double(settings, CTL_WB, st->wb_temperature);
		slider(g, CTL_TINT, T_("Web.Tint"), -150, 150, 1);
		obs_data_set_double(settings, CTL_TINT, st->wb_tint);
	}

	toggle(g, CTL_FOCUS_AUTO, T_("Controls.FocusAuto"));
	obs_data_set_bool(settings, CTL_FOCUS_AUTO, !st->focus_locked);
	slider(g, CTL_FOCUS, T_("Web.Focus"), 0, 1, 0.01);
	obs_data_set_double(settings, CTL_FOCUS, st->lens_position);

	if (st->color_count > 1) {
		obs_property_t *color = choice(g, CTL_COLOR, T_("Web.Color"),
					       OBS_COMBO_FORMAT_STRING);
		for (int i = 0; i < st->color_count; i++) {
			const char *c = st->colors[i];
			obs_property_list_add_string(
				color,
				!strcmp(c, "sdr")   ? T_("Web.Color.SDR")
				: !strcmp(c, "hlg") ? T_("Web.Color.HLG")
				: !strcmp(c, "log") ? T_("Web.Color.Log")
						    : c,
				c);
		}
		obs_data_set_string(settings, CTL_COLOR, st->color);
	}

	if (st->has_monitor) {
		toggle(g, CTL_ZEBRA, T_("Web.Zebra"));
		obs_data_set_bool(settings, CTL_ZEBRA, st->zebra);
		toggle(g, CTL_PEAK, T_("Web.Peaking"));
		obs_data_set_bool(settings, CTL_PEAK, st->peaking);
		toggle(g, CTL_FALSE, T_("Web.FalseColor"));
		obs_data_set_bool(settings, CTL_FALSE, st->false_color);
		obs_property_t *guide = choice(g, CTL_GUIDE, T_("Web.Guides"),
					       OBS_COMBO_FORMAT_STRING);
		obs_property_list_add_string(guide, T_("Web.Guides.Off"), "off");
		obs_property_list_add_string(guide, T_("Web.Guides.Grid"),
					     "grid");
		obs_property_list_add_string(guide, "2.39:1", "2.39");
		obs_property_list_add_string(guide, "1.85:1", "1.85");
		obs_property_list_add_string(guide, "4:3", "4:3");
		obs_data_set_string(settings, CTL_GUIDE, st->guide);
	}
}

/* OBS hotkeys (Settings > Hotkeys, listed under the source's name): the
 * Pro controls an operator reaches for without a mouse. Each toggles
 * from the phone's last STATE, so a press always flips what is live. */
enum hotkey_action {
	HK_PAUSE,
	HK_LOCK_ALL,
	HK_NEXT_LENS,
	HK_FLASHLIGHT,
	HK_ZEBRA,
	HK_PEAKING,
	HK_FALSE_COLOR,
	HK_COUNT,
};

static const char *const hotkey_names[HK_COUNT] = {
	"lenslink.pause",     "lenslink.lock_all", "lenslink.next_lens",
	"lenslink.flashlight", "lenslink.zebra",   "lenslink.peaking",
	"lenslink.false_color",
};

struct hotkey_ctx {
	struct ios_camera_source *s;
	enum hotkey_action action;
	obs_hotkey_id id;
};

static bool is_front(const char *label)
{
	return !strncmp(label, "Front", 5);
}

static void hotkey_command(enum hotkey_action action,
			   const struct lenslink_ctl_state *st, char *json,
			   size_t size)
{
	switch (action) {
	case HK_PAUSE:
		snprintf(json, size, "{\"cmd\":\"%s\"}",
			 st->paused ? "resume_stream" : "pause_stream");
		break;
	case HK_LOCK_ALL: {
		bool all = st->focus_locked &&
			   (!st->supports_wb_lock || st->wb_locked) &&
			   (!st->supports_manual_exposure ||
			    (st->iso_manual && st->shutter_manual));
		snprintf(json, size,
			 "{\"cmd\":\"lock\",\"target\":\"all\",\"on\":%s}",
			 bool_str(!all));
		break;
	}
	case HK_NEXT_LENS: {
		int cur = -1;
		for (int i = 0; i < st->lens_count; i++)
			if (!strcmp(st->lenses[i], st->lens))
				cur = i;
		for (int step = 1; cur >= 0 && step < st->lens_count; step++) {
			const char *next = st->lenses[(cur + step) % st->lens_count];
			if (is_front(next) == is_front(st->lens)) {
				obs_data_t *cmd = obs_data_create();
				obs_data_set_string(cmd, "cmd", "selectLens");
				obs_data_set_string(cmd, "label", next);
				snprintf(json, size, "%s", obs_data_get_json(cmd));
				obs_data_release(cmd);
				break;
			}
		}
		break;
	}
	case HK_FLASHLIGHT:
		if (st->has_flashlight)
			snprintf(json, size,
				 "{\"cmd\":\"flashlight\",\"on\":%s}",
				 bool_str(!st->flashlight));
		break;
	case HK_ZEBRA:
		snprintf(json, size, "{\"cmd\":\"monitor\",\"zebra\":%s}",
			 bool_str(!st->zebra));
		break;
	case HK_PEAKING:
		snprintf(json, size, "{\"cmd\":\"monitor\",\"peaking\":%s}",
			 bool_str(!st->peaking));
		break;
	case HK_FALSE_COLOR:
		snprintf(json, size,
			 "{\"cmd\":\"monitor\",\"falseColor\":%s}",
			 bool_str(!st->false_color));
		break;
	default:
		break;
	}
}

static void hotkey_pressed(void *data, obs_hotkey_id id, obs_hotkey_t *hotkey,
			   bool pressed)
{
	UNUSED_PARAMETER(id);
	UNUSED_PARAMETER(hotkey);
	struct hotkey_ctx *ctx = data;
	if (!pressed)
		return;
	char *state = bmalloc(CTL_STATE_BUF);
	struct lenslink_ctl_state st;
	ios_camera_copy_state(ctx->s, state, CTL_STATE_BUF);
	if (lenslink_ctl_parse(state, strlen(state), &st) &&
	    st.lens_count > 0) {
		char json[256] = {0};
		hotkey_command(ctx->action, &st, json, sizeof(json));
		if (json[0])
			send(ctx->s, json);
	}
	bfree(state);
}

void *lenslink_camera_hotkeys_register(struct ios_camera_source *s,
				       obs_source_t *source)
{
	const char *const texts[HK_COUNT] = {
		T_("Hotkey.Pause"),	 T_("Hotkey.LockAll"),
		T_("Hotkey.NextLens"),	 T_("Hotkey.Flashlight"),
		T_("Hotkey.Zebra"),	 T_("Hotkey.Peaking"),
		T_("Hotkey.FalseColor"),
	};
	struct hotkey_ctx *ctx = bzalloc(sizeof(*ctx) * HK_COUNT);
	for (int i = 0; i < HK_COUNT; i++) {
		ctx[i].s = s;
		ctx[i].action = (enum hotkey_action)i;
		ctx[i].id = obs_hotkey_register_source(source, hotkey_names[i],
						       texts[i],
						       hotkey_pressed, &ctx[i]);
	}
	return ctx;
}

void lenslink_camera_hotkeys_free(void *hotkeys)
{
	struct hotkey_ctx *ctx = hotkeys;
	if (!ctx)
		return;
	for (int i = 0; i < HK_COUNT; i++)
		obs_hotkey_unregister(ctx[i].id);
	bfree(ctx);
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

	add_pro_controls(g, settings, &st);

	obs_properties_add_button(g, "ctl_refresh", T_("Controls.Refresh"),
				  refresh_clicked);
	obs_properties_add_group(props, "ctl_group", T_("Controls"),
				 OBS_GROUP_NORMAL, g);
}
