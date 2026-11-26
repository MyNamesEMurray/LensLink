#pragma once

#include <obs-module.h>

struct ios_camera_source;

#ifdef __cplusplus
extern "C" {
#endif

void lenslink_camera_controls_add(obs_properties_t *props,
				  struct ios_camera_source *s,
				  obs_data_t *settings);

void lenslink_camera_controls_clear(obs_data_t *settings);

const char *lenslink_lens_text(const char *label);

/* Registers the source's OBS hotkeys; the returned context goes back to
 * lenslink_camera_hotkeys_free(), which unregisters them first. */
void *lenslink_camera_hotkeys_register(struct ios_camera_source *s,
				       obs_source_t *source);
void lenslink_camera_hotkeys_free(void *hotkeys);

#ifdef __cplusplus
}
#endif
