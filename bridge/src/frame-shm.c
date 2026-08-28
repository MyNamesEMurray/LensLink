/*
 * Windows implementation of the cross-process frame hand-off.
 * See frame-shm.h for the layout and why it is a seqlock.
 *
 * Compiled into both the bridge and the filter DLL.
 */

#ifdef _WIN32

#include <windows.h>

#include <string.h>
#include <stdlib.h>

#include "frame-shm.h"

struct llshm {
	HANDLE mapping;
	struct llshm_header *header;
	uint8_t *slots[LLSHM_SLOTS];
	bool writer;
};

/* Same clock on both sides: QPC is system-wide, so a timestamp written
 * by the bridge is directly comparable in the filter's process. */
static uint64_t now_ns(void)
{
	static LARGE_INTEGER freq;
	if (!freq.QuadPart)
		QueryPerformanceFrequency(&freq);
	LARGE_INTEGER count;
	QueryPerformanceCounter(&count);
	return (uint64_t)(count.QuadPart / freq.QuadPart) * 1000000000ull +
	       (uint64_t)(count.QuadPart % freq.QuadPart) * 1000000000ull /
		       (uint64_t)freq.QuadPart;
}

static void map_slots(struct llshm *shm)
{
	uint8_t *base = (uint8_t *)shm->header;
	for (int i = 0; i < LLSHM_SLOTS; i++)
		shm->slots[i] = base + LLSHM_DATA_OFFSET +
				(size_t)i * LLSHM_SLOT_BYTES;
}

static struct llshm *open_common(bool writer)
{
	struct llshm *shm = calloc(1, sizeof(*shm));
	if (!shm)
		return NULL;

	if (writer) {
		shm->mapping = CreateFileMappingW(
			INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0,
			(DWORD)LLSHM_TOTAL_BYTES, LLSHM_MAPPING_NAME);
	} else {
		shm->mapping = OpenFileMappingW(FILE_MAP_ALL_ACCESS, FALSE,
						LLSHM_MAPPING_NAME);
	}
	if (!shm->mapping) {
		free(shm);
		return NULL;
	}

	bool existed = writer && GetLastError() == ERROR_ALREADY_EXISTS;

	shm->header = (struct llshm_header *)MapViewOfFile(
		shm->mapping, FILE_MAP_ALL_ACCESS, 0, 0, LLSHM_TOTAL_BYTES);
	if (!shm->header) {
		CloseHandle(shm->mapping);
		free(shm);
		return NULL;
	}

	map_slots(shm);
	shm->writer = writer;

	if (writer) {
		/* A fresh mapping is already zeroed; an inherited one may
		 * hold a previous bridge's state, so reset everything the
		 * writer owns and leave the reader's fields alone. */
		if (!existed)
			memset(shm->header, 0, sizeof(*shm->header));
		shm->header->sequence = 0;
		shm->header->active_slot = 0;
		shm->header->width = 0;
		shm->header->height = 0;
		shm->header->slot_bytes = (uint32_t)LLSHM_SLOT_BYTES;
		shm->header->version = LLSHM_VERSION;
		shm->header->writer_heartbeat_ns = now_ns();
		/* Magic last: it is what tells a reader the rest is
		 * meaningful. */
		shm->header->magic = LLSHM_MAGIC;
	} else if (shm->header->magic != LLSHM_MAGIC ||
		   shm->header->version != LLSHM_VERSION) {
		/* A bridge from a different build owns this mapping.
		 * Refusing beats misreading its bytes. */
		UnmapViewOfFile(shm->header);
		CloseHandle(shm->mapping);
		free(shm);
		return NULL;
	}

	return shm;
}

struct llshm *llshm_open_write(void)
{
	return open_common(true);
}

struct llshm *llshm_open_read(void)
{
	return open_common(false);
}

void llshm_close(struct llshm *shm)
{
	if (!shm)
		return;
	if (shm->writer && shm->header) {
		/* Stop claiming to be live: a reader that outlives the
		 * bridge must fall back to its no-signal frame promptly. */
		shm->header->magic = 0;
		shm->header->writer_heartbeat_ns = 0;
	}
	if (shm->header)
		UnmapViewOfFile(shm->header);
	if (shm->mapping)
		CloseHandle(shm->mapping);
	free(shm);
}

bool llshm_publish(struct llshm *shm, const uint8_t *nv12, uint32_t width,
		   uint32_t height, uint64_t pts_ns)
{
	if (!shm || !shm->writer || !nv12)
		return false;
	if (width > LLSHM_MAX_WIDTH || height > LLSHM_MAX_HEIGHT || !width ||
	    !height)
		return false;

	size_t size = (size_t)width * height * 3 / 2;
	struct llshm_header *h = shm->header;
	uint32_t slot = h->active_slot ^ 1u;

	memcpy(shm->slots[slot], nv12, size);

	/* Seqlock publish: odd sequence marks the window in which the
	 * header fields are inconsistent. The barriers keep the compiler
	 * and the CPU from hoisting the field writes out of it. */
	h->sequence++;
	MemoryBarrier();
	h->active_slot = slot;
	h->width = width;
	h->height = height;
	h->pts_ns = pts_ns;
	h->writer_heartbeat_ns = now_ns();
	MemoryBarrier();
	h->sequence++;

	return true;
}

bool llshm_read(struct llshm *shm, uint8_t *dst, size_t dst_size,
		uint32_t *width, uint32_t *height, uint64_t *pts_ns)
{
	if (!shm)
		return false;

	struct llshm_header *h = shm->header;
	if (h->magic != LLSHM_MAGIC)
		return false;

	uint64_t heartbeat = h->writer_heartbeat_ns;
	if (!heartbeat || now_ns() - heartbeat > LLSHM_STALE_NS)
		return false;

	/* Three attempts: each retry means the writer published mid-read,
	 * so a third failure is a writer running far faster than this
	 * reader, and the caller is better served by its previous frame
	 * than by spinning. */
	for (int attempt = 0; attempt < 3; attempt++) {
		uint64_t before = h->sequence;
		if (before & 1u)
			continue; /* publish in flight */

		MemoryBarrier();
		uint32_t slot = h->active_slot;
		uint32_t w = h->width;
		uint32_t hgt = h->height;
		uint64_t pts = h->pts_ns;

		if (!w || !hgt || slot >= LLSHM_SLOTS)
			return false;

		size_t size = (size_t)w * hgt * 3 / 2;
		if (dst) {
			if (dst_size < size)
				return false;
			memcpy(dst, shm->slots[slot], size);
		}

		MemoryBarrier();
		if (h->sequence != before)
			continue; /* torn: the frame moved under us */

		if (width)
			*width = w;
		if (height)
			*height = hgt;
		if (pts_ns)
			*pts_ns = pts;
		return true;
	}

	return false;
}

void llshm_set_wanted_format(struct llshm *shm, uint32_t width,
			     uint32_t height, uint32_t fps)
{
	if (!shm)
		return;
	shm->header->want_width = width;
	shm->header->want_height = height;
	shm->header->want_fps = fps;
}

void llshm_reader_heartbeat(struct llshm *shm)
{
	if (shm)
		shm->header->reader_heartbeat_ns = now_ns();
}

void llshm_get_wanted_format(struct llshm *shm, uint32_t *width,
			     uint32_t *height, uint32_t *fps)
{
	if (!shm)
		return;
	if (width)
		*width = shm->header->want_width;
	if (height)
		*height = shm->header->want_height;
	if (fps)
		*fps = shm->header->want_fps;
}

bool llshm_reader_present(struct llshm *shm)
{
	if (!shm)
		return false;
	uint64_t beat = shm->header->reader_heartbeat_ns;
	return beat && now_ns() - beat < LLSHM_STALE_NS;
}

#endif /* _WIN32 */
