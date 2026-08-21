/*
 * Bridge configuration.
 *
 * A small INI-style file rather than OBS's obs_data JSON: the bridge
 * has no libobs, the file is meant to be hand-editable, and the whole
 * schema is a dozen keys. Defaults are chosen so an empty file plus a
 * phone IP on the command line is a working setup.
 *
 * Location: %APPDATA%\LensLink\bridge.ini on Windows,
 * ~/.config/lenslink/bridge.ini elsewhere. Override with --config.
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "bridge-core.h"

#define BRIDGE_MAX_DEVICES 4

struct bridge_config {
	bool web_enabled;
	int web_port;
	char log_file[512]; /* empty = stderr only */

	struct bridge_device_config devices[BRIDGE_MAX_DEVICES];
	size_t device_count;
};

/*
 * Splits "10.0.0.4" or "10.0.0.4:9979" into host and port, leaving
 * `*port` at 0 when none was given (the caller then uses the protocol
 * default). A port only ever comes from a deliberate override — the app
 * always listens on 9979 — but it is what lets the smoke test point the
 * bridge at a fake phone on an unprivileged port.
 */
void bridge_parse_host_port(const char *input, char *host, size_t host_size,
			    uint16_t *port);

/* Fills `cfg` with defaults, then applies `path` if it exists. Returns
 * false only when the file exists but cannot be read — a missing file
 * is the normal first-run case, not an error. */
bool bridge_config_load(struct bridge_config *cfg, const char *path);

/* The default config path for this platform, into `out`. */
void bridge_config_default_path(char *out, size_t size);

/* Writes the current config back, creating parent directories. Used by
 * --save so a user can start from a populated file instead of a blank
 * one. */
bool bridge_config_save(const struct bridge_config *cfg, const char *path);
