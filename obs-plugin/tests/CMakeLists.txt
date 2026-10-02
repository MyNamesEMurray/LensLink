# Standalone unit tests for pure plugin logic: no libobs, no FFmpeg, no
# OBS process. Enabled with -DLENSLINK_BUILD_TESTS=ON; run with ctest (or
# the binaries directly).

set(_src ${CMAKE_CURRENT_SOURCE_DIR}/../src)

function(lenslink_test name)
  add_executable(test-${name} test-${name}.c ${ARGN})
  target_include_directories(test-${name} PRIVATE ${_src})
  if(NOT WIN32)
    target_link_libraries(test-${name} PRIVATE m)
  endif()
  add_test(NAME ${name} COMMAND test-${name})
endfunction()

lenslink_test(protocol)
