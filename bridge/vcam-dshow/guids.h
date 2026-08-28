/*
 * Identity of the virtual camera.
 *
 * The CLSID is baked into the registry when the DLL registers itself
 * and is how every app that has ever selected this camera refers to it.
 * Changing it orphans those selections and leaves a dead entry in
 * everyone's camera list — so it is fixed for good.
 */

#pragma once

#include <windows.h>

/* {8E5D2A31-9C74-4F6B-B1A8-3D0E7C42F901} */
DEFINE_GUID(CLSID_LensLinkVCam, 0x8e5d2a31, 0x9c74, 0x4f6b, 0xb1, 0xa8,
	    0x3d, 0x0e, 0x7c, 0x42, 0xf9, 0x01);

/* What the user sees in Zoom's camera dropdown. Must match the string
 * the uninstaller looks for, so it lives here rather than inline. */
#define LENSLINK_VCAM_NAME L"LensLink Camera"
