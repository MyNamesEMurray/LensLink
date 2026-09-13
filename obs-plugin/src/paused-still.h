#pragma once

#include <obs-module.h>
#include <stdbool.h>
#include <stdint.h>

#include "h264-decoder.h"

/*
 * Draws the picture OBS shows while the phone holds a stream: the last
 * frame's thumbnail blown back up to size (which is the blur), dimmed,
 * in grey, with a pause glyph over it. See paused-still.c for why.
 *
 * `thumb` is LENSLINK_THUMB_W * LENSLINK_THUMB_H bytes of luma, from
 * h264_decoder_thumbnail(). `timestamp` places the frame on the stream's
 * own timeline; 0 falls back to the system clock. Returns false when
 * there is nothing sane to draw.
 */
bool lenslink_paused_still_output(obs_source_t *source, const uint8_t *thumb,
				  int width, int height, uint64_t timestamp);
