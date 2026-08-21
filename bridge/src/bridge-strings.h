/*
 * Status vocabulary for the bridge.
 *
 * These mirror the Status.* entries in
 * obs-plugin/data/locale/en-US.ini, reworded only where the plugin's
 * text names OBS ("this source", "another LensLink source"). The
 * vocabulary itself is fixed by docs/UI_DESIGN.md and is shared with
 * the app and the web panel — change it here and there together.
 *
 * Not a locale file: the bridge ships no translation machinery yet. If
 * it grows one, this header is the list to feed it.
 */

#pragma once

#define LL_STATUS_CONNECTED "Connected:"
#define LL_STATUS_DISCONNECTED "Disconnected — reconnecting"
#define LL_STATUS_DIALING "Trying to reach the phone at"
#define LL_STATUS_NO_HOST \
	"Set the phone's IP address (shown in the LensLink app)"
#define LL_STATUS_WAITING_USB                                              \
	"No device detected on USB — check the cable and tap Trust "       \
	"(Windows also needs iTunes)"
#define LL_STATUS_WAITING_PINNED \
	"Waiting for the selected USB device to be connected"
#define LL_STATUS_USB_FOUND                                                 \
	"Device found, but the LensLink app isn't reachable — unlock the "  \
	"phone and open the app (it must be on screen), then start the "    \
	"camera there or from here"
#define LL_STATUS_DECODER_FAILED \
	"Connected, but the stream can't be decoded — try H.264 in the app"
#define LL_STATUS_CAMERA_ON_SCREEN                                          \
	"Phone is sending its camera — this device is set to screen "       \
	"mirroring. Start a screen broadcast on the phone, or switch this " \
	"device to the camera."
#define LL_STATUS_SCREEN_ON_CAMERA                                           \
	"Phone is sending a screen broadcast — this device is set to the "   \
	"camera. Switch this device to screen mirroring for it."
#define LL_STATUS_STANDBY                                                 \
	"Connected — the camera is idle. It can be started from the "     \
	"control panel."
#define LL_STATUS_STARTING "Starting the phone's camera…"
