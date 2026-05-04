# Emscripten (WASM) build options for cmake/emscripten/ modules.
#
# Usage:
#   include(emscripten/options)
#
# Sets cache variables that control Emscripten SDK download and espeak-ng cross-compile.

set(EMSCRIPTEN_VERSION "5.0.6" CACHE STRING "Emscripten version to download and use")

# espeak-ng cross-compile defaults (overridden by native/espeak_ng_external.cmake
# via PIPER_ESPEAKNG_UPDATE_DISCONNECTED when that module is included)
if(NOT DEFINED PIPER_ESPEAKNG_UPDATE_DISCONNECTED)
    set(PIPER_ESPEAKNG_UPDATE_DISCONNECTED ON CACHE BOOL "Skip git update for espeak-ng ExternalProject")
endif()
if(NOT DEFINED PIPER_ESPEAKNG_CMAKE_ARGS)
    set(PIPER_ESPEAKNG_CMAKE_ARGS CACHE STRING "Extra CMAKE_ARGS for espeak-ng ExternalProject (empty for cross-compile)")
endif()
