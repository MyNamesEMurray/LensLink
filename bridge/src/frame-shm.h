/*
 * The bridge -> virtual-camera-filter hand-off, across process
 * boundaries.
 *
 * A DirectShow filter is a COM object that the *consuming* app loads
 * into its own process: Zoom instantiates lenslink-vcam.dll inside
 * Zoom. So the thing that dials the phone and the thing that feeds the
 * camera cannot be the same process, and frames have to cross. This is
 * that crossing: one named file mapping holding a small header and two
 * NV12 slots.
 *
 * Included by BOTH sides — the bridge (C) and the filter DLL (C++) — so
 * the layout is defined exactly once. Every field is fixed-width and
 * naturally aligned, and there is a size assertion at the bottom: a
 * silent layout mismatch here would be a very unpleasant bug to chase.
 *
 * Synchronisation is a seqlock, not a mutex: the writer must never be
 * blocked by a reader (docs/PERFORMANCE.md's drop-don't-queue rule), and
 * a reader that loses a race simply retries and gets the newer frame,
 * which is what it wanted anyway. A reader that crashes mid-read cannot
 * wedge the writer, which a shared mutex would allow.
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Bump when the layout changes. Mismatched sides refuse to talk rather
 * than misinterpret each other's bytes. */
#define LLSHM_VERSION 1
#define LLSHM_MAGIC 0x4C4C4E4Bu /* "LLNK" */

/* The mapping is sized for this ceiling and never resized, so a format
 * change costs nothing and a reader never re-opens. 1080p is also the
 * ceiling the filter advertises: a virtual camera that offers 4K to a
 * video-call app mostly gets it downscaled again at a cost nobody
 * wanted. Larger phone streams are scaled down by the bridge. */
#define LLSHM_MAX_WIDTH 1920u
#define LLSHM_MAX_HEIGHT 1080u
#define LLSHM_SLOT_BYTES ((size_t)LLSHM_MAX_WIDTH * LLSHM_MAX_HEIGHT * 3 / 2)
#define LLSHM_SLOTS 2

/* Session-local: both processes run as the same user in the same
 * session, so this needs no privileges and cannot collide with another
 * user's bridge on a shared machine. */
#define LLSHM_MAPPING_NAME L"Local\\LensLinkVCam_v1"

/* A side is considered gone once its heartbeat is this stale. */
#define LLSHM_STALE_NS (2ull * 1000000000ull)

struct llshm_header {
	/* 8-byte fields first, so the layout is identical under any
	 * reasonable alignment rule on either compiler. */
	uint64_t sequence;      /* odd = publish in flight (seqlock) */
	uint64_t pts_ns;
	uint64_t writer_heartbeat_ns;
	uint64_t reader_heartbeat_ns;

	uint32_t magic;
	uint32_t version;
	uint32_t slot_bytes;    /* capacity of each slot */
	uint32_t active_slot;   /* which slot holds the latest full frame */
	uint32_t width;         /* of the frame in the active slot */
	uint32_t height;

	/* Reader -> writer. The filter publishes the format its pin
	 * negotiated; the bridge scales to it. Zero means "not yet
	 * negotiated", and the bridge then publishes the phone's own
	 * size. */
	uint32_t want_width;
	uint32_t want_height;
	uint32_t want_fps;

	uint32_t reserved;      /* keeps the header 8-byte aligned */
};

/* Frame data starts here, LLSHM_SLOTS slots of LLSHM_SLOT_BYTES each.
 * Comfortably past the header, and a round number so a future field
 * costs nothing: the assertion below is what actually enforces it. */
#define LLSHM_DATA_OFFSET 128u
#define LLSHM_TOTAL_BYTES (LLSHM_DATA_OFFSET + LLSHM_SLOT_BYTES * LLSHM_SLOTS)

#ifdef __cplusplus
extern "C" {
#endif

/* Both sides must agree byte for byte, so prove it at compile time. */
typedef char llshm_header_size_check
	[(sizeof(struct llshm_header) <= LLSHM_DATA_OFFSET) ? 1 : -1];

struct llshm;

/*
 * open_write: the bridge. Creates the mapping (or attaches to an
 * existing one) and becomes the writer.
 * open_read: the filter DLL. Attaches only if a writer has made one;
 * returns NULL when the bridge isn't running, which is the filter's cue
 * to emit its "no signal" frame.
 */
struct llshm *llshm_open_write(void);
struct llshm *llshm_open_read(void);
void llshm_close(struct llshm *shm);

/* Writer: copies one packed NV12 frame into the inactive slot and
 * publishes it. Frames larger than the ceiling are rejected (the caller
 * scales first). */
bool llshm_publish(struct llshm *shm, const uint8_t *nv12, uint32_t width,
		   uint32_t height, uint64_t pts_ns);

/*
 * Reader: copies the newest frame out. `dst_size` must be at least
 * width*height*3/2 for the current dimensions — call with dst NULL to
 * learn them first. Returns false when no frame is available, the
 * writer is stale, or the copy kept losing the seqlock race.
 */
bool llshm_read(struct llshm *shm, uint8_t *dst, size_t dst_size,
		uint32_t *width, uint32_t *height, uint64_t *pts_ns);

/* Reader: announce the negotiated capture format, and stay alive. Both
 * are cheap enough to call once per delivered frame. */
void llshm_set_wanted_format(struct llshm *shm, uint32_t width,
			     uint32_t height, uint32_t fps);
void llshm_reader_heartbeat(struct llshm *shm);

/* Writer: what the reader asked for (zeroes when nothing has), and
 * whether a reader is currently attached — the honest driverless
 * equivalent of a tally light ("an app has the camera open"). */
void llshm_get_wanted_format(struct llshm *shm, uint32_t *width,
			     uint32_t *height, uint32_t *fps);
bool llshm_reader_present(struct llshm *shm);

#ifdef __cplusplus
}
#endif
