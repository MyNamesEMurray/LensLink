/*
 * The picture OBS shows while the phone is holding a stream.
 *
 * A paused stream sends no frames, and an async source keeps whatever it
 * had — so without this a pause looks exactly like a stall: the same
 * frozen picture, no explanation. Instead the source hands the last
 * frame's thumbnail (h264-decoder.c keeps one, sampled sparsely) to this
 * file, which blows it back up to frame size. Upscaling 64x36 is where
 * the blur comes from: no filter kernel, no per-frame cost, and the
 * result reads as "deliberately obscured" rather than "broken". Grey,
 * because a paused picture should not look like live colour, and a pause
 * glyph on top so it reads at a glance from across a room.
 *
 * Output is Y800 (luma only), so none of this touches chroma planes or
 * cares which pixel format the stream itself uses.
 */

#include "paused-still.h"

#include <obs-module.h>
#include <util/bmem.h>
#include <util/platform.h>

#include <string.h>

/* How far the still is pulled down from the live picture's brightness.
 * Dim enough to read as inactive, bright enough to still show what the
 * camera is pointed at. */
#define STILL_DIM_NUMERATOR 9
#define STILL_DIM_DENOMINATOR 20

/* Pause glyph geometry, as fractions of the shorter frame edge. */
#define GLYPH_HEIGHT_DIV 4 /* bar height = min(w,h) / 4 */
#define GLYPH_BAR_DIV 14   /* bar width  = min(w,h) / 14 */
#define GLYPH_GAP_DIV 22   /* gap        = min(w,h) / 22 */

/* Bilinear sample of the thumbnail at normalized (fx, fy), in 16.16
 * fixed point so this stays integer-only. */
static inline uint8_t thumb_bilinear(const uint8_t *thumb, uint32_t fx,
				     uint32_t fy)
{
	uint32_t x = fx >> 16;
	uint32_t y = fy >> 16;
	uint32_t x1 = x + 1 < (uint32_t)LENSLINK_THUMB_W ? x + 1 : x;
	uint32_t y1 = y + 1 < (uint32_t)LENSLINK_THUMB_H ? y + 1 : y;
	uint32_t dx = fx & 0xFFFF;
	uint32_t dy = fy & 0xFFFF;

	const uint8_t *row0 = thumb + (size_t)y * LENSLINK_THUMB_W;
	const uint8_t *row1 = thumb + (size_t)y1 * LENSLINK_THUMB_W;
	uint32_t top = ((uint32_t)row0[x] * (0x10000 - dx) +
			(uint32_t)row0[x1] * dx) >>
		       16;
	uint32_t bottom = ((uint32_t)row1[x] * (0x10000 - dx) +
			   (uint32_t)row1[x1] * dx) >>
			  16;
	return (uint8_t)((top * (0x10000 - dy) + bottom * dy) >> 16);
}

/* Two bars, centred, with a dark halo so they hold up over a light or a
 * dark picture without needing to know which it is. */
static void draw_pause_glyph(uint8_t *luma, int width, int height)
{
	const int shorter = width < height ? width : height;
	const int bar_h = shorter / GLYPH_HEIGHT_DIV;
	const int bar_w = shorter / GLYPH_BAR_DIV;
	const int gap = shorter / GLYPH_GAP_DIV;
	if (bar_h <= 0 || bar_w <= 0)
		return;

	const int halo = bar_w / 6 > 0 ? bar_w / 6 : 1;
	const int top = (height - bar_h) / 2;
	const int left = (width - (bar_w * 2 + gap)) / 2;
	const int bar_x[2] = {left, left + bar_w + gap};

	for (int b = 0; b < 2; b++) {
		const int x0 = bar_x[b] - halo;
		const int x1 = bar_x[b] + bar_w + halo;
		const int y0 = top - halo;
		const int y1 = top + bar_h + halo;
		for (int y = y0; y < y1; y++) {
			if (y < 0 || y >= height)
				continue;
			uint8_t *row = luma + (size_t)y * width;
			const bool inner_y = y >= top && y < top + bar_h;
			for (int x = x0; x < x1; x++) {
				if (x < 0 || x >= width)
					continue;
				const bool inner =
					inner_y && x >= bar_x[b] &&
					x < bar_x[b] + bar_w;
				row[x] = inner ? 235 : 16;
			}
		}
	}
}

bool lenslink_paused_still_output(obs_source_t *source, const uint8_t *thumb,
				  int width, int height, uint64_t timestamp)
{
	if (!source || !thumb || width <= 0 || height <= 0)
		return false;
	/* Guards the multiply below and keeps a corrupt VIDEO_CONFIG from
	 * asking for a gigabyte of scratch. */
	if (width > 8192 || height > 8192)
		return false;

	const size_t pixels = (size_t)width * (size_t)height;
	uint8_t *luma = bmalloc(pixels);
	if (!luma)
		return false;

	const uint32_t step_x =
		(uint32_t)(((uint64_t)(LENSLINK_THUMB_W - 1) << 16) / width);
	const uint32_t step_y =
		(uint32_t)(((uint64_t)(LENSLINK_THUMB_H - 1) << 16) / height);

	uint32_t fy = 0;
	for (int y = 0; y < height; y++, fy += step_y) {
		uint8_t *row = luma + (size_t)y * width;
		uint32_t fx = 0;
		for (int x = 0; x < width; x++, fx += step_x) {
			uint32_t v = thumb_bilinear(thumb, fx, fy);
			row[x] = (uint8_t)(v * STILL_DIM_NUMERATOR /
					   STILL_DIM_DENOMINATOR);
		}
	}

	draw_pause_glyph(luma, width, height);

	struct obs_source_frame frame = {0};
	frame.format = VIDEO_FORMAT_Y800;
	frame.width = (uint32_t)width;
	frame.height = (uint32_t)height;
	frame.data[0] = luma;
	frame.linesize[0] = (uint32_t)width;
	/* Y800 as written here is full-range grey; without this OBS
	 * stretches 16-235 and the still comes out crushed. */
	frame.full_range = true;
	frame.timestamp = timestamp ? timestamp : os_gettime_ns();

	/* obs_source_output_video copies into its own frame cache, so the
	 * scratch buffer is ours to free straight away. */
	obs_source_output_video(source, &frame);
	bfree(luma);
	return true;
}
