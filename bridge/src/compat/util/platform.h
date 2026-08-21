/*
 * libobs platform helpers, shimmed for the standalone bridge.
 * Only the handful the reused plugin sources call.
 */

#pragma once

#include <stdint.h>

/* Monotonic nanoseconds — the clock the wire protocol's pts values and
 * the TIMESYNC exchange are compared against. Must never go backwards. */
uint64_t os_gettime_ns(void);
void os_sleep_ms(uint32_t duration);
void os_set_thread_name(const char *name);
