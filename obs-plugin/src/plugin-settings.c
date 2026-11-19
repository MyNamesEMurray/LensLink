#include <obs-module.h>
#include <util/platform.h>
#include <util/threading.h>

#include <string.h>

#include "net-compat.h"
#include "plugin-settings.h"
#include "web-auth.h"

/* Plain globals, written under the mutex and read without it: every
 * consumer re-reads on use, all values are single words, and a torn read
 * is impossible for bool/int on the supported platforms. */
static bool g_gpu_pipeline = false;
static bool g_web_enabled = true;
static int g_web_port = LLS_WEB_PORT_DEFAULT;
static bool g_web_lan = false;
static char g_web_key[WEB_AUTH_KEY_SIZE];
static bool g_diagnostics = false;
static bool g_dump_stream = false;
static bool g_benchmark = false;

static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

static char *settings_path(void)
{
	char *dir = obs_module_config_path(NULL);
	if (!dir)
		return NULL;
	os_mkdirs(dir);
	bfree(dir);
	return obs_module_config_path("settings.json");
}

static void load_from(obs_data_t *data)
{
	pthread_mutex_lock(&g_mutex);
	g_gpu_pipeline = obs_data_get_bool(data, LLS_GPU_PIPELINE);
	g_web_enabled = obs_data_get_bool(data, LLS_WEB_ENABLED);
	int port = (int)obs_data_get_int(data, LLS_WEB_PORT);
	g_web_port = (port >= 1024 && port <= 65535) ? port
						     : LLS_WEB_PORT_DEFAULT;
	g_web_lan = obs_data_get_bool(data, LLS_WEB_LAN);
	snprintf(g_web_key, sizeof(g_web_key), "%s",
		 obs_data_get_string(data, LLS_WEB_KEY));
	g_diagnostics = obs_data_get_bool(data, LLS_DIAGNOSTICS);
	g_dump_stream = obs_data_get_bool(data, LLS_DUMP_STREAM);
	g_benchmark = obs_data_get_bool(data, LLS_BENCHMARK);
	pthread_mutex_unlock(&g_mutex);
}

static void set_defaults(obs_data_t *data)
{
	obs_data_set_default_bool(data, LLS_GPU_PIPELINE, false);
	obs_data_set_default_bool(data, LLS_WEB_ENABLED, true);
	obs_data_set_default_int(data, LLS_WEB_PORT, LLS_WEB_PORT_DEFAULT);
	obs_data_set_default_bool(data, LLS_WEB_LAN, false);
	obs_data_set_default_string(data, LLS_WEB_KEY, "");
	obs_data_set_default_bool(data, LLS_DIAGNOSTICS, false);
	obs_data_set_default_bool(data, LLS_DUMP_STREAM, false);
	obs_data_set_default_bool(data, LLS_BENCHMARK, false);
}

void lenslink_settings_init(void)
{
	char *path = settings_path();
	obs_data_t *data = path ? obs_data_create_from_json_file(path)
				: NULL;
	if (!data)
		data = obs_data_create();
	set_defaults(data);
	load_from(data);
	obs_data_release(data);
	bfree(path);

	blog(LOG_INFO,
	     "[lenslink] settings: pipeline=%s web=%s port=%d diag=%s",
	     g_gpu_pipeline ? "gpu (beta)" : "standard",
	     g_web_enabled ? "on" : "off", g_web_port,
	     g_diagnostics ? "on" : "off");
}

void lenslink_settings_shutdown(void)
{
	/* Nothing owned; the globals just stop being read. */
}

bool lenslink_settings_gpu_pipeline(void)
{
	return g_gpu_pipeline;
}

bool lenslink_settings_web_enabled(void)
{
	return g_web_enabled;
}

int lenslink_settings_web_port(void)
{
	return g_web_port;
}

bool lenslink_settings_web_lan(void)
{
	return g_web_lan;
}

void lenslink_settings_web_key(char *out, size_t size)
{
	pthread_mutex_lock(&g_mutex);
	snprintf(out, size, "%s", g_web_key);
	pthread_mutex_unlock(&g_mutex);
}

bool lenslink_settings_new_key(char *out, size_t size)
{
	char key[WEB_AUTH_KEY_SIZE];
	if (size < sizeof(key) || !web_auth_random_key(key))
		return false;
	memcpy(out, key, sizeof(key));
	return true;
}

bool lenslink_settings_local_ipv4(char *out, size_t size)
{
	if (!net_init())
		return false;
	bool ok = false;
	socket_t s = socket(AF_INET, SOCK_DGRAM, 0);
	if (s != OBSC_INVALID_SOCKET) {
		struct sockaddr_in peer;
		memset(&peer, 0, sizeof(peer));
		peer.sin_family = AF_INET;
		peer.sin_port = htons(9);
		peer.sin_addr.s_addr = htonl(0xC0000201);
		struct sockaddr_in me;
		socklen_t len = sizeof(me);
		if (connect(s, (struct sockaddr *)&peer, sizeof(peer)) == 0 &&
		    getsockname(s, (struct sockaddr *)&me, &len) == 0 &&
		    me.sin_addr.s_addr != 0 &&
		    (ntohl(me.sin_addr.s_addr) >> 24) != 127) {
			inet_ntop(AF_INET, &me.sin_addr, out, (socklen_t)size);
			ok = true;
		}
		net_close(s);
	}
	return ok;
}

bool lenslink_settings_diagnostics(void)
{
	return g_diagnostics;
}

bool lenslink_settings_dump_stream(void)
{
	return g_dump_stream;
}

bool lenslink_settings_benchmark(void)
{
	return g_benchmark;
}

obs_data_t *lenslink_settings_snapshot(void)
{
	obs_data_t *data = obs_data_create();
	pthread_mutex_lock(&g_mutex);
	obs_data_set_bool(data, LLS_GPU_PIPELINE, g_gpu_pipeline);
	obs_data_set_bool(data, LLS_WEB_ENABLED, g_web_enabled);
	obs_data_set_int(data, LLS_WEB_PORT, g_web_port);
	obs_data_set_bool(data, LLS_WEB_LAN, g_web_lan);
	obs_data_set_string(data, LLS_WEB_KEY, g_web_key);
	obs_data_set_bool(data, LLS_DIAGNOSTICS, g_diagnostics);
	obs_data_set_bool(data, LLS_DUMP_STREAM, g_dump_stream);
	obs_data_set_bool(data, LLS_BENCHMARK, g_benchmark);
	pthread_mutex_unlock(&g_mutex);
	return data;
}

void lenslink_settings_update(obs_data_t *values)
{
	set_defaults(values);
	if (obs_data_get_bool(values, LLS_WEB_LAN) &&
	    !*obs_data_get_string(values, LLS_WEB_KEY)) {
		char key[WEB_AUTH_KEY_SIZE];
		if (web_auth_random_key(key))
			obs_data_set_string(values, LLS_WEB_KEY, key);
	}
	load_from(values);

	char *path = settings_path();
	if (path) {
		if (!obs_data_save_json_safe(values, path, "tmp", "bak"))
			blog(LOG_WARNING,
			     "[lenslink] settings: could not save %s", path);
		bfree(path);
	}
}
