#include <obs-module.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#endif

#include "plugin-settings.h"
#include "bridge-config.h"

void bridge_parse_host_port(const char *input, char *host, size_t host_size,
			    uint16_t *port)
{
	*port = 0;
	snprintf(host, host_size, "%s", input);

	/* Rightmost colon only, and only when what follows is entirely
	 * digits: a bare IPv6 literal has colons of its own and must not
	 * be chopped up here. */
	char *colon = strrchr(host, ':');
	if (!colon || colon == host)
		return;
	for (const char *p = colon + 1; *p; p++) {
		if (!isdigit((unsigned char)*p))
			return;
	}
	if (strchr(host, ':') != colon)
		return; /* more than one colon: an IPv6 literal */

	int value = atoi(colon + 1);
	if (value <= 0 || value > 65535)
		return;
	*port = (uint16_t)value;
	*colon = 0;
}

void bridge_config_default_path(char *out, size_t size)
{
#ifdef _WIN32
	const char *base = getenv("APPDATA");
	snprintf(out, size, "%s\\LensLink\\bridge.ini",
		 base ? base : ".");
#else
	const char *xdg = getenv("XDG_CONFIG_HOME");
	if (xdg && xdg[0])
		snprintf(out, size, "%s/lenslink/bridge.ini", xdg);
	else {
		const char *home = getenv("HOME");
		snprintf(out, size, "%s/.config/lenslink/bridge.ini",
			 home ? home : ".");
	}
#endif
}

static void make_parent_dirs(const char *path)
{
	char dir[512];
	snprintf(dir, sizeof(dir), "%s", path);

	char *last = strrchr(dir, '/');
#ifdef _WIN32
	char *last_bs = strrchr(dir, '\\');
	if (!last || (last_bs && last_bs > last))
		last = last_bs;
#endif
	if (!last)
		return;
	*last = 0;

	/* Walk the path creating each component; ignore "already exists". */
	for (char *p = dir + 1; *p; p++) {
		if (*p != '/' && *p != '\\')
			continue;
		char sep = *p;
		*p = 0;
#ifdef _WIN32
		_mkdir(dir);
#else
		mkdir(dir, 0755);
#endif
		*p = sep;
	}
#ifdef _WIN32
	_mkdir(dir);
#else
	mkdir(dir, 0755);
#endif
}

static char *trim(char *s)
{
	while (*s && isspace((unsigned char)*s))
		s++;
	char *end = s + strlen(s);
	while (end > s && isspace((unsigned char)end[-1]))
		*--end = 0;
	return s;
}

static bool parse_bool(const char *v)
{
	return strcmp(v, "true") == 0 || strcmp(v, "yes") == 0 ||
	       strcmp(v, "1") == 0 || strcmp(v, "on") == 0;
}

static void device_defaults(struct bridge_device_config *dev, size_t index)
{
	memset(dev, 0, sizeof(*dev));
	snprintf(dev->name, sizeof(dev->name), "LensLink Camera%s",
		 index ? " 2" : "");
	dev->mode = BRIDGE_CONN_LAN;
	dev->auto_start = true;
	dev->allow_hw = true;
}

static void set_defaults(struct bridge_config *cfg)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->web_enabled = true;
	cfg->web_port = LLS_WEB_PORT_DEFAULT;
	device_defaults(&cfg->devices[0], 0);
	cfg->device_count = 1;
}

static void apply_key(struct bridge_config *cfg, bool in_device,
		      const char *key, const char *value)
{
	if (!in_device) {
		if (strcmp(key, "web_control") == 0)
			cfg->web_enabled = parse_bool(value);
		else if (strcmp(key, "web_control_port") == 0)
			cfg->web_port = atoi(value);
		else if (strcmp(key, "log_file") == 0)
			snprintf(cfg->log_file, sizeof(cfg->log_file), "%s",
				 value);
		else
			blog(LOG_WARNING, "[lenslink] unknown config key '%s'",
			     key);
		return;
	}

	struct bridge_device_config *dev =
		&cfg->devices[cfg->device_count - 1];

	if (strcmp(key, "name") == 0)
		snprintf(dev->name, sizeof(dev->name), "%s", value);
	else if (strcmp(key, "mode") == 0)
		dev->mode = strcmp(value, "usb") == 0 ? BRIDGE_CONN_USB
						      : BRIDGE_CONN_LAN;
	else if (strcmp(key, "host") == 0)
		bridge_parse_host_port(value, dev->host, sizeof(dev->host),
				       &dev->port);
	else if (strcmp(key, "usb_udid") == 0)
		snprintf(dev->usb_udid, sizeof(dev->usb_udid), "%s", value);
	else if (strcmp(key, "kind") == 0)
		dev->is_screen = strcmp(value, "screen") == 0;
	else if (strcmp(key, "auto_start") == 0)
		dev->auto_start = parse_bool(value);
	else if (strcmp(key, "hardware_decode") == 0)
		dev->allow_hw = parse_bool(value);
	else
		blog(LOG_WARNING, "[lenslink] unknown device key '%s'", key);
}

bool bridge_config_load(struct bridge_config *cfg, const char *path)
{
	set_defaults(cfg);

	FILE *f = fopen(path, "r");
	if (!f)
		return true; /* first run */

	/* The file replaces the implicit default device rather than adding
	 * to it: a file listing one [device] must not yield two. */
	bool saw_device_section = false;
	bool in_device = false;
	char line[1024];

	while (fgets(line, sizeof(line), f)) {
		char *s = trim(line);
		if (!*s || *s == '#' || *s == ';')
			continue;

		if (*s == '[') {
			char *end = strchr(s, ']');
			if (!end)
				continue;
			*end = 0;
			const char *section = s + 1;
			if (strcmp(section, "device") == 0) {
				if (!saw_device_section) {
					saw_device_section = true;
					cfg->device_count = 0;
				}
				if (cfg->device_count >= BRIDGE_MAX_DEVICES) {
					blog(LOG_WARNING,
					     "[lenslink] more than %d devices "
					     "configured; ignoring the rest",
					     BRIDGE_MAX_DEVICES);
					in_device = false;
					continue;
				}
				device_defaults(
					&cfg->devices[cfg->device_count],
					cfg->device_count);
				cfg->device_count++;
				in_device = true;
			} else {
				in_device = false;
			}
			continue;
		}

		char *eq = strchr(s, '=');
		if (!eq)
			continue;
		*eq = 0;
		char *key = trim(s);
		char *value = trim(eq + 1);
		apply_key(cfg, in_device, key, value);
	}

	fclose(f);

	if (saw_device_section && cfg->device_count == 0) {
		device_defaults(&cfg->devices[0], 0);
		cfg->device_count = 1;
	}
	return true;
}

bool bridge_config_save(const struct bridge_config *cfg, const char *path)
{
	make_parent_dirs(path);

	FILE *f = fopen(path, "w");
	if (!f)
		return false;

	fprintf(f, "# LensLink Bridge configuration.\n"
		   "# See bridge/README.md and docs/DRIVERLESS.md.\n\n");
	fprintf(f, "web_control = %s\n", cfg->web_enabled ? "true" : "false");
	fprintf(f, "web_control_port = %d\n", cfg->web_port);
	if (cfg->log_file[0])
		fprintf(f, "log_file = %s\n", cfg->log_file);

	for (size_t i = 0; i < cfg->device_count; i++) {
		const struct bridge_device_config *dev = &cfg->devices[i];
		fprintf(f, "\n[device]\n");
		fprintf(f, "name = %s\n", dev->name);
		fprintf(f, "mode = %s\n",
			dev->mode == BRIDGE_CONN_USB ? "usb" : "lan");
		if (dev->port)
			fprintf(f, "host = %s:%u\n", dev->host,
				(unsigned)dev->port);
		else
			fprintf(f, "host = %s\n", dev->host);
		if (dev->usb_udid[0])
			fprintf(f, "usb_udid = %s\n", dev->usb_udid);
		fprintf(f, "kind = %s\n", dev->is_screen ? "screen" : "camera");
		fprintf(f, "auto_start = %s\n",
			dev->auto_start ? "true" : "false");
		fprintf(f, "hardware_decode = %s\n",
			dev->allow_hw ? "true" : "false");
	}

	fclose(f);
	return true;
}
