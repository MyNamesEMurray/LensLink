# LensLink Bridge — the phone as a plain webcam, without OBS.
#
# Builds a standalone executable that reuses the OBS plugin's transport,
# discovery, decode and control-panel sources verbatim (see
# src/compat/obs-module.h for how they compile without libobs). Keeping
# them byte-identical between the two builds is the point: the bridge
# cannot drift from the plugin, because it is the same code.
#
# No globbing here either — new .c files go in the lists below.

cmake_minimum_required(VERSION 3.16)
project(lenslink-bridge C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT LENSLINK_VERSION)
  set(LENSLINK_VERSION "dev")
endif()

set(PLUGIN_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../obs-plugin/src")

# Shared with the OBS plugin, compiled unmodified.
set(SHARED_SOURCES
  "${PLUGIN_SRC}/usbmux.c"
  "${PLUGIN_SRC}/mdns.c"
  "${PLUGIN_SRC}/h264-decoder.c"
  "${PLUGIN_SRC}/web-control.c"
)

set(BRIDGE_SOURCES
  src/main.c
  src/bridge-core.c
  src/bridge-config.c
  src/bridge-settings.c
  src/frame-queue.c
  src/nv12.c
  src/nv12-scale.c
  src/obs-shim.c
  src/vcam-ppm.c
)

# One virtual-camera backend per platform.
#
# Windows publishes frames into shared memory, where lenslink-vcam.dll
# picks them up inside whichever app opened the camera. Everywhere else
# there is no camera stack to publish to, so the null backend counts
# frames and can write a snapshot — which is what keeps the whole
# receive/decode path testable on a plain Linux CI runner.
if(WIN32)
  list(APPEND BRIDGE_SOURCES src/vcam-shm.c src/frame-shm.c)
else()
  list(APPEND BRIDGE_SOURCES src/vcam-null.c)
endif()

add_executable(lenslink-bridge ${BRIDGE_SOURCES} ${SHARED_SOURCES})

target_include_directories(lenslink-bridge PRIVATE
  src
  src/compat
  "${PLUGIN_SRC}"
)

target_compile_definitions(lenslink-bridge PRIVATE
  LENSLINK_VERSION="${LENSLINK_VERSION}"
)

# FFmpeg. CI passes explicit paths to the static decode-only build
# (.github/actions/static-ffmpeg) so the executable has no FFmpeg DLL
# dependency at all; a local build falls back to pkg-config.
if(FFMPEG_INCLUDE_DIR AND AVCODEC_LIBRARY AND AVUTIL_LIBRARY)
  target_include_directories(lenslink-bridge PRIVATE "${FFMPEG_INCLUDE_DIR}")
  target_link_libraries(lenslink-bridge PRIVATE
    "${AVCODEC_LIBRARY}" "${AVUTIL_LIBRARY}")
else()
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET libavcodec libavutil)
  target_link_libraries(lenslink-bridge PRIVATE PkgConfig::FFMPEG)
endif()

if(WIN32)
  # bcrypt/ole32/user32: referenced by the static decode-only FFmpeg that
  # release builds link (avutil's BCryptGenRandom RNG, DXVA2 device
  # setup). No-ops when linking a shared FFmpeg.
  target_link_libraries(lenslink-bridge PRIVATE ws2_32 bcrypt ole32 user32)
  # The reused sources use snprintf and friends; MSVC's "deprecated"
  # warnings for them are noise, not signal.
  target_compile_definitions(lenslink-bridge PRIVATE
    _CRT_SECURE_NO_WARNINGS WIN32_LEAN_AND_MEAN)
else()
  find_package(Threads REQUIRED)
  target_link_libraries(lenslink-bridge PRIVATE Threads::Threads m)
endif()

if(APPLE)
  # The static FFmpeg's VideoToolbox hwaccel resolves against these.
  target_link_libraries(lenslink-bridge PRIVATE
    "-framework VideoToolbox" "-framework CoreMedia"
    "-framework CoreVideo" "-framework CoreFoundation")
endif()

install(TARGETS lenslink-bridge RUNTIME DESTINATION bin)
