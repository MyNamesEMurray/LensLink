#include <obs-module.h>
#include <util/bmem.h>
#include <util/dstr.h>
#include <util/platform.h>

#include <string.h>

#include "diagnostics.h"
#include "health.h"
#include "plugin-settings.h"
#include "net-compat.h"

#ifdef __APPLE__
#include <sys/sysctl.h>
#endif
#ifdef __linux__
#include <sys/utsname.h>
#include <stdio.h>
#endif

#ifndef LENSLINK_VERSION
#define LENSLINK_VERSION "dev"
#endif

/* The module's own architecture. A mismatch with OBS cannot happen in
 * process — a plugin that failed to load never runs this — but naming it
 * turns "did my universal build actually run native?" into a fact. */
#if defined(__aarch64__) || defined(_M_ARM64)
#define MODULE_ARCH "arm64"
#elif defined(__x86_64__) || defined(_M_X64)
#define MODULE_ARCH "x86_64"
#else
#define MODULE_ARCH "unknown"
#endif

#if defined(_WIN32)
#define PLATFORM_NAME "Windows"
#elif defined(__APPLE__)
#define PLATFORM_NAME "macOS"
#elif defined(__linux__)
#define PLATFORM_NAME "Linux"
#else
#define PLATFORM_NAME "unknown"
#endif

#ifdef __APPLE__
static void sysctl_str(const char *name, char *out, size_t len)
{
	size_t n = len;
	out[0] = '\0';
	if (sysctlbyname(name, out, &n, NULL, 0) != 0)
		snprintf(out, len, "?");
}

/* Non-zero when this process is running under Rosetta — i.e. an Intel OBS
 * on Apple silicon. Everything still works, but it explains surprising
 * performance and rules out an architecture mismatch as the cause of a
 * plugin that "did nothing". */
static int rosetta_translated(void)
{
	int v = 0;
	size_t n = sizeof(v);
	if (sysctlbyname("sysctl.proc_translated", &v, &n, NULL, 0) != 0)
		return 0;
	return v;
}
#endif

static void append_environment(struct dstr *d)
{
	dstr_cat(d, "== Environment ==\n");
	dstr_catf(d, "LensLink:     %s (%s module)\n", LENSLINK_VERSION,
		  MODULE_ARCH);
	dstr_catf(d, "OBS Studio:   %s\n", obs_get_version_string());
	dstr_catf(d, "Platform:     %s\n", PLATFORM_NAME);

#ifdef __APPLE__
	char osver[64], model[128], cpu[128];
	sysctl_str("kern.osproductversion", osver, sizeof(osver));
	sysctl_str("hw.model", model, sizeof(model));
	sysctl_str("machdep.cpu.brand_string", cpu, sizeof(cpu));
	dstr_catf(d, "macOS:        %s\n", osver);
	dstr_catf(d, "Mac:          %s (%s)\n", model, cpu);
	dstr_catf(d, "Rosetta:      %s\n",
		  rosetta_translated()
			  ? "yes — OBS is the Intel build, translated"
			  : "no");
#endif
#ifdef __linux__
	struct utsname u;
	if (uname(&u) == 0)
		dstr_catf(d, "Kernel:       %s %s (%s)\n", u.sysname,
			  u.release, u.machine);
	FILE *f = fopen("/etc/os-release", "r");
	if (f) {
		char line[256];
		while (fgets(line, sizeof(line), f)) {
			if (strncmp(line, "PRETTY_NAME=", 12) != 0)
				continue;
			char *v = line + 12, *nl = strchr(v, '\n');
			if (nl)
				*nl = '\0';
			if (*v == '"') {
				v++;
				char *q = strrchr(v, '"');
				if (q)
					*q = '\0';
			}
			dstr_catf(d, "Distribution: %s\n", v);
			break;
		}
		fclose(f);
	}
#endif

	/* The graphics device decides whether the GPU pipeline can share
	 * textures at all, and names the driver in a multi-GPU laptop. */
	obs_enter_graphics();
	const char *gpu = gs_get_device_name();
	dstr_catf(d, "Graphics:     %s\n", gpu ? gpu : "?");
	obs_leave_graphics();
	dstr_cat(d, "\n");
}

static void append_settings(struct dstr *d)
{
	obs_data_t *s = lenslink_settings_snapshot();
	dstr_cat(d, "== Plugin settings ==\n");
	dstr_catf(d, "GPU decode pipeline: %s\n",
		  obs_data_get_bool(s, LLS_GPU_PIPELINE) ? "on" : "off");
	dstr_catf(d, "Browser panel:       %s (port %d)\n",
		  obs_data_get_bool(s, LLS_WEB_ENABLED) ? "on" : "off",
		  (int)obs_data_get_int(s, LLS_WEB_PORT));
	dstr_catf(d, "Verbose diagnostics: %s\n",
		  obs_data_get_bool(s, LLS_DIAGNOSTICS) ? "on" : "off");
	obs_data_release(s);
	dstr_cat(d, "\n");
}

/* A socket error is the difference between "nothing was listening" and
 * "the OS refused to let us try", which look identical in the UI and have
 * completely different fixes. */
static const char *dial_error_meaning(int err)
{
#ifndef _WIN32
	switch (err) {
	case EPERM:
	case EACCES:
		return "refused by the OS — on macOS 13+ check "
		       "System Settings > Privacy & Security > Local Network "
		       "for OBS; on Linux check a firewall";
	case EHOSTUNREACH:
	case ENETUNREACH:
		return "no route — different network, or the phone is asleep";
	case ECONNREFUSED:
		return "nothing listening — the app is closed or backgrounded";
	case ETIMEDOUT:
		return "no answer — often client isolation on the network";
	default:
		break;
	}
#endif
	return NULL;
}

static void append_sources(struct dstr *d)
{
	struct lenslink_health h[16];
	size_t n = lenslink_health_enum(h, 16);

	dstr_cat(d, "== Sources ==\n");
	if (n == 0) {
		dstr_cat(d, "(none — no LensLink source exists in this "
			    "scene collection)\n\n");
		return;
	}

	for (size_t i = 0; i < n; i++) {
		dstr_catf(d, "[%s] %s\n", h[i].is_screen ? "Screen" : "Camera",
			  h[i].source_name);
		dstr_catf(d, "  status:    %s\n", h[i].status);
		dstr_catf(d, "  device:    %s\n",
			  h[i].device[0] ? h[i].device : "(unknown)");
		dstr_catf(d, "  transport: %s\n",
			  h[i].transport[0] ? h[i].transport : "(none)");
		dstr_catf(d, "  state:     %s%s\n",
			  h[i].connected ? "connected" : "not connected",
			  h[i].standby ? ", camera idle (standby)" : "");
		if (h[i].connected) {
			dstr_catf(d, "  received:  %llu packets, %llu "
				     "keyframes, %llu bytes\n",
				  (unsigned long long)h[i].video_packets,
				  (unsigned long long)h[i].keyframes,
				  (unsigned long long)h[i].bytes);
			dstr_catf(d, "  decoded:   %llu frames, %llu errors\n",
				  (unsigned long long)h[i].frames,
				  (unsigned long long)h[i].decode_errors);
			dstr_catf(d, "  decoder:   %s%s\n",
				  h[i].decoder[0] ? h[i].decoder : "none",
				  h[i].gpu_pipeline ? ", GPU pipeline"
						    : "");
			if (h[i].hw_retries)
				dstr_catf(d, "  hw retries: %d — hardware "
					     "decode fell back\n",
					  h[i].hw_retries);
			dstr_catf(d, "  latency:   %d ms\n", h[i].latency_ms);
			if (h[i].green_screen)
				dstr_cat(d, "  green screen: ON — the phone "
					    "is painting its background green; "
					    "a green picture may be this "
					    "working, not a fault\n");

			/* The one comparison worth spelling out, because it
			 * separates a dead link from a live one whose picture
			 * has frozen or gone green. */
			if (h[i].video_packets > 0 && h[i].frames == 0)
				dstr_cat(d, "  NOTE: packets arrived but "
					    "nothing decoded — the link is "
					    "fine, the decoder is not\n");
		}
		if (h[i].last_dial_error) {
			const char *why =
				dial_error_meaning(h[i].last_dial_error);
			dstr_catf(d, "  last dial error: %d",
				  h[i].last_dial_error);
			if (why)
				dstr_catf(d, " — %s", why);
			dstr_cat(d, "\n");
		}
		dstr_cat(d, "\n");
	}
}

char *lenslink_diagnostics_report(void)
{
	struct dstr d = {0};

	dstr_cat(&d, "LensLink diagnostics\n");
	dstr_cat(&d, "Paste this into a GitHub issue: "
		     "https://github.com/MyNamesEMurray/LensLink/issues\n");
	dstr_cat(&d, "It contains no video, no audio and no personal data — "
		     "versions, hardware and connection state only.\n\n");

	append_environment(&d);
	append_settings(&d);
	append_sources(&d);

	dstr_cat(&d, "Also useful: the OBS log (Help > Log Files > Upload "
		     "Current Log File), and — if the picture went wrong "
		     "rather than absent — the camera's own state from\n"
		     "curl localhost:9980/api/state, which says whether the "
		     "green screen is on and what format was negotiated.\n");

	return d.array ? d.array : bstrdup("");
}

void lenslink_diagnostics_log(void)
{
	char *report = lenslink_diagnostics_report();
	blog(LOG_INFO, "[lenslink] diagnostics report follows\n%s", report);
	bfree(report);
}
