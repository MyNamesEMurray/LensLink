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
lenslink_test(json-reader ${_src}/json-reader.c)
lenslink_test(handshake ${_src}/handshake.c ${_src}/json-reader.c)
lenslink_test(still ${_src}/still.c)

# Fuzz harnesses for the parsers of untrusted input (tests/fuzz/). By
# default each runs under a deterministic mutation driver as an ordinary
# test; configure with -DLENSLINK_FUZZ_LIBFUZZER=ON (clang with libFuzzer)
# to build real libFuzzer binaries instead, run by hand.
option(LENSLINK_FUZZ_LIBFUZZER "Build the fuzz harnesses against libFuzzer" OFF)
set(LENSLINK_FUZZ_ITERATIONS 200000 CACHE STRING
    "Mutations per fuzz harness when run by ctest")

function(lenslink_fuzz name)
  add_executable(fuzz-${name} fuzz/fuzz-${name}.c ${ARGN})
  target_include_directories(fuzz-${name} PRIVATE ${_src} fuzz)
  if(LENSLINK_FUZZ_LIBFUZZER)
    target_compile_options(fuzz-${name} PRIVATE -fsanitize=fuzzer)
    target_link_options(fuzz-${name} PRIVATE -fsanitize=fuzzer)
  else()
    target_sources(fuzz-${name} PRIVATE fuzz/fuzz-driver.c)
    add_test(NAME fuzz-${name}
             COMMAND fuzz-${name} ${LENSLINK_FUZZ_ITERATIONS})
  endif()
endfunction()

lenslink_fuzz(json ${_src}/handshake.c ${_src}/json-reader.c)
