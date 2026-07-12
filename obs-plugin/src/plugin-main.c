#include <obs-module.h>

#include "net-compat.h"

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("lenslink", "en-US")

MODULE_EXPORT const char *obs_module_description(void)
{
	return "LensLink — use an iPhone or iPad camera as a video source over "
	       "Wi-Fi or USB (LensLink companion app required)";
}

extern struct obs_source_info ios_camera_source_info;

bool obs_module_load(void)
{
	if (!net_init()) {
		blog(LOG_ERROR, "[lenslink] network init failed");
		return false;
	}

	obs_register_source(&ios_camera_source_info);
	blog(LOG_INFO, "[lenslink] plugin loaded");
	return true;
}

void obs_module_unload(void)
{
	net_shutdown();
}
