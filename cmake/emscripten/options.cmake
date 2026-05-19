# Emscripten (WASM) build options for cmake/emscripten/ modules.
#
# Usage:
#   include(emscripten/options)
#
# Sets cache variables that control external dependency download, paths, and defaults.
# This file is auto-included by cmake/emscripten/find_emscripten.cmake.

# ── Version defaults (also used by build.py for consistency) ──
set(EMSCRIPTEN_VERSION "5.0.6" CACHE STRING "Emscripten version to download and use")
set(NODE_VERSION       "22.16.0" CACHE STRING "Node.js / npm version to download")
set(ONNXRUNTIME_VERSION "1.22.0" CACHE STRING "ONNX Runtime version (unused in WASM, kept for compatibility)")

# ── Substitutable dependency paths (CMake options) ──
# Set any of these with -D to override auto-detection/download.
# Each is a CACHE variable so -D persists across reconfigure.

set(EMSDK_PATH    ""      CACHE PATH "Path to emsdk directory (e.g. external/emsdk-5.0.6/emsdk). Empty = auto-detect/download")
set(NPM_DIR       ""      CACHE PATH "Path to node/bin directory (contains node + npm). Empty = auto-detect/download")
set(ONNXRUNTIME_WEB_LIB_PATH "" CACHE FILEPATH "Path to libonnxruntime_webassembly.a (pre-built). Empty = auto-detect/download")
set(ESPEAKNG_SRC_PATH ""      CACHE PATH   "Path to espeak-ng source directory (git clone). Empty = auto-clone from git via ExternalProject")

# ── Legacy espeak-ng flags (preserved for backward compatibility) ──
if(NOT DEFINED PIPER_ESPEAKNG_UPDATE_DISCONNECTED)
    set(PIPER_ESPEAKNG_UPDATE_DISCONNECTED ON CACHE BOOL "Skip git update for espeak-ng ExternalProject")
endif()
if(NOT DEFINED PIPER_ESPEAKNG_CMAKE_ARGS)
    set(PIPER_ESPEAKNG_CMAKE_ARGS CACHE STRING "Extra CMAKE_ARGS for espeak-ng ExternalProject (empty for cross-compile)")
endif()
