# Shared CMake module: configure onnxruntime for native or WASM builds.
#
# Usage: include(onnxruntime_external) configure_onnxruntime_external()
#
# For native builds: downloads and extracts the real onnxruntime library. For
# WASM builds: does nothing (caller should provide mock libraries).
#
# Optional variables (set by caller): ONNXRUNTIME_VERSION  — default: 1.22.0
# ONNXRUNTIME_DIR      — skip download/extract if already set ONNXRUNTIME_URL —
# custom download URL
#
# After configure_onnxruntime_external(), link against onnxruntime_iface_lib.

include(ExternalProject)

function(configure_onnxruntime_external)
  # ── No-op: caller provides its own onnxruntime_iface_lib (WASM) ──
  if(TARGET onnxruntime_iface_lib)
    return()
  endif()

  # ── Pre-extracted: just wire up the interface ──
  if(DEFINED ONNXRUNTIME_DIR)
    add_library(onnxruntime_iface_lib INTERFACE)
    target_include_directories(onnxruntime_iface_lib
                               INTERFACE ${ONNXRUNTIME_DIR}/include)
    target_link_directories(onnxruntime_iface_lib INTERFACE
                            ${ONNXRUNTIME_DIR}/lib)
    target_link_libraries(onnxruntime_iface_lib INTERFACE onnxruntime)
    return()
  endif()

  # ── Native: download and extract real onnxruntime ──
  set(ONNXRUNTIME_VERSION
      "1.22.0"
      CACHE STRING "onnxruntime version to download")

  # Determine platform-specific prefix and extension
  set(_OR_PREFIX "")
  set(_OR_EXT "tgz")

  if(WIN32)
    set(_OR_PREFIX "onnxruntime-win-x64-${ONNXRUNTIME_VERSION}")
    set(_OR_EXT "zip")
  elseif(APPLE)
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL x86_64)
      set(_OR_PREFIX "onnxruntime-osx-x86_64-${ONNXRUNTIME_VERSION}")
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL arm64)
      set(_OR_PREFIX "onnxruntime-osx-arm64-${ONNXRUNTIME_VERSION}")
    else()
      message(FATAL_ERROR "Unsupported architecture for onnxruntime on Apple")
    endif()
  else()
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL x86_64)
      set(_OR_PREFIX "onnxruntime-linux-x64-${ONNXRUNTIME_VERSION}")
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL aarch64)
      set(_OR_PREFIX "onnxruntime-linux-aarch64-${ONNXRUNTIME_VERSION}")
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL armv7l)
      set(_OR_PREFIX "onnxruntime-linux-arm32-${ONNXRUNTIME_VERSION}")
      set(_OR_URL
          "https://github.com/synesthesiam/prebuilt-apps/releases/download/v1.0/onnxruntime-linux-arm32-${ONNXRUNTIME_VERSION}.tgz"
      )
    else()
      message(FATAL_ERROR "Unsupported architecture for onnxruntime")
    endif()
  endif()

  if(NOT DEFINED ONNXRUNTIME_URL)
    set(ONNXRUNTIME_URL
        "https://github.com/microsoft/onnxruntime/releases/download/v${ONNXRUNTIME_VERSION}/${_OR_PREFIX}.${_OR_EXT}"
    )
  endif()

  # Put downloads and extracted artifacts in the build tree (cleanable like
  # build/).
  set(_OR_DOWNLOAD_DIR "${CMAKE_BINARY_DIR}/external/onnxruntime")
  set(_OR_FILENAME "${_OR_PREFIX}.${_OR_EXT}")
  set(_OR_DIR "${_OR_DOWNLOAD_DIR}/${_OR_PREFIX}")

  if(NOT EXISTS "${_OR_DIR}")
    if(NOT EXISTS "${_OR_DOWNLOAD_DIR}/${_OR_FILENAME}")
      file(MAKE_DIRECTORY "${_OR_DOWNLOAD_DIR}")
      message("Downloading ${ONNXRUNTIME_URL}")
      file(DOWNLOAD "${ONNXRUNTIME_URL}" "${_OR_DOWNLOAD_DIR}/${_OR_FILENAME}")
    endif()
    file(ARCHIVE_EXTRACT INPUT "${_OR_DOWNLOAD_DIR}/${_OR_FILENAME}"
         DESTINATION "${_OR_DOWNLOAD_DIR}")
  endif()

  # ── Interface library ──
  add_library(onnxruntime_iface_lib INTERFACE)
  target_include_directories(onnxruntime_iface_lib INTERFACE ${_OR_DIR}/include)
  target_link_directories(onnxruntime_iface_lib INTERFACE ${_OR_DIR}/lib)
  target_link_libraries(onnxruntime_iface_lib INTERFACE onnxruntime)

  # ── Add libpiper/include if caller sets _repo_root (for piper_impl.hpp) ──
  if(DEFINED _repo_root)
    target_include_directories(onnxruntime_iface_lib
                               INTERFACE ${_repo_root}/libpiper/include)
  endif()

  # Export ONNXRUNTIME_DIR for callers that need it (e.g. install).
  set(ONNXRUNTIME_DIR
      "${_OR_DIR}"
      PARENT_SCOPE)
endfunction()
