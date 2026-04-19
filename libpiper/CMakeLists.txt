# Builds libpiper
cmake_minimum_required(VERSION 3.26)
project(piper LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── espeak-ng toolchain vars (native build) ─────────────
get_filename_component(_repo_root "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(PIPER_ESPEAKNG_UPDATE_DISCONNECTED ON CACHE BOOL "" FORCE)
set(PIPER_ESPEAKNG_PATCH_SCRIPT "${_repo_root}/cmake/patch_espeak_data.sh" CACHE STRING "" FORCE)
set(PIPER_ESPEAKNG_CMAKE_ARGS)

include(${CMAKE_CURRENT_LIST_DIR}/../cmake/espeak_ng_external.cmake)
configure_espeak_ng_external()

# ── onnxruntime (native: real library; WASM: use mock libraries) ──

include(${_repo_root}/cmake/onnxruntime_external.cmake)
configure_onnxruntime_external()

# ---- libpiper ---

add_library(piper SHARED
    ${CMAKE_CURRENT_SOURCE_DIR}/src/piper.cpp
)

target_include_directories(piper PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(piper
    espeakng_iface_lib
    onnxruntime_iface_lib
)

# ---- install ---

include(GNUInstallDirs)

install(TARGETS piper
    DESTINATION ${CMAKE_INSTALL_PREFIX}
)

install(
    FILES ${CMAKE_CURRENT_SOURCE_DIR}/include/piper.h
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(
    DIRECTORY ${ONNXRUNTIME_DIR}/lib/
    DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

# ---- Google Test ----

include(FetchContent)
FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/refs/heads/main.zip
)
# For Windows:
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

# Add tests subdirectory
# Pass ESPEAKNG_INSTALL_DIR to the tests subdirectory
set(ESPEAKNG_INSTALL_DIR ${CMAKE_BINARY_DIR}/espeak_ng-install)
add_subdirectory(tests)

# =============================================================================
# Documentation: Compile-Test Workflow
# =============================================================================
#
# The mock libraries and test executables are now defined in tests/CMakeLists.txt
#
# To perform compile-time API verification:
#   1. Build with mocks: cmake -B build && cmake --build build
#   2. Swap mock libraries with real implementations (libespeak-ng.a, onnxruntime.so)
#   3. Rebuild: cmake --build build
#   4. Successful compilation = API compatibility verified
#

# Copy espeak-ng-data
set(ESPEAKNG_DATA_SRC ${CMAKE_BINARY_DIR}/espeak_ng-install/share/espeak-ng-data)
set(ESPEAKNG_DATA_DST ${CMAKE_INSTALL_PREFIX}/espeak-ng-data)

install(
    DIRECTORY ${ESPEAKNG_DATA_SRC}
    DESTINATION ${CMAKE_INSTALL_PREFIX}
)
