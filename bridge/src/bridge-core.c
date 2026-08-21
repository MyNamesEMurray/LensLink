/*
 * The bridge's dial loop: connect to the phone, parse the wire protocol,
 * decode, publish NV12 frames for the virtual-camera sinks.
 *
 * This mirrors the plugin's dial loop in ios-camera-source.c, minus
 * everything that only means something inside OBS — lip-sync
 * calibration, tally program/preview, the GPU texture pipeline, source
 * properties. The transport, discovery and decode code underneath is
 * not a copy: usbmux.c, mdns.c and h264-decoder.c are the plugin's own
 * files, compiled into this binary unchanged.
 */

#include <obs-module.h>
#include <util/threading.h>

#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#include "net-compat.h"
#include "protocol.h"
#include "usbmux.h"
#include "h264-decoder.h"
#include "web-control.h"

#include "bridge-core.h"
#include "bridge-strings.h"
#include "frame-queue.h"
#include "nv12.h"

#define RECV_CHUNK (256 * 1024)
#define SEND_BUF_MAX (256 * 1024)
#define CONTROL_QUEUE_MAX 32

/* ------------------------------------------------------------------ */

struct recv_buf {
	uint8_t *data;
	size_t len;
	size_t cap;
};

struct send_buf {
	uint8_t *data;
	size_t len;
	size_t cap;
	bool failed;
};

struct client_state {
	socket_t sock;
	struct recv_buf buf;
	struct send_buf out;
	struct h264_decoder *decoder;
	int hw_retry;
	uint64_t packets_at_decoder;
	enum AVCodecID codec_id;
	bool is_screen;
	bool standby;
	bool wrong_kind;
	char name[128];

	/* NTP-style clock offset (phone clock minus ours) and the running
	 * per-frame capture->decode figure built from it. */
	uint64_t last_sync_send;
	int64_t offset_ns;
	bool offset_valid;
	uint64_t lat_sum_ns;
	uint64_t lat_count;
	uint64_t lat_window_start;

	uint64_t video_packets;
	uint64_t frames_output;
};

struct ios_camera_source {
	struct bridge_device_config cfg;
	struct frame_queue *queue;
	struct nv12_converter *conv;

	pthread_t thread;
	bool thread_active;
	volatile bool stop;

	pthread_mutex_t status_mutex;
	char status[512];
	char device_state[4096]; /* latest STATE snapshot, verbatim */
	char device_name[128];
	bool connected;
	bool standby;
	bool is_screen;
	uint32_t width;
	uint32_t height;
	unsigned latency_ms;
	uint64_t frames;

	/* Commands from the web panel, drained by the dial loop. */
	pthread_mutex_t control_mutex;
	char control_queue[CONTROL_QUEUE_MAX][512];
	size_t control_count;

	bool auto_start_armed;
	int dial_failures;
};

/* ------------------------------------------------------------------ */
/* Status. */

static void set_status(struct ios_camera_source *s, const char *fmt, ...)
{
	char buf[512];
	va_list args;
	va_start(args, fmt);
	vsnprintf(buf, sizeof(buf), fmt, args);
	va_end(args);

	pthread_mutex_lock(&s->status_mutex);
	if (strcmp(s->status, buf) != 0) {
		snprintf(s->status, sizeof(s->status), "%s", buf);
		blog(LOG_INFO, "[lenslink] %s: %s", s->cfg.name, buf);
	}
	pthread_mutex_unlock(&s->status_mutex);
}

/* ------------------------------------------------------------------ */
/* Buffers. Same growth/shrink discipline as the plugin: receive
 * straight into the tail, compact once per recv cycle, and release a
 * keyframe-sized spike instead of pinning it for the connection. */

static void recv_buf_free(struct recv_buf *b)
{
	bfree(b->data);
	memset(b, 0, sizeof(*b));
}

static void recv_buf_reserve(struct recv_buf *b, size_t size)
{
	if (b->len + size > b->cap) {
		size_t new_cap = b->cap ? b->cap : RECV_CHUNK;
		while (new_cap < b->len + size)
			new_cap *= 2;
		b->data = brealloc(b->data, new_cap);
		b->cap = new_cap;
	}
}

static void recv_buf_consume(struct recv_buf *b, size_t size)
{
	if (size >= b->len)
		b->len = 0;
	else {
		memmove(b->data, b->data + size, b->len - size);
		b->len -= size;
	}

	if (b->cap > 2 * RECV_CHUNK && b->len < RECV_CHUNK) {
		size_t new_cap = 2 * RECV_CHUNK;
		uint8_t *shrunk = bmalloc(new_cap);
		memcpy(shrunk, b->data, b->len);
		bfree(b->data);
		b->data = shrunk;
		b->cap = new_cap;
	}
}

static void send_buf_free(struct send_buf *b)
{
	bfree(b->data);
	memset(b, 0, sizeof(*b));
}

static void client_flush(struct client_state *c)
{
	struct send_buf *b = &c->out;
	while (b->len > 0 && !b->failed) {
		int n = (int)send(c->sock, (const char *)b->data, (int)b->len,
				  0);
		if (n > 0) {
			memmove(b->data, b->data + n, b->len - (size_t)n);
			b->len -= (size_t)n;
		} else if (n < 0 && net_would_block()) {
			return;
		} else {
			b->failed = true;
		}
	}
}

static void client_send(struct client_state *c, const void *data, size_t len)
{
	struct send_buf *b = &c->out;
	const uint8_t *p = data;

	if (b->failed)
		return;

	if (b->len == 0) {
		while (len > 0) {
			int n = (int)send(c->sock, (const char *)p, (int)len,
					  0);
			if (n > 0) {
				p += n;
				len -= (size_t)n;
			} else if (n < 0 && net_would_block()) {
				break;
			} else {
				b->failed = true;
				return;
			}
		}
		if (len == 0)
			return;
	}

	if (b->len + len > SEND_BUF_MAX) {
		blog(LOG_WARNING,
		     "[lenslink] peer not draining control channel, "
		     "dropping connection");
		b->failed = true;
		return;
	}
	if (b->len + len > b->cap) {
		size_t new_cap = b->cap ? b->cap : 4096;
		while (new_cap < b->len + len)
			new_cap *= 2;
		b->data = brealloc(b->data, new_cap);
		b->cap = new_cap;
	}
	memcpy(b->data + b->len, p, len);
	b->len += len;
}

static void send_control_cmd(struct client_state *c, const char *json)
{
	size_t len = strlen(json);
	uint8_t hdr[OBSC_HEADER_SIZE];
	obsc_build_header(hdr, OBSC_PKT_CONTROL, 0, os_gettime_ns(),
			  (uint32_t)len);
	client_send(c, hdr, OBSC_HEADER_SIZE);
	client_send(c, json, len);
}

/* ------------------------------------------------------------------ */
/* Minimal JSON field reads. The payloads are the app's own generated
 * snapshots, not arbitrary documents — the plugin reads them the same
 * way rather than linking a parser. */

static void extract_json_string(const char *json, const char *key, char *out,
				size_t out_size)
{
	out[0] = 0;

	char pattern[64];
	snprintf(pattern, sizeof(pattern), "\"%s\"", key);
	const char *p = strstr(json, pattern);
	if (!p)
		return;

	p = strchr(p + strlen(pattern), ':');
	if (!p)
		return;
	p++;
	while (*p == ' ' || *p == '\t')
		p++;
	if (*p != '"')
		return;
	p++;

	size_t i = 0;
	while (*p && *p != '"' && i + 1 < out_size) {
		if (*p == '\\' && p[1])
			p++;
		out[i++] = *p++;
	}
	out[i] = 0;
}

static bool extract_json_bool(const char *json, const char *key)
{
	char pattern[64];
	snprintf(pattern, sizeof(pattern), "\"%s\"", key);
	const char *p = strstr(json, pattern);
	if (!p)
		return false;

	p = strchr(p + strlen(pattern), ':');
	if (!p)
		return false;
	p++;
	while (*p == ' ' || *p == '\t')
		p++;
	return strncmp(p, "true", 4) == 0;
}

/* ------------------------------------------------------------------ */
/* Decoded frames. */

static void frame_sink(void *ud, AVFrame *frame)
{
	struct ios_camera_source *s = ud;

	if (nv12_publish_frame(s->conv, frame, s->queue)) {
		pthread_mutex_lock(&s->status_mutex);
		s->width = (uint32_t)frame->width;
		s->height = (uint32_t)frame->height;
		s->frames++;
		pthread_mutex_unlock(&s->status_mutex);
	}

	av_frame_free(&frame);
}

static bool ensure_decoder(struct ios_camera_source *s,
			   struct client_state *c)
{
	if (c->decoder)
		return true;

	c->decoder = h264_decoder_create(c->codec_id, s->cfg.allow_hw,
					 c->hw_retry);
	if (!c->decoder) {
		set_status(s, "%s", LL_STATUS_DECODER_FAILED);
		return false;
	}
	h264_decoder_set_frame_sink(c->decoder, frame_sink, s);
	c->packets_at_decoder = c->video_packets;
	blog(LOG_INFO, "[lenslink] decoder ready (%s)",
	     h264_decoder_hw_name(c->decoder));
	return true;
}

/* A hardware decoder that initializes is no proof it can decode this
 * stream: a driver can accept the codec and then emit nothing. Walk to
 * the next hardware API (and finally software) when that happens —
 * the same fallback the plugin does. */
static void decoder_fallback(struct ios_camera_source *s,
			     struct client_state *c)
{
	int failed_index = c->decoder ? h264_decoder_hw_index(c->decoder) : -1;
	h264_decoder_destroy(c->decoder);
	c->decoder = NULL;
	c->hw_retry = failed_index + 1;
	blog(LOG_WARNING, "[lenslink] decode failed, trying the next decoder");
	ensure_decoder(s, c);
}

/* ------------------------------------------------------------------ */

static bool handle_packet(struct ios_camera_source *s, struct client_state *c,
			  const struct obsc_header *hdr,
			  const uint8_t *payload)
{
	switch (hdr->type) {
	case OBSC_PKT_HELLO: {
		char json[512] = {0};
		size_t n = hdr->payload_size < sizeof(json) - 1
				   ? hdr->payload_size
				   : sizeof(json) - 1;
		memcpy(json, payload, n);
		extract_json_string(json, "name", c->name, sizeof(c->name));
		char kind[16] = {0};
		extract_json_string(json, "kind", kind, sizeof(kind));
		c->is_screen = strcmp(kind, "screen") == 0;
		c->standby = !c->is_screen &&
			     extract_json_bool(json, "standby");

		pthread_mutex_lock(&s->status_mutex);
		s->connected = true;
		s->is_screen = c->is_screen;
		s->standby = c->standby;
		snprintf(s->device_name, sizeof(s->device_name), "%s",
			 c->name);
		pthread_mutex_unlock(&s->status_mutex);

		blog(LOG_INFO, "[lenslink] connected: %s (%s%s)",
		     c->name[0] ? c->name : "(unnamed)",
		     c->is_screen ? "screen" : "camera",
		     c->standby ? ", standby" : "");

		/* The phone picks what it streams. A device configured for
		 * the camera never shows a screen broadcast and vice versa —
		 * same contract as the plugin's two source types. */
		if (c->is_screen != s->cfg.is_screen) {
			c->wrong_kind = true;
			set_status(s, "%s",
				   c->is_screen ? LL_STATUS_SCREEN_ON_CAMERA
						: LL_STATUS_CAMERA_ON_SCREEN);
			return false;
		}

		if (c->standby) {
			if (s->cfg.auto_start && s->auto_start_armed) {
				s->auto_start_armed = false;
				blog(LOG_INFO,
				     "[lenslink] app is idle — starting the "
				     "camera remotely");
				send_control_cmd(c,
						 "{\"cmd\":\"start_stream\"}");
				set_status(s, "%s", LL_STATUS_STARTING);
			} else {
				set_status(s, "%s", LL_STATUS_STANDBY);
			}
			break;
		}

		set_status(s, "%s %s", LL_STATUS_CONNECTED,
			   c->name[0] ? c->name : "iOS device");
		break;
	}
	case OBSC_PKT_VIDEO_CONFIG: {
		int log_len = hdr->payload_size < 256 ? (int)hdr->payload_size
						      : 256;
		blog(LOG_INFO, "[lenslink] video config: %.*s", log_len,
		     (const char *)payload);

		char json[512] = {0};
		size_t n = hdr->payload_size < sizeof(json) - 1
				   ? hdr->payload_size
				   : sizeof(json) - 1;
		memcpy(json, payload, n);

		char codec[32] = {0};
		extract_json_string(json, "codec", codec, sizeof(codec));

		if (c->standby) {
			c->standby = false;
			pthread_mutex_lock(&s->status_mutex);
			s->standby = false;
			pthread_mutex_unlock(&s->status_mutex);
			set_status(s, "%s %s", LL_STATUS_CONNECTED,
				   c->name[0] ? c->name : "iOS device");
		}

		enum AVCodecID id = strcmp(codec, "hevc") == 0
					    ? AV_CODEC_ID_HEVC
					    : AV_CODEC_ID_H264;
		/* A codec change means a whole new decoder; the same codec
		 * again (a format switch) keeps the one already walking the
		 * hardware fallback list. */
		if (c->decoder && id != c->codec_id) {
			h264_decoder_destroy(c->decoder);
			c->decoder = NULL;
			c->hw_retry = 0;
		}
		c->codec_id = id;
		ensure_decoder(s, c);
		break;
	}
	case OBSC_PKT_VIDEO: {
		c->video_packets++;
		if (!c->decoder && !ensure_decoder(s, c))
			break;
		if (!c->decoder)
			break;

		if (!h264_decoder_decode(c->decoder, NULL, payload,
					 hdr->payload_size, hdr->pts_ns))
			decoder_fallback(s, c);

		/* Latency: the frame's capture time is in the phone's clock,
		 * so it needs the measured offset before it means anything
		 * here. (docs/PROTOCOL.md, TIMESYNC.) */
		if (c->offset_valid && (hdr->flags & OBSC_FLAG_KEYFRAME) == 0)
			break;
		if (c->offset_valid) {
			int64_t local_capture =
				(int64_t)hdr->pts_ns - c->offset_ns;
			int64_t delta =
				(int64_t)os_gettime_ns() - local_capture;
			if (delta > 0 && delta < 2000000000LL) {
				c->lat_sum_ns += (uint64_t)delta;
				c->lat_count++;
			}
		}
		break;
	}
	case OBSC_PKT_TIMESYNC_RESP: {
		if (hdr->payload_size < 8)
			break;
		uint64_t t1 = obsc_read_u64(payload);
		uint64_t t2 = hdr->pts_ns;
		uint64_t t3 = os_gettime_ns();
		if (t3 < t1)
			break;
		/* offset = t2 - (t1 + t3)/2, error bounded by rtt/2. */
		c->offset_ns = (int64_t)t2 - (int64_t)((t1 + t3) / 2);
		c->offset_valid = true;
		break;
	}
	case OBSC_PKT_STATE: {
		size_t n = hdr->payload_size < sizeof(s->device_state) - 1
				   ? hdr->payload_size
				   : sizeof(s->device_state) - 1;
		pthread_mutex_lock(&s->status_mutex);
		memcpy(s->device_state, payload, n);
		s->device_state[n] = 0;
		pthread_mutex_unlock(&s->status_mutex);
		break;
	}
	case OBSC_PKT_DIAG: {
		int len = hdr->payload_size < 512 ? (int)hdr->payload_size
						  : 512;
		blog(LOG_INFO, "[lenslink] device: %.*s", len,
		     (const char *)payload);
		break;
	}
	case OBSC_PKT_PING:
	case OBSC_PKT_AUDIO:
	case OBSC_PKT_SCREEN_AUDIO:
	case OBSC_PKT_REQUEST:
		/* Audio is deliberately dropped: a virtual camera carries no
		 * audio track, and the lip-sync reference has nothing to
		 * calibrate against here. docs/DRIVERLESS.md explains why. */
		break;
	default:
		break;
	}

	return true;
}

static bool client_read(struct ios_camera_source *s, struct client_state *c)
{
	recv_buf_reserve(&c->buf, RECV_CHUNK);
	int n = (int)recv(c->sock, (char *)c->buf.data + c->buf.len,
			  RECV_CHUNK, 0);
	if (n == 0) {
		blog(LOG_INFO, "[lenslink] connection closed by device");
		return false;
	}
	if (n < 0) {
		blog(LOG_INFO, "[lenslink] recv error %d", net_last_error());
		return false;
	}
	c->buf.len += (size_t)n;

	size_t off = 0;
	bool ok = true;
	while (c->buf.len - off >= OBSC_HEADER_SIZE) {
		struct obsc_header hdr;
		if (!obsc_parse_header(c->buf.data + off, &hdr)) {
			blog(LOG_WARNING,
			     "[lenslink] bad packet header, dropping client");
			ok = false;
			break;
		}

		size_t total = OBSC_HEADER_SIZE + hdr.payload_size;
		if (c->buf.len - off < total)
			break;

		if (!handle_packet(s, c, &hdr,
				   c->buf.data + off + OBSC_HEADER_SIZE)) {
			ok = false;
			break;
		}

		off += total;
	}

	recv_buf_consume(&c->buf, off);
	return ok;
}

/* ------------------------------------------------------------------ */
/* Per-connection maintenance, all on the dial thread. */

static void latency_tick(struct ios_camera_source *s, struct client_state *c)
{
	uint64_t now = os_gettime_ns();

	if (now - c->last_sync_send > 1000000000ULL) {
		c->last_sync_send = now;
		uint8_t hdr[OBSC_HEADER_SIZE];
		obsc_build_header(hdr, OBSC_PKT_TIMESYNC_REQ, 0, now, 0);
		client_send(c, hdr, OBSC_HEADER_SIZE);
	}

	if (!c->lat_window_start)
		c->lat_window_start = now;

	if (c->lat_count && now - c->lat_window_start > 5000000000ULL) {
		unsigned avg_ms =
			(unsigned)(c->lat_sum_ns / c->lat_count / 1000000);
		pthread_mutex_lock(&s->status_mutex);
		s->latency_ms = avg_ms;
		pthread_mutex_unlock(&s->status_mutex);
		set_status(s, "%s %s — ~%u ms", LL_STATUS_CONNECTED,
			   c->name[0] ? c->name : "iOS device", avg_ms);
		c->lat_sum_ns = 0;
		c->lat_count = 0;
		c->lat_window_start = now;
	}
}

static void control_tick(struct ios_camera_source *s, struct client_state *c)
{
	char pending[CONTROL_QUEUE_MAX][512];
	size_t count = 0;

	pthread_mutex_lock(&s->control_mutex);
	count = s->control_count;
	for (size_t i = 0; i < count; i++)
		memcpy(pending[i], s->control_queue[i], sizeof(pending[i]));
	s->control_count = 0;
	pthread_mutex_unlock(&s->control_mutex);

	for (size_t i = 0; i < count; i++)
		send_control_cmd(c, pending[i]);
}

static void client_disconnect(struct ios_camera_source *s,
			      struct client_state *c)
{
	h264_decoder_destroy(c->decoder);
	recv_buf_free(&c->buf);
	send_buf_free(&c->out);
	net_close(c->sock);

	pthread_mutex_lock(&s->status_mutex);
	s->connected = false;
	s->standby = false;
	s->width = 0;
	s->height = 0;
	s->latency_ms = 0;
	s->device_state[0] = 0;
	pthread_mutex_unlock(&s->status_mutex);
}

/* ------------------------------------------------------------------ */

static void sleep_ms_interruptible(struct ios_camera_source *s, int total_ms)
{
	for (int slept = 0; slept < total_ms && !s->stop; slept += 50)
		os_sleep_ms(50);
}

static socket_t tcp_dial(const char *host, uint16_t port, volatile bool *stop)
{
	struct sockaddr_in addr = {0};
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);

	/* Numeric IP is the normal case (the app shows one), and it skips
	 * getaddrinfo, whose DNS timeout cannot be interrupted. */
	if (inet_pton(AF_INET, host, &addr.sin_addr) != 1) {
		char port_str[16];
		snprintf(port_str, sizeof(port_str), "%u", (unsigned)port);
		struct addrinfo hints = {0};
		struct addrinfo *res = NULL;
		hints.ai_family = AF_INET;
		hints.ai_socktype = SOCK_STREAM;
		if (getaddrinfo(host, port_str, &hints, &res) != 0 || !res)
			return OBSC_INVALID_SOCKET;
		memcpy(&addr, res->ai_addr, sizeof(addr));
		addr.sin_port = htons(port);
		freeaddrinfo(res);
	}

	socket_t s = socket(AF_INET, SOCK_STREAM, 0);
	if (s == OBSC_INVALID_SOCKET)
		return OBSC_INVALID_SOCKET;

	net_set_nonblocking(s);
	int ret = connect(s, (struct sockaddr *)&addr, sizeof(addr));

	if (ret != 0) {
#ifdef _WIN32
		if (WSAGetLastError() != WSAEWOULDBLOCK)
			goto fail;
#else
		if (errno != EINPROGRESS)
			goto fail;
#endif
		bool writable = false;
		for (int i = 0; i < 30 && !(stop && *stop); i++) {
			int r = net_wait(s, NET_WAIT_WRITE, 100);
			if (r < 0)
				goto fail;
			if (r & NET_WAIT_WRITE) {
				writable = true;
				break;
			}
		}
		if (!writable)
			goto fail;

		int err = 0;
		socklen_t len = sizeof(err);
		getsockopt(s, SOL_SOCKET, SO_ERROR, (char *)&err, &len);
		if (err != 0)
			goto fail;
	}

	int yes = 1;
	setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char *)&yes,
		   sizeof(yes));
	return s;

fail:
	net_close(s);
	return OBSC_INVALID_SOCKET;
}

static socket_t dial_usb(struct ios_camera_source *s)
{
	struct usbmux_device devs[16];
	int n = usbmux_list_devices(devs, 16);
	const char *pinned = s->cfg.usb_udid;

	int chosen = -1;
	for (int i = 0; i < n; i++) {
		if (pinned[0] && strcmp(pinned, devs[i].udid) != 0)
			continue;
		chosen = i;
		break;
	}

	if (chosen < 0) {
		set_status(s, "%s",
			   pinned[0] ? LL_STATUS_WAITING_PINNED
				     : LL_STATUS_WAITING_USB);
		return OBSC_INVALID_SOCKET;
	}

	set_status(s, "%s", LL_STATUS_USB_FOUND);
	return usbmux_connect_device(devs[chosen].id, OBSC_USB_PORT);
}

static void dial_loop(struct ios_camera_source *s)
{
	while (!s->stop) {
		socket_t sock = OBSC_INVALID_SOCKET;

		if (s->cfg.mode == BRIDGE_CONN_USB) {
			sock = dial_usb(s);
		} else if (!s->cfg.host[0]) {
			set_status(s, "%s", LL_STATUS_NO_HOST);
			sleep_ms_interruptible(s, 2000);
			continue;
		} else {
			uint16_t port = s->cfg.port ? s->cfg.port
						    : OBSC_USB_PORT;
			set_status(s, "%s %s", LL_STATUS_DIALING, s->cfg.host);
			sock = tcp_dial(s->cfg.host, port, &s->stop);
		}

		if (sock == OBSC_INVALID_SOCKET) {
			/* Two consecutive failures, not one, before re-arming
			 * auto-start: a blip right after the user pressed Stop
			 * on the phone must not bounce it back into
			 * streaming. */
			if (++s->dial_failures >= 2)
				s->auto_start_armed = true;
			sleep_ms_interruptible(s, 2000);
			continue;
		}

		s->dial_failures = 0;
		blog(LOG_INFO, "[lenslink] connected to device (%s)",
		     s->cfg.mode == BRIDGE_CONN_USB ? "USB" : "network");

		struct client_state client = {.sock = sock};

		while (!s->stop) {
			int events = NET_WAIT_READ;
			if (client.out.len > 0)
				events |= NET_WAIT_WRITE;
			int ret = net_wait(sock, events, 200);
			if (ret < 0)
				break;
			if (client.out.len > 0)
				client_flush(&client);
			latency_tick(s, &client);
			control_tick(s, &client);
			if (client.out.failed)
				break;
			if ((ret & NET_WAIT_READ) && !client_read(s, &client))
				break;
		}

		bool wrong_kind = client.wrong_kind;
		blog(LOG_INFO, "[lenslink] device connection ended");
		client_disconnect(s, &client);

		if (!s->stop && !wrong_kind)
			set_status(s, "%s", LL_STATUS_DISCONNECTED);

		/* The phone keeps offering the same stream, so an immediate
		 * redial would spin a reject loop at LAN speed. */
		if (wrong_kind)
			sleep_ms_interruptible(s, 3000);
	}
}

static void *dial_thread(void *data)
{
	struct ios_camera_source *s = data;
	os_set_thread_name("lenslink-dial");
	dial_loop(s);
	return NULL;
}

/* ------------------------------------------------------------------ */
/* Lifecycle. */

struct ios_camera_source *
bridge_device_create(const struct bridge_device_config *cfg,
		     struct frame_queue *queue)
{
	struct ios_camera_source *s = bzalloc(sizeof(*s));
	s->cfg = *cfg;
	s->queue = queue;
	s->conv = nv12_converter_create();
	if (!s->conv) {
		bfree(s);
		return NULL;
	}
	pthread_mutex_init(&s->status_mutex, NULL);
	pthread_mutex_init(&s->control_mutex, NULL);
	s->auto_start_armed = true;
	snprintf(s->status, sizeof(s->status), "%s", LL_STATUS_DISCONNECTED);
	return s;
}

void bridge_device_start(struct ios_camera_source *s)
{
	if (s->thread_active)
		return;
	s->stop = false;
	if (pthread_create(&s->thread, NULL, dial_thread, s) == 0)
		s->thread_active = true;
	else
		blog(LOG_ERROR, "[lenslink] failed to start the dial thread");
}

void bridge_device_stop(struct ios_camera_source *s)
{
	if (!s->thread_active)
		return;
	s->stop = true;
	pthread_join(s->thread, NULL);
	s->thread_active = false;
}

void bridge_device_destroy(struct ios_camera_source *s)
{
	if (!s)
		return;
	bridge_device_stop(s);
	nv12_converter_destroy(s->conv);
	pthread_mutex_destroy(&s->status_mutex);
	pthread_mutex_destroy(&s->control_mutex);
	bfree(s);
}

void bridge_device_stats(struct ios_camera_source *s, uint32_t *width,
			 uint32_t *height, unsigned *latency_ms,
			 uint64_t *frames)
{
	pthread_mutex_lock(&s->status_mutex);
	if (width)
		*width = s->width;
	if (height)
		*height = s->height;
	if (latency_ms)
		*latency_ms = s->latency_ms;
	if (frames)
		*frames = s->frames;
	pthread_mutex_unlock(&s->status_mutex);
}

/* ------------------------------------------------------------------ */
/* The upcalls web-control.c makes (declared in web-control.h). Same
 * contract as the plugin's: safe from the web thread, and the caller
 * holds the registry lock so a device cannot be destroyed underneath
 * one of these. */

void ios_camera_enqueue_control(struct ios_camera_source *s, const char *json,
				size_t len)
{
	if (len >= sizeof(s->control_queue[0]))
		return;

	pthread_mutex_lock(&s->control_mutex);
	if (s->control_count < CONTROL_QUEUE_MAX) {
		memcpy(s->control_queue[s->control_count], json, len);
		s->control_queue[s->control_count][len] = 0;
		s->control_count++;
	}
	pthread_mutex_unlock(&s->control_mutex);
}

void ios_camera_copy_status(struct ios_camera_source *s, char *buf, size_t size)
{
	pthread_mutex_lock(&s->status_mutex);
	snprintf(buf, size, "%s", s->status);
	pthread_mutex_unlock(&s->status_mutex);
}

void ios_camera_copy_state(struct ios_camera_source *s, char *buf, size_t size)
{
	pthread_mutex_lock(&s->status_mutex);
	snprintf(buf, size, "%s",
		 s->device_state[0] ? s->device_state : "{}");
	pthread_mutex_unlock(&s->status_mutex);
}

void ios_camera_copy_name(struct ios_camera_source *s, char *buf, size_t size)
{
	pthread_mutex_lock(&s->status_mutex);
	snprintf(buf, size, "%s", s->cfg.name);
	pthread_mutex_unlock(&s->status_mutex);
}

bool ios_camera_is_screen(struct ios_camera_source *s)
{
	return s->cfg.is_screen;
}

bool ios_camera_is_standby(struct ios_camera_source *s)
{
	pthread_mutex_lock(&s->status_mutex);
	bool standby = s->standby;
	pthread_mutex_unlock(&s->status_mutex);
	return standby;
}

bool ios_camera_is_connected(struct ios_camera_source *s)
{
	pthread_mutex_lock(&s->status_mutex);
	bool connected = s->connected;
	pthread_mutex_unlock(&s->status_mutex);
	return connected;
}

bool ios_camera_auto_start(struct ios_camera_source *s)
{
	return s->cfg.auto_start;
}

void ios_camera_set_auto_start(struct ios_camera_source *s, bool on)
{
	s->cfg.auto_start = on;
}

/* Lip-sync calibration is an OBS-only feature — there is no second
 * audio device here to align against. The panel reads "off" and hides
 * the row (docs/UI_DESIGN.md). */
const char *ios_camera_sync_state(struct ios_camera_source *s)
{
	(void)s;
	return "off";
}

void ios_camera_recalibrate(struct ios_camera_source *s)
{
	(void)s;
}
