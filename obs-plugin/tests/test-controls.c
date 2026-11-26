#include "controls.h"
#include "test.h"

static void test_full_state(void)
{
	const char *json =
		"{\"paused\":false,\"zoom\":2.5,\"maxZoom\":10,"
		"\"hasFlashlight\":true,\"flashlight\":true,"
		"\"lens\":\"Main (Wide)\",\"lenses\":[\"Main (Wide)\",\"Telephoto\"],"
		"\"stabilization\":\"standard\",\"resolution\":\"1080p\",\"fps\":60,"
		"\"codec\":\"hevc\",\"resolutions\":[\"720p\",\"1080p\",\"4K\"],"
		"\"frameRates\":[30,60],\"codecs\":[\"h264\",\"hevc\"],"
		"\"supportsReframe\":true,\"supportsReframeHQ\":true,"
		"\"reframeHQ\":true,\"reframe\":{\"zoom\":2,\"x\":0.4,\"y\":0.6},"
		"\"supportsGreenScreen\":true,\"greenScreen\":false,\"unknown\":[1,{\"a\":2}]}";
	struct lenslink_ctl_state s;

	CHECK(lenslink_ctl_parse(json, strlen(json), &s));
	CHECK_NEAR(s.zoom, 2.5);
	CHECK_NEAR(s.max_zoom, 10);
	CHECK(s.has_flashlight && s.flashlight);
	CHECK_STR(s.lens, "Main (Wide)");
	CHECK(s.lens_count == 2);
	CHECK_STR(s.lenses[1], "Telephoto");
	CHECK_STR(s.stabilization, "standard");
	CHECK(s.resolution_count == 3);
	CHECK_STR(s.resolutions[2], "4K");
	CHECK(s.frame_rate_count == 2 && s.frame_rates[1] == 60);
	CHECK(s.codec_count == 2);
	CHECK(s.supports_reframe && s.supports_reframe_hq && s.reframe_hq);
	CHECK_NEAR(s.reframe_zoom, 2);
	CHECK_NEAR(s.reframe_x, 0.4);
	CHECK_NEAR(s.reframe_y, 0.6);
	CHECK(s.supports_green_screen && !s.green_screen);
}

static void test_defaults_and_bad_input(void)
{
	struct lenslink_ctl_state s;

	CHECK(lenslink_ctl_parse("{}", 2, &s));
	CHECK_NEAR(s.zoom, 1);
	CHECK_NEAR(s.reframe_zoom, 1);
	CHECK_NEAR(s.reframe_x, 0.5);
	CHECK(!s.supports_reframe && s.lens_count == 0);

	CHECK(!lenslink_ctl_parse("{\"zoom\":", 8, &s));
	CHECK(!s.valid);
	CHECK(!lenslink_ctl_parse("nope", 4, &s));
}

static void test_clamps(void)
{
	struct lenslink_ctl_state s;
	const char *a =
		"{\"zoom\":1e30,\"maxZoom\":1e300,\"fps\":1e30,"
		"\"frameRates\":[-5,1e30,60],"
		"\"reframe\":{\"zoom\":99,\"x\":-3,\"y\":7}}";
	CHECK(lenslink_ctl_parse(a, strlen(a), &s));
	CHECK_NEAR(s.max_zoom, 20);
	CHECK_NEAR(s.zoom, 20);
	CHECK(s.fps == 1000);
	CHECK(s.frame_rate_count == 3);
	CHECK(s.frame_rates[0] == 0 && s.frame_rates[1] == 1000 &&
	      s.frame_rates[2] == 60);
	CHECK_NEAR(s.reframe_zoom, 4);
	CHECK_NEAR(s.reframe_x, 0);
	CHECK_NEAR(s.reframe_y, 1);

	const char *b = "{\"zoom\":0.2,\"maxZoom\":-4,\"fps\":-1e30}";
	CHECK(lenslink_ctl_parse(b, strlen(b), &s));
	CHECK_NEAR(s.max_zoom, 1);
	CHECK_NEAR(s.zoom, 1);
	CHECK(s.fps == 0);

	const char *c = "{\"zoom\":3,\"maxZoom\":2}";
	CHECK(lenslink_ctl_parse(c, strlen(c), &s));
	CHECK_NEAR(s.zoom, 2);
}

static void test_pro_fields(void)
{
	const char *json =
		"{\"exposureBias\":-0.5,\"supportsManualExposure\":true,"
		"\"exposureMode\":\"manual\",\"isoMode\":\"manual\","
		"\"shutterMode\":\"auto\",\"iso\":400,\"minISO\":50,"
		"\"maxISO\":3200,\"shutterSeconds\":0.01,"
		"\"supportsWhiteBalanceLock\":true,"
		"\"whiteBalanceMode\":\"locked\","
		"\"whiteBalanceTemperature\":5600,\"whiteBalanceTint\":999,"
		"\"focusMode\":\"locked\",\"lensPosition\":0.42,"
		"\"hdr\":true,\"colors\":[\"sdr\",\"hlg\",\"log\"],"
		"\"monitor\":{\"zebra\":true,\"zebraLevel\":20,"
		"\"peaking\":true,\"falseColor\":false,\"guide\":\"2.39\"}}";
	struct lenslink_ctl_state s;

	CHECK(lenslink_ctl_parse(json, strlen(json), &s));
	CHECK_NEAR(s.exposure_bias, -0.5);
	CHECK(s.supports_manual_exposure && s.iso_manual && !s.shutter_manual);
	CHECK_NEAR(s.iso, 400);
	CHECK_NEAR(s.max_iso, 3200);
	CHECK_NEAR(s.shutter, 0.01);
	CHECK(s.supports_wb_lock && s.wb_locked);
	CHECK_NEAR(s.wb_temperature, 5600);
	CHECK_NEAR(s.wb_tint, 150);
	CHECK(s.focus_locked);
	CHECK_NEAR(s.lens_position, 0.42);
	CHECK_STR(s.color, "hlg");
	CHECK(s.color_count == 3);
	CHECK(s.has_monitor && s.zebra && s.peaking && !s.false_color);
	CHECK(s.zebra_level == 70);
	CHECK_STR(s.guide, "2.39");

	const char *old = "{\"exposureMode\":\"manual\",\"color\":\"log\"}";
	CHECK(lenslink_ctl_parse(old, strlen(old), &s));
	CHECK(s.iso_manual && s.shutter_manual);
	CHECK_STR(s.color, "log");
	CHECK(!s.has_monitor && s.zebra_level == 95);
	CHECK_STR(s.guide, "off");
}

int main(void)
{
	test_full_state();
	test_defaults_and_bad_input();
	test_clamps();
	test_pro_fields();
	TEST_MAIN_END();
}
