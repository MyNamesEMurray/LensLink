/*
 * Auto lip-sync calibration policy.
 *
 * The offset LensLink applies is `video latency - mic latency`. Those two
 * numbers come from very different places:
 *
 *   - Video latency is a property of the *link*. It moves with network
 *     conditions, resolution and USB-vs-Wi-Fi, and timesync measures it
 *     every second for free.
 *   - Mic latency is a property of the streamer's *audio gear* — interface
 *     buffering, driver, OBS's audio path. Recovering it needs the audio
 *     cross-correlation, which needs the phone's reference audio and
 *     someone making noise. It doesn't change while the audio path
 *     doesn't.
 *
 * So the correlation runs until the mic figure is known, then the figure
 * is latched and the offset simply tracks the video latency. The
 * correlation re-runs only occasionally, to notice if the audio path
 * changed underneath us (a re-plugged interface, a headset taking over).
 *
 * The decisions that drive that live here, free of libobs, so they can be
 * exercised without OBS or a phone.
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

/* Calibration progress. Reported to the user, so the wording of each state
 * matters as much as the value (see docs/UI_DESIGN.md). */
enum lipsync_cal_state {
	LS_CAL_OFF,       /* auto-calibrate disabled, or no audio source */
	LS_CAL_MEASURING, /* listening for agreeing readings; nothing applied */
	LS_CAL_LOCKED,    /* mic latency latched; tracking video latency */
	LS_CAL_RELOCK,    /* the latched figure stopped matching — re-measuring */
};

#define CAL_NS_MS 1000000LL

/* A correlation peak below this is noise, not a reading. */
#define CAL_MIN_CONFIDENCE 0.5

/* Once locked, the correlation only runs to confirm the latched figure is
 * still right — rarely, since what it measures doesn't drift on its own. */
#define CAL_VERIFY_INTERVAL_NS (90 * 1000000000ULL)

/* How far a confirming reading may sit from the latched figure before the
 * audio path is assumed to have changed under us. Comfortably wider than
 * the reading-to-reading noise the 40 ms agreement gate already tolerates,
 * so ordinary jitter can't knock a good lock loose. */
#define CAL_RELOCK_DIFF_NS (50 * CAL_NS_MS)

/* Whether a locked source should spend a correlation confirming itself.
 * `verified_ns` is when it last did (0 = never, which is due immediately). */
static inline bool lipsync_cal_due_for_verify(uint64_t now,
					      uint64_t verified_ns)
{
	/* Locking always stamps this, so 0 means a lock arrived some other
	 * way; confirm it at the first opportunity rather than trusting it
	 * for an interval. Explicit because `now - 0` is a plain duration
	 * since the clock's epoch, which says nothing about staleness. */
	if (verified_ns == 0)
		return true;
	return now - verified_ns >= CAL_VERIFY_INTERVAL_NS;
}

/* Whether a confirming reading is far enough from the latched figure to
 * mean the audio path changed, rather than ordinary measurement noise. */
static inline bool lipsync_cal_reading_invalidates(int64_t reading_ns,
						   int64_t locked_ns)
{
	int64_t drift = reading_ns - locked_ns;
	if (drift < 0)
		drift = -drift;
	return drift >= CAL_RELOCK_DIFF_NS;
}
