/*
 * libobs memory API, shimmed for the standalone bridge.
 *
 * The plugin sources the bridge reuses verbatim (usbmux.c, mdns.c,
 * h264-decoder.c, web-control.c) allocate through libobs. Outside OBS
 * these map straight onto the CRT; bmalloc/bzalloc abort on OOM, which
 * is what libobs does and what those call sites assume.
 */

#pragma once

#include <stddef.h>

void *bmalloc(size_t size);
void *bzalloc(size_t size);
void *brealloc(void *ptr, size_t size);
void bfree(void *ptr);
char *bstrdup(const char *str);
