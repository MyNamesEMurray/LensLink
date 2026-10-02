/* Packet header framing (protocol.h) against docs/PROTOCOL.md. */

#include "protocol.h"
#include "test.h"

static void test_packet_types(void)
{
	/* The numbers are the wire format, hand-mirrored in the app's
	 * Protocol.swift: renumbering one breaks every phone in the field. */
	CHECK(OBSC_PKT_HELLO == 1);
	CHECK(OBSC_PKT_VIDEO_CONFIG == 2);
	CHECK(OBSC_PKT_VIDEO == 3);
	CHECK(OBSC_PKT_PING == 4);
	CHECK(OBSC_PKT_TIMESYNC_REQ == 5);
	CHECK(OBSC_PKT_TIMESYNC_RESP == 6);
	CHECK(OBSC_PKT_CONTROL == 7);
	CHECK(OBSC_PKT_STATE == 8);
	CHECK(OBSC_PKT_AUDIO == 9);
	CHECK(OBSC_PKT_SCREEN_AUDIO == 10);
	CHECK(OBSC_PKT_DIAG == 11);
	CHECK(OBSC_PKT_REQUEST == 12);
	CHECK(OBSC_HEADER_SIZE == 20);
	CHECK(OBSC_USB_PORT == 9979);
}

static void test_build_layout(void)
{
	uint8_t buf[OBSC_HEADER_SIZE];
	obsc_build_header(buf, OBSC_PKT_VIDEO, OBSC_FLAG_KEYFRAME,
			  0x0102030405060708ull, 0x00A1B2C3u);

	static const uint8_t want[OBSC_HEADER_SIZE] = {
		'O',  'B',  'S',  'C',  1,    3,    0x00, 0x01, 0x01, 0x02,
		0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x00, 0xA1, 0xB2, 0xC3,
	};
	CHECK(memcmp(buf, want, sizeof(want)) == 0);
}

static void test_round_trip(void)
{
	uint8_t buf[OBSC_HEADER_SIZE];
	struct obsc_header hdr;

	obsc_build_header(buf, OBSC_PKT_TIMESYNC_RESP, 0xBEEF,
			  0xFEDCBA9876543210ull, OBSC_MAX_PAYLOAD);
	CHECK(obsc_parse_header(buf, &hdr));
	CHECK(hdr.version == OBSC_PROTOCOL_VERSION);
	CHECK(hdr.type == OBSC_PKT_TIMESYNC_RESP);
	CHECK(hdr.flags == 0xBEEF);
	CHECK(hdr.pts_ns == 0xFEDCBA9876543210ull);
	CHECK(hdr.payload_size == OBSC_MAX_PAYLOAD);

	obsc_build_header(buf, OBSC_PKT_HELLO, 0, 0, 0);
	CHECK(obsc_parse_header(buf, &hdr));
	CHECK(hdr.type == OBSC_PKT_HELLO && hdr.payload_size == 0);

	/* Unknown types parse: the dial loop skips them by size, which is
	 * what keeps new packet types backwards-compatible. */
	obsc_build_header(buf, 200, 0, 1, 5);
	CHECK(obsc_parse_header(buf, &hdr) && hdr.type == 200);
}

static void test_rejects(void)
{
	uint8_t buf[OBSC_HEADER_SIZE];
	struct obsc_header hdr;

	obsc_build_header(buf, OBSC_PKT_VIDEO, 0, 0, 16);
	buf[3] = 'X';
	CHECK(!obsc_parse_header(buf, &hdr));

	obsc_build_header(buf, OBSC_PKT_VIDEO, 0, 0, 16);
	buf[4] = OBSC_PROTOCOL_VERSION + 1;
	CHECK(!obsc_parse_header(buf, &hdr));
	buf[4] = 0;
	CHECK(!obsc_parse_header(buf, &hdr));

	obsc_build_header(buf, OBSC_PKT_VIDEO, 0, 0, OBSC_MAX_PAYLOAD + 1);
	CHECK(!obsc_parse_header(buf, &hdr));
	obsc_build_header(buf, OBSC_PKT_VIDEO, 0, 0, 0xFFFFFFFFu);
	CHECK(!obsc_parse_header(buf, &hdr));
}

int main(void)
{
	test_packet_types();
	test_build_layout();
	test_round_trip();
	test_rejects();
	TEST_MAIN_END();
}
