# Native build options for cmake/native/ modules.
#
# Usage:
#   include(native/options)
#
# Sets cache variables that control external library builds.

set(ONNXRUNTIME_VERSION "1.22.0" CACHE STRING "onnxruntime version to download")

if(NOT DEFINED PIPER_ESPEAKNG_UPDATE_DISCONNECTED)
    set(PIPER_ESPEAKNG_UPDATE_DISCONNECTED ON CACHE BOOL "Skip git update for espeak-ng ExternalProject")
endif()
if(NOT DEFINED PIPER_ESPEAKNG_CMAKE_ARGS)
    set(PIPER_ESPEAKNG_CMAKE_ARGS CACHE STRING "Extra CMAKE_ARGS for espeak-ng ExternalProject")
endif()
