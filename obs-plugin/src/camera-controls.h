#pragma once

#include <obs-module.h>

struct ios_camera_source;

#ifdef __cplusplus
extern "C" {
#endif

void lenslink_camera_controls_add(obs_properties_t *props,
				  struct ios_camera_source *s,
				  obs_data_t *settings);

const char *lenslink_lens_text(const char *label);

#ifdef __cplusplus
}
#endif
