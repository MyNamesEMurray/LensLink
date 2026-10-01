#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Pipeline benchmark: hard before/after numbers for the GPU (beta)
 * pipeline. When enabled (Tools -> LensLink Settings), a clearly tagged
 * line lands in the OBS log every ~5 s:
 *
 *   [lenslink][bench] pipeline=standard | 1920x1080 ~60 fps |
 *     video-path cost/frame: avg 2.84 ms, max 4.10 ms |
 *     pixel copies: 186.4 MB/s | OBS process CPU: 9.8%
 *
 * "video-path cost" is the per-frame CPU time this plugin spends moving
 * a decoded frame toward the compositor — the exact work the pipelines
 * do differently (standard: GPU download + OBS frame copy; GPU: texture
 * map/draw prep). "pixel copies" is decoded video crossing system
 * memory. Same scene, both pipelines, two log lines = the comparison
 * table. Off by default; zero overhead beyond a branch when off.
 *
 * Thread-safe; callers are the decode threads and the render thread.
 */

/* One frame moved through the video path: how long the pipeline-specific
 * work took, and how many bytes of pixels crossed system memory. */
void lenslink_bench_frame(uint64_t cost_ns, size_t bytes_copied,
			  int width, int height);

void lenslink_bench_stages(bool have_arrival, uint64_t arrival_ns,
			   uint64_t decode_ns);

/* Latest capture->decode latency (TIMESYNC-derived), for the CSV rows. */
void lenslink_bench_latency(int latency_ms, int rtt_ms);

/* Rate-limited logger + CSV writer; call from any ~1 Hz maintenance
 * tick. While the setting is on, every second of live video appends a
 * row to bench-<pipeline>-<epoch>.csv in the plugin config dir (path
 * logged at open); tools/bench-report.py turns a before/after pair of
 * those files into a comparison report. */
void lenslink_bench_maybe_log(void);

void lenslink_bench_set_run(bool on, const char *label);

bool lenslink_bench_enabled(void);

struct lenslink_phone_stages {
	double capture_ms;
	double encode_ms;
	double encode_max_ms;
	double send_ms;
	double total_ms;
};

void lenslink_bench_phone(const struct lenslink_phone_stages *stages);

bool lenslink_bench_status(char *file, size_t file_size, bool *writing);

/* Closes the sample file; module unload. */
void lenslink_bench_shutdown(void);

#ifdef __cplusplus
}
#endif
