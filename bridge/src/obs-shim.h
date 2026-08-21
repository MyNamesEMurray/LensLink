/* Bridge-side extras that live alongside the libobs shim. */

#pragma once

/* Mirrors blog() into a file as well as stderr. The tray build has no
 * console, so this is the only record a bug report can carry. */
void lenslink_log_open(const char *path);
void lenslink_log_close(void);
void lenslink_log_set_level(int min_level);
