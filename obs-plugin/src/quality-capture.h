#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

bool lenslink_quality_arm(const char *id);

void lenslink_quality_chunk(const uint8_t *payload, size_t len);

void lenslink_quality_status_json(char *out, size_t size);

void lenslink_quality_shutdown(void);

#ifdef __cplusplus
}
#endif
