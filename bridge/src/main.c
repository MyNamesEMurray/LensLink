/*
 * LensLink Bridge — the phone as a plain webcam, without OBS.
 *
 * Dials the phone exactly the way the OBS plugin does (same transport,
 * same protocol, literally the same source files), decodes, converts to
 * NV12 and hands frames to a virtual-camera backend. The browser
 * control panel on 127.0.0.1:9980 is the plugin's, unmodified.
 *
 * See docs/DRIVERLESS.md for the design and for what this mode
 * deliberately does not do (no audio, no lip-sync, no tally).
 */

#include <obs-module.h>
#include <util/threading.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

#include "net-compat.h"
#include "mdns.h"
#include "usbmux.h"
#include "web-control.h"

#include "obs-shim.h"
#include "bridge-config.h"
#include "bridge-core.h"
#include "frame-queue.h"
#include "vcam.h"

#ifndef LENSLINK_VERSION
#define LENSLINK_VERSION "dev"
#endif

void bridge_settings_apply(const struct bridge_config *cfg);

static volatile sig_atomic_t g_quit;

static void on_signal(int sig)
{
	(void)sig;
	g_quit = 1;
}

/* ------------------------------------------------------------------ */

static void usage(void)
{
	printf("LensLink Bridge " LENSLINK_VERSION "\n"
	       "Use an iPhone running LensLink as a webcam, without OBS.\n"
	       "\n"
	       "Usage: lenslink-bridge [options]\n"
	       "\n"
	       "  --host <ip>        Phone's IP address (overrides the config)\n"
	       "  --usb              Connect over USB instead of Wi-Fi\n"
	       "  --screen           Accept a screen broadcast, not the camera\n"
	       "  --name <text>      Name for the virtual camera\n"
	       "  --config <path>    Config file (default: see below)\n"
	       "  --save             Write the resulting config back and exit\n"
	       "  --web-port <n>     Control panel port (0 disables the panel)\n"
	       "  --log <path>       Mirror the log to a file\n"
	       "  --snapshot <path>  Write the first decoded frame as a PPM\n"
	       "  --frames <n>       Exit after n decoded frames (0 = never)\n"
	       "  --discover         List LensLink phones on the LAN and exit\n"
	       "  --list-usb         List phones attached over USB and exit\n"
	       "  --version          Print the version and exit\n"
	       "  --help             This message\n");

	char path[512];
	bridge_config_default_path(path, sizeof(path));
	printf("\nDefault config: %s\n", path);
}

static int cmd_discover(void)
{
	struct mdns_result results[16];
	printf("Browsing for LensLink phones (2 s)...\n");
	int n = mdns_browse("_lenslink._tcp.local", 2000, results, 16);
	if (n <= 0) {
		printf("No phones found. Make sure the LensLink app is open "
		       "and on the same network.\n");
		return 1;
	}
	for (int i = 0; i < n; i++)
		printf("  %-32s %s\n", results[i].name, results[i].host);
	return 0;
}

static int cmd_list_usb(void)
{
	struct usbmux_device devs[16];
	int n = usbmux_list_devices(devs, 16);
	if (n <= 0) {
		printf("No devices on USB. Check the cable, tap Trust on the "
		       "phone, and make sure iTunes (Apple Mobile Device "
		       "Support) is installed.\n");
		return 1;
	}
	for (int i = 0; i < n; i++)
		printf("  id=%ld udid=%s\n", devs[i].id, devs[i].udid);
	return 0;
}

/* ------------------------------------------------------------------ */
/* The pump: newest decoded frame -> the virtual camera.
 *
 * Polls rather than being signalled, deliberately. The queue's contract
 * is "newest wins, no backlog", so a missed wake-up costs one frame and
 * never accumulates; a 4 ms tick keeps up with 120 fps while staying
 * far cheaper than a condition variable per frame. */

struct pump {
	struct frame_queue *queue;
	struct vcam_sink *sink;
	uint64_t max_frames; /* 0 = unlimited */
	uint64_t delivered;
	volatile bool stop;
	pthread_t thread;
};

static void *pump_thread(void *data)
{
	struct pump *p = data;
	os_set_thread_name("lenslink-pump");

	uint8_t *buffer = NULL;
	size_t buffer_size = 0;
	uint64_t last_seq = 0;

	while (!p->stop) {
		uint32_t width = 0, height = 0;
		uint64_t pts = 0, seq = 0;

		if (!frame_queue_read(p->queue, NULL, 0, &width, &height, &pts,
				      &seq) ||
		    seq == last_seq) {
			os_sleep_ms(4);
			continue;
		}

		size_t needed = (size_t)width * height * 3 / 2;
		if (needed > buffer_size) {
			bfree(buffer);
			buffer = bmalloc(needed);
			buffer_size = needed;
		}

		if (!frame_queue_read(p->queue, buffer, buffer_size, &width,
				      &height, &pts, &seq)) {
			/* Raced with a resize; the next tick catches it. */
			continue;
		}
		last_seq = seq;

		if (!vcam_submit(p->sink, buffer, width, height, pts))
			break;

		p->delivered++;
		if (p->max_frames && p->delivered >= p->max_frames) {
			blog(LOG_INFO,
			     "[lenslink] reached the --frames limit (%llu)",
			     (unsigned long long)p->max_frames);
			g_quit = 1;
			break;
		}
	}

	bfree(buffer);
	return NULL;
}

/* ------------------------------------------------------------------ */

int main(int argc, char **argv)
{
	char config_path[512] = {0};
	const char *host_override = NULL;
	const char *name_override = NULL;
	const char *log_override = NULL;
	const char *snapshot_path = NULL;
	bool usb_override = false;
	bool screen_override = false;
	bool save_and_exit = false;
	int web_port_override = -1;
	uint64_t max_frames = 0;

	for (int i = 1; i < argc; i++) {
		const char *arg = argv[i];
		bool has_value = i + 1 < argc;

/* Statement expressions are a GNU extension and this builds under
 * MSVC too, so the check and the fetch stay separate. */
#define NEED_VALUE(name)                                             \
	if (!has_value) {                                            \
		fprintf(stderr, "%s needs a value\n", name);         \
		return 2;                                            \
	}

		if (strcmp(arg, "--help") == 0 || strcmp(arg, "-h") == 0) {
			usage();
			return 0;
		} else if (strcmp(arg, "--version") == 0) {
			printf("%s\n", LENSLINK_VERSION);
			return 0;
		} else if (strcmp(arg, "--discover") == 0) {
			if (!net_init())
				return 1;
			int rc = cmd_discover();
			net_shutdown();
			return rc;
		} else if (strcmp(arg, "--list-usb") == 0) {
			if (!net_init())
				return 1;
			int rc = cmd_list_usb();
			net_shutdown();
			return rc;
		} else if (strcmp(arg, "--host") == 0) {
			NEED_VALUE("--host")
			host_override = argv[++i];
		} else if (strcmp(arg, "--name") == 0) {
			NEED_VALUE("--name")
			name_override = argv[++i];
		} else if (strcmp(arg, "--config") == 0) {
			NEED_VALUE("--config")
			snprintf(config_path, sizeof(config_path), "%s",
				 argv[++i]);
		} else if (strcmp(arg, "--log") == 0) {
			NEED_VALUE("--log")
			log_override = argv[++i];
		} else if (strcmp(arg, "--snapshot") == 0) {
			NEED_VALUE("--snapshot")
			snapshot_path = argv[++i];
		} else if (strcmp(arg, "--web-port") == 0) {
			NEED_VALUE("--web-port")
			web_port_override = atoi(argv[++i]);
		} else if (strcmp(arg, "--frames") == 0) {
			NEED_VALUE("--frames")
			max_frames = strtoull(argv[++i], NULL, 10);
		} else if (strcmp(arg, "--usb") == 0) {
			usb_override = true;
		} else if (strcmp(arg, "--screen") == 0) {
			screen_override = true;
		} else if (strcmp(arg, "--save") == 0) {
			save_and_exit = true;
		} else {
			fprintf(stderr, "Unknown option: %s\n\n", arg);
			usage();
			return 2;
		}
#undef NEED_VALUE
	}

	if (!config_path[0])
		bridge_config_default_path(config_path, sizeof(config_path));

	struct bridge_config cfg;
	if (!bridge_config_load(&cfg, config_path)) {
		fprintf(stderr, "Cannot read config: %s\n", config_path);
		return 1;
	}

	/* Command-line overrides apply to the first device: the flags are
	 * the single-phone convenience path, and a multi-phone setup is
	 * expressed in the config file instead. */
	struct bridge_device_config *first = &cfg.devices[0];
	if (host_override) {
		bridge_parse_host_port(host_override, first->host,
				       sizeof(first->host), &first->port);
		first->mode = BRIDGE_CONN_LAN;
	}
	if (usb_override)
		first->mode = BRIDGE_CONN_USB;
	if (screen_override)
		first->is_screen = true;
	if (name_override)
		snprintf(first->name, sizeof(first->name), "%s", name_override);
	if (log_override)
		snprintf(cfg.log_file, sizeof(cfg.log_file), "%s", log_override);
	if (web_port_override >= 0) {
		cfg.web_port = web_port_override;
		cfg.web_enabled = web_port_override > 0;
	}

	if (save_and_exit) {
		if (!bridge_config_save(&cfg, config_path)) {
			fprintf(stderr, "Cannot write config: %s\n",
				config_path);
			return 1;
		}
		printf("Wrote %s\n", config_path);
		return 0;
	}

	if (cfg.log_file[0])
		lenslink_log_open(cfg.log_file);

	blog(LOG_INFO, "[lenslink] LensLink Bridge %s starting (config: %s)",
	     LENSLINK_VERSION, config_path);

	if (!net_init()) {
		blog(LOG_ERROR, "[lenslink] socket startup failed");
		return 1;
	}

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	bridge_settings_apply(&cfg);

	struct frame_queue *queue = frame_queue_create();
	struct vcam_sink *sink = vcam_create(first->name);
	if (snapshot_path)
		vcam_request_snapshot(sink, snapshot_path);

	/* One device feeds the virtual camera today. The extra config slots
	 * exist because the control panel is already multi-source and the
	 * next backend can register one camera per device — see
	 * docs/DRIVERLESS.md. */
	if (cfg.device_count > 1)
		blog(LOG_WARNING,
		     "[lenslink] %u devices configured; only the first feeds "
		     "the virtual camera in this build",
		     (unsigned)cfg.device_count);

	struct ios_camera_source *device = bridge_device_create(first, queue);
	if (!device) {
		blog(LOG_ERROR, "[lenslink] failed to create the device");
		return 1;
	}

	web_control_register(device);
	web_control_apply_settings();
	if (cfg.web_enabled)
		blog(LOG_INFO, "[lenslink] control panel: http://127.0.0.1:%d",
		     cfg.web_port);

	bridge_device_start(device);

	struct pump pump = {
		.queue = queue,
		.sink = sink,
		.max_frames = max_frames,
	};
	if (pthread_create(&pump.thread, NULL, pump_thread, &pump) != 0) {
		blog(LOG_ERROR, "[lenslink] failed to start the frame pump");
		g_quit = 1;
	}

	/* Status heartbeat: one line every 5 s, which is what makes a
	 * headless run diagnosable without attaching anything. */
	uint64_t last_beat = 0;
	while (!g_quit) {
		os_sleep_ms(100);

		uint64_t now = os_gettime_ns();
		if (now - last_beat < 5000000000ULL)
			continue;
		last_beat = now;

		char status[512];
		uint32_t width = 0, height = 0;
		unsigned latency_ms = 0;
		uint64_t frames = 0, published = 0, overwritten = 0;
		ios_camera_copy_status(device, status, sizeof(status));
		bridge_device_stats(device, &width, &height, &latency_ms,
				    &frames);
		frame_queue_stats(queue, &published, &overwritten);

		if (width)
			blog(LOG_INFO,
			     "[lenslink] %ux%u | ~%u ms | %llu decoded, "
			     "%llu to the camera, %llu dropped | %s",
			     width, height, latency_ms,
			     (unsigned long long)frames,
			     (unsigned long long)pump.delivered,
			     (unsigned long long)overwritten, status);
		else
			blog(LOG_INFO, "[lenslink] %s", status);
	}

	blog(LOG_INFO, "[lenslink] shutting down");

	pump.stop = true;
	pthread_join(pump.thread, NULL);

	bridge_device_stop(device);
	web_control_unregister(device);
	web_control_apply_settings();
	bridge_device_destroy(device);

	vcam_destroy(sink);
	frame_queue_destroy(queue);
	net_shutdown();
	lenslink_log_close();
	return 0;
}
