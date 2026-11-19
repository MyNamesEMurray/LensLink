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

int main(void)
{
	test_full_state();
	test_defaults_and_bad_input();
	TEST_MAIN_END();
}
