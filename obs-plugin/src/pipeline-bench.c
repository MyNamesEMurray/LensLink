#include <obs-module.h>
#include <util/platform.h>
#include <util/threading.h>

#include <inttypes.h>
#include <stdio.h>
#include <time.h>

#include "pipeline-bench.h"
#include "plugin-settings.h"

static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

/* Current 1 s window (one CSV row each). */
static uint64_t g_frames;
static uint64_t g_cost_total_ns;
static uint64_t g_cost_max_ns;
static uint64_t g_bytes;
static int g_width, g_height;
static int g_latency_ms;
static int g_rtt_ms;
static uint64_t g_arrivals;
static uint64_t g_arrival_total_ns;
static uint64_t g_arrival_max_ns;
static uint64_t g_decodes;
static uint64_t g_decode_total_ns;
static uint64_t g_decode_max_ns;

/* 5 s aggregation for the human-readable OBS-log line. */
static uint64_t g_log_frames;
static uint64_t g_log_cost_total_ns;
static uint64_t g_log_cost_max_ns;
static uint64_t g_log_bytes;
static uint64_t g_log_arrivals;
static uint64_t g_log_arrival_total_ns;
static uint64_t g_log_decodes;
static uint64_t g_log_decode_total_ns;
static uint64_t g_log_decode_max_ns;

static uint64_t g_last_tick_ns;
static uint64_t g_last_log_ns;
static uint64_t g_file_start_ns;

/* Process CPU usage, sampled the same way OBS's own Stats dock does. */
static os_cpu_usage_info_t *g_cpu;

static FILE *g_csv;
static char g_csv_path[1024];

static bool g_run_active;
static char g_run_label[64];

static bool bench_on(void)
{
	return g_run_active || lenslink_settings_benchmark();
}

void lenslink_bench_frame(uint64_t cost_ns, size_t bytes_copied, int width,
			  int height)
{
	if (!bench_on())
		return;

	pthread_mutex_lock(&g_mutex);
	g_frames++;
	g_cost_total_ns += cost_ns;
	if (cost_ns > g_cost_max_ns)
		g_cost_max_ns = cost_ns;
	g_bytes += bytes_copied;
	g_width = width;
	g_height = height;
	pthread_mutex_unlock(&g_mutex);
}

void lenslink_bench_stages(bool have_arrival, uint64_t arrival_ns,
			   uint64_t decode_ns)
{
	if (!bench_on())
		return;

	pthread_mutex_lock(&g_mutex);
	if (have_arrival) {
		g_arrivals++;
		g_arrival_total_ns += arrival_ns;
		if (arrival_ns > g_arrival_max_ns)
			g_arrival_max_ns = arrival_ns;
	}
	g_decodes++;
	g_decode_total_ns += decode_ns;
	if (decode_ns > g_decode_max_ns)
		g_decode_max_ns = decode_ns;
	pthread_mutex_unlock(&g_mutex);
}

void lenslink_bench_latency(int latency_ms, int rtt_ms)
{
	if (!bench_on())
		return;
	pthread_mutex_lock(&g_mutex);
	g_latency_ms = latency_ms;
	g_rtt_ms = rtt_ms;
	pthread_mutex_unlock(&g_mutex);
}

static double avg_ms(uint64_t total_ns, uint64_t count)
{
	return count ? (double)total_ns / (double)count / 1e6 : 0.0;
}

/* One CSV per enable-run, named by pipeline + wall time so before/after
 * files are self-identifying for tools/bench-report.py. */
static void csv_open(void)
{
	char *dir = obs_module_config_path(NULL);
	if (!dir)
		return;
	os_mkdirs(dir);
	bfree(dir);

	char name[160];
	const char *pipeline =
		lenslink_settings_gpu_pipeline() ? "gpu" : "standard";
	if (g_run_label[0])
		snprintf(name, sizeof(name), "bench-%s-%s-%lld.csv",
			 g_run_label, pipeline, (long long)time(NULL));
	else
		snprintf(name, sizeof(name), "bench-%s-%lld.csv", pipeline,
			 (long long)time(NULL));
	char *path = obs_module_config_path(name);
	if (!path)
		return;
	g_csv = os_fopen(path, "w");
	if (g_csv) {
		fputs("time_s,pipeline,width,height,fps,avg_cost_ms,"
		      "max_cost_ms,copy_mb_s,latency_ms,obs_cpu_pct,"
		      "arrival_ms,max_arrival_ms,decode_ms,max_decode_ms,"
		      "rtt_ms\n",
		      g_csv);
		blog(LOG_INFO, "[lenslink][bench] writing samples to %s",
		     path);
		snprintf(g_csv_path, sizeof(g_csv_path), "%s", path);
	}
	bfree(path);
}

static void csv_close(void)
{
	if (g_csv) {
		fclose(g_csv);
		g_csv = NULL;
		blog(LOG_INFO, "[lenslink][bench] sample file closed");
	}
}

void lenslink_bench_set_run(bool on, const char *label)
{
	pthread_mutex_lock(&g_mutex);
	csv_close();
	g_last_tick_ns = 0;
	g_last_log_ns = 0;
	g_run_active = on;
	g_run_label[0] = 0;
	if (on && label) {
		size_t n = 0;
		for (const char *c = label;
		     *c && n + 1 < sizeof(g_run_label); c++) {
			bool ok = (*c >= 'a' && *c <= 'z') ||
				  (*c >= 'A' && *c <= 'Z') ||
				  (*c >= '0' && *c <= '9') || *c == '-' ||
				  *c == '_';
			g_run_label[n++] = ok ? *c : '-';
		}
		g_run_label[n] = 0;
	}
	char shown[sizeof(g_run_label)];
	snprintf(shown, sizeof(shown), "%s", g_run_label);
	pthread_mutex_unlock(&g_mutex);
	blog(LOG_INFO, "[lenslink][bench] run %s%s%s", on ? "started" : "ended",
	     shown[0] ? ": " : "", shown);
}

bool lenslink_bench_status(char *file, size_t file_size, bool *writing)
{
	pthread_mutex_lock(&g_mutex);
	bool active = g_run_active;
	if (writing)
		*writing = g_csv != NULL;
	if (file && file_size)
		snprintf(file, file_size, "%s", g_csv_path);
	pthread_mutex_unlock(&g_mutex);
	return active;
}

void lenslink_bench_shutdown(void)
{
	pthread_mutex_lock(&g_mutex);
	csv_close();
	if (g_cpu) {
		os_cpu_usage_info_destroy(g_cpu);
		g_cpu = NULL;
	}
	pthread_mutex_unlock(&g_mutex);
}

void lenslink_bench_maybe_log(void)
{
	pthread_mutex_lock(&g_mutex);

	if (!bench_on()) {
		/* Toggled off: finish the file so the report tool sees a
		 * complete run. */
		csv_close();
		g_last_tick_ns = 0;
		g_last_log_ns = 0;
		pthread_mutex_unlock(&g_mutex);
		return;
	}

	uint64_t now = os_gettime_ns();
	if (g_last_tick_ns == 0) {
		/* First tick with the benchmark on: start the windows (and
		 * the CPU sampler) instead of logging garbage. */
		g_last_tick_ns = now;
		g_last_log_ns = now;
		g_file_start_ns = now;
		g_frames = 0;
		g_cost_total_ns = 0;
		g_cost_max_ns = 0;
		g_bytes = 0;
		g_log_frames = 0;
		g_log_cost_total_ns = 0;
		g_log_cost_max_ns = 0;
		g_log_bytes = 0;
		g_arrivals = 0;
		g_arrival_total_ns = 0;
		g_arrival_max_ns = 0;
		g_decodes = 0;
		g_decode_total_ns = 0;
		g_decode_max_ns = 0;
		g_log_arrivals = 0;
		g_log_arrival_total_ns = 0;
		g_log_decodes = 0;
		g_log_decode_total_ns = 0;
		g_log_decode_max_ns = 0;
		if (!g_cpu)
			g_cpu = os_cpu_usage_info_start();
		if (!g_csv)
			csv_open();
		pthread_mutex_unlock(&g_mutex);
		return;
	}

	uint64_t window_ns = now - g_last_tick_ns;
	if (window_ns < 1000000000ULL) {
		pthread_mutex_unlock(&g_mutex);
		return;
	}

	/* Close the 1 s window: one CSV row (only when video flowed). */
	uint64_t frames = g_frames;
	uint64_t cost_total = g_cost_total_ns;
	uint64_t cost_max = g_cost_max_ns;
	uint64_t bytes = g_bytes;
	int w = g_width, h = g_height, lat = g_latency_ms, rtt = g_rtt_ms;
	uint64_t arrivals = g_arrivals;
	uint64_t arrival_total = g_arrival_total_ns;
	uint64_t arrival_max = g_arrival_max_ns;
	uint64_t decodes = g_decodes;
	uint64_t decode_total = g_decode_total_ns;
	uint64_t decode_max = g_decode_max_ns;
	g_frames = 0;
	g_cost_total_ns = 0;
	g_cost_max_ns = 0;
	g_bytes = 0;
	g_arrivals = 0;
	g_arrival_total_ns = 0;
	g_arrival_max_ns = 0;
	g_decodes = 0;
	g_decode_total_ns = 0;
	g_decode_max_ns = 0;
	g_last_tick_ns = now;

	g_log_frames += frames;
	g_log_cost_total_ns += cost_total;
	if (cost_max > g_log_cost_max_ns)
		g_log_cost_max_ns = cost_max;
	g_log_bytes += bytes;
	g_log_arrivals += arrivals;
	g_log_arrival_total_ns += arrival_total;
	g_log_decodes += decodes;
	g_log_decode_total_ns += decode_total;
	if (decode_max > g_log_decode_max_ns)
		g_log_decode_max_ns = decode_max;

	double cpu = g_cpu ? os_cpu_usage_info_query(g_cpu) : 0.0;
	double seconds = (double)window_ns / 1e9;

	if (frames > 0 && g_csv) {
		fprintf(g_csv,
			"%.1f,%s,%d,%d,%.1f,%.3f,%.3f,%.2f,%d,%.2f,"
			"%.3f,%.3f,%.3f,%.3f,%d\n",
			(double)(now - g_file_start_ns) / 1e9,
			lenslink_settings_gpu_pipeline() ? "gpu" : "standard",
			w, h, (double)frames / seconds,
			(double)cost_total / (double)frames / 1e6,
			(double)cost_max / 1e6,
			(double)bytes / seconds / 1e6, lat, cpu,
			avg_ms(arrival_total, arrivals),
			(double)arrival_max / 1e6,
			avg_ms(decode_total, decodes),
			(double)decode_max / 1e6, rtt);
		fflush(g_csv);
	}

	/* The human-readable line every ~5 s. */
	if (now - g_last_log_ns < 5000000000ULL) {
		pthread_mutex_unlock(&g_mutex);
		return;
	}
	double log_seconds = (double)(now - g_last_log_ns) / 1e9;
	uint64_t lf = g_log_frames;
	uint64_t lc = g_log_cost_total_ns;
	uint64_t lm = g_log_cost_max_ns;
	uint64_t lb = g_log_bytes;
	double la = avg_ms(g_log_arrival_total_ns, g_log_arrivals);
	double ld = avg_ms(g_log_decode_total_ns, g_log_decodes);
	double ldm = (double)g_log_decode_max_ns / 1e6;
	g_log_frames = 0;
	g_log_cost_total_ns = 0;
	g_log_cost_max_ns = 0;
	g_log_bytes = 0;
	g_log_arrivals = 0;
	g_log_arrival_total_ns = 0;
	g_log_decodes = 0;
	g_log_decode_total_ns = 0;
	g_log_decode_max_ns = 0;
	g_last_log_ns = now;
	pthread_mutex_unlock(&g_mutex);

	if (lf == 0)
		return; /* nothing streamed this window */

	blog(LOG_INFO,
	     "[lenslink][bench] pipeline=%s | %dx%d ~%.0f fps | "
	     "video-path cost/frame: avg %.2f ms, max %.2f ms | "
	     "pixel copies: %.1f MB/s | OBS process CPU: %.1f%%",
	     lenslink_settings_gpu_pipeline() ? "gpu" : "standard", w, h,
	     (double)lf / log_seconds, (double)lc / (double)lf / 1e6,
	     (double)lm / 1e6, (double)lb / log_seconds / 1e6, cpu);
	blog(LOG_INFO,
	     "[lenslink][bench] stages: capture->arrival avg %.2f ms | "
	     "decode avg %.2f ms, max %.2f ms | link rtt %d ms",
	     la, ld, ldm, rtt);
}
