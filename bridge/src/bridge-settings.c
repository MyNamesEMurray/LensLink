/*
 * The two plugin-wide settings web-control.c reads. In OBS these come
 * from Tools -> LensLink Settings (plugin-settings.c); here they come
 * from the bridge's config file, so the same web-control.c satisfies
 * both without a #ifdef.
 */

#include <stdbool.h>

#include "plugin-settings.h"
#include "bridge-config.h"

static bool g_web_enabled = true;
static int g_web_port = LLS_WEB_PORT_DEFAULT;

void bridge_settings_apply(const struct bridge_config *cfg)
{
	g_web_enabled = cfg->web_enabled;
	g_web_port = cfg->web_port;
}

bool lenslink_settings_web_enabled(void)
{
	return g_web_enabled;
}

int lenslink_settings_web_port(void)
{
	return g_web_port;
}
