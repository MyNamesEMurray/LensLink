/*
 * One-button diagnostics report: everything a maintainer needs to explain a
 * failure the reporter cannot see, assembled into pasteable text.
 *
 * Built from the same health snapshots the frontend UI reads, plus the
 * environment facts that decide whether the plugin can work at all — OBS
 * and plugin versions, OS and CPU architecture (including whether OBS is
 * running translated), the graphics device, and the last socket error each
 * source hit while dialling.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Returns a bmalloc'd report; free with bfree. Never returns NULL. */
char *lenslink_diagnostics_report(void);

/* Writes the report to the OBS log, so "Help → Log Files" carries it. */
void lenslink_diagnostics_log(void);

#ifdef __cplusplus
}
#endif
