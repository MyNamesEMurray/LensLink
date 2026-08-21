/*
 * One connection to one phone, decoded into a frame queue.
 *
 * The type is named `struct ios_camera_source` because web-control.c is
 * compiled into the bridge unmodified and that is the type its upcalls
 * name (see web-control.h). Everything the panel asks of a "source" —
 * status, cached STATE, control forwarding — the bridge answers the
 * same way the plugin does, which is why the browser panel works here
 * with no changes at all.
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

struct frame_queue;

enum bridge_conn_mode {
	BRIDGE_CONN_LAN,
	BRIDGE_CONN_USB,
};

struct bridge_device_config {
	char name[64];       /* shown in the panel and the camera name */
	enum bridge_conn_mode mode;
	char host[128];      /* LAN: the phone's IP */
	uint16_t port;       /* LAN: 0 means the protocol default (9979) */
	char usb_udid[64];   /* USB: pin to one phone; empty = first free */
	bool is_screen;      /* accept a screen broadcast, not the camera */
	bool auto_start;     /* remote-start the camera when the app idles */
	bool allow_hw;       /* try GPU decode before software */
};

struct ios_camera_source;

struct ios_camera_source *
bridge_device_create(const struct bridge_device_config *cfg,
		     struct frame_queue *queue);

/* Starts/stops the dial thread. destroy() stops first if needed. */
void bridge_device_start(struct ios_camera_source *dev);
void bridge_device_stop(struct ios_camera_source *dev);
void bridge_device_destroy(struct ios_camera_source *dev);

/* Live numbers for the status line: 0/absent until a stream arrives. */
void bridge_device_stats(struct ios_camera_source *dev, uint32_t *width,
			 uint32_t *height, unsigned *latency_ms,
			 uint64_t *frames);
