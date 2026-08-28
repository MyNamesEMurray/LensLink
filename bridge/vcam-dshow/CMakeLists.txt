# lenslink-vcam.dll — the DirectShow virtual camera.
#
# A separate CMake project from the bridge because it is a separate
# deliverable with a different lifecycle: the DLL is registered once by
# an installer and then loaded into other people's processes, while the
# bridge is an ordinary program the user runs. They share only
# frame-shm.c, the mapping both ends read and write.
#
# Built for x64 AND x86: a 32-bit app can only load a 32-bit DirectShow
# filter, and plenty of conferencing software is still 32-bit. Both
# register against the same CLSID, each under its own registry view.

cmake_minimum_required(VERSION 3.16)
project(lenslink-vcam CXX C)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT WIN32)
  message(FATAL_ERROR "lenslink-vcam is a DirectShow filter; Windows only")
endif()

add_library(lenslink-vcam SHARED
  dllmain.cpp
  vcam-filter.cpp
  ../src/frame-shm.c
  lenslink-vcam.def
)

target_include_directories(lenslink-vcam PRIVATE . ../src)

target_compile_definitions(lenslink-vcam PRIVATE
  _CRT_SECURE_NO_WARNINGS WIN32_LEAN_AND_MEAN)

# strmiids carries the DirectShow interface and class GUIDs
# (IID_IPin, CLSID_FilterMapper2, MEDIASUBTYPE_NV12, ...).
target_link_libraries(lenslink-vcam PRIVATE strmiids ole32 oleaut32 uuid
                                            advapi32)

# The registry path and the app-visible camera name both come from the
# DLL, so its own filename is the only thing an installer needs to know.
set_target_properties(lenslink-vcam PROPERTIES
  OUTPUT_NAME "lenslink-vcam"
  PREFIX "")

if(MINGW)
  # Local compile-checking build. MinGW needs the .def passed as a link
  # input and does not produce the MSVC import library layout, which is
  # fine — nothing links against a COM server.
  target_link_options(lenslink-vcam PRIVATE
    -static-libgcc -static-libstdc++)
endif()
