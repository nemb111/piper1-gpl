# Shared CMake module: configure onnxruntime for native or WASM builds.
#
# Usage: include(onnxruntime_external) configure_onnxruntime_external()
#
# For native builds: downloads and extracts the real onnxruntime library. For
# WASM builds: does nothing (caller should provide mock libraries).
#
# Optional variables (set by caller): ONNXRUNTIME_VERSION  — default: 1.22.0
# ONNXRUNTIME_DIR      — skip download/extract if already set onnxruntime_url —
# custom download URL
#
# After configure_onnxruntime_external(), link against onnxruntime_iface_lib.

include(ExternalProject)

# Configure ONNX Runtime for native builds. @brief Downloads, extracts, and sets
# up ONNX Runtime library. @param onnxruntime_url Optional custom download URL
# @param onnxruntime_dir Optional pre-extracted onnxruntime directory
function(configure_onnxruntime_external)
  # No-op: caller provides its own onnxruntime_iface_lib (WASM)
  if(TARGET onnxruntime_iface_lib)
    return()
  endif()

  # Pre-extracted: just wire up the interface
  if(DEFINED ONNXRUNTIME_DIR)
    _setup_or_interface(${ONNXRUNTIME_DIR})
    return()
  endif()

  # Set version and download URL
  set(ONNXRUNTIME_VERSION
      "1.22.0"
      CACHE STRING "onnxruntime version to download")
  _set_or_platform("${ONNXRUNTIME_VERSION}")

  # Use custom URL if provided
  if(NOT DEFINED onnxruntime_url)
    set(onnxruntime_url
        "https://github.com/microsoft/onnxruntime/releases/download/v${ONNXRUNTIME_VERSION}/${or_prefix}.${or_ext}"
    )
  endif()

  # Set up paths
  set(or_download_dir "${CMAKE_BINARY_DIR}/external/onnxruntime")
  set(or_filename "${or_prefix}.${or_ext}")
  set(or_dir "${or_download_dir}/${or_prefix}")

  # Download and extract if needed
  _download_or_archive("${or_download_dir}" "${or_filename}" "${or_dir}"
                       "${onnxruntime_url}")

  # Wire up interface library
  _setup_or_interface("${or_dir}")

  if(DEFINED _repo_root)
    target_include_directories(onnxruntime_iface_lib
                               INTERFACE ${_repo_root}/libpiper/include)
  endif()

  set(ONNXRUNTIME_DIR
      "${or_dir}"
      PARENT_SCOPE)
endfunction()

# Set platform-specific onnxruntime prefix and extension
function(_set_or_platform version)
  set(or_prefix
      ""
      PARENT_SCOPE)
  set(or_ext
      "tgz"
      PARENT_SCOPE)

  if(WIN32)
    set(or_prefix
        "onnxruntime-win-x64-${version}"
        PARENT_SCOPE)
    set(or_ext
        "zip"
        PARENT_SCOPE)
  elseif(APPLE)
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL x86_64)
      set(or_prefix
          "onnxruntime-osx-x86_64-${version}"
          PARENT_SCOPE)
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL arm64)
      set(or_prefix
          "onnxruntime-osx-arm64-${version}"
          PARENT_SCOPE)
    else()
      message(FATAL_ERROR "Unsupported architecture for onnxruntime on Apple")
    endif()
  else()
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL x86_64)
      set(or_prefix
          "onnxruntime-linux-x64-${version}"
          PARENT_SCOPE)
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL aarch64)
      set(or_prefix
          "onnxruntime-linux-aarch64-${version}"
          PARENT_SCOPE)
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL armv7l)
      set(or_prefix
          "onnxruntime-linux-arm32-${version}"
          PARENT_SCOPE)
      set(or_url
          "https://github.com/synesthesiam/prebuilt-apps/releases"
          "/download/v1.0/onnxruntime-linux-arm32-${version}.tgz"
          PARENT_SCOPE)
    else()
      message(FATAL_ERROR "Unsupported architecture for onnxruntime")
    endif()
  endif()
endfunction()

# Download and extract onnxruntime archive
function(_download_or_archive dl_dir filename or_dir url)
  if(NOT EXISTS "${or_dir}")
    if(NOT EXISTS "${dl_dir}/${filename}")
      file(MAKE_DIRECTORY "${dl_dir}")
      message("Downloading ${url}")
      file(DOWNLOAD "${url}" "${dl_dir}/${filename}")
    endif()
    execute_process(
      COMMAND ${CMAKE_COMMAND} -E tar xzf "${dl_dir}/${filename}"
      WORKING_DIRECTORY "${dl_dir}"
      RESULT_VARIABLE _extract_result)
    if(NOT _extract_result EQUAL 0)
      message(
        FATAL_ERROR
          "Failed to extract ONNX Runtime archive: ${dl_dir}/${filename}")
    endif()
  endif()
endfunction()

# Set up ONNX Runtime interface library
function(_setup_or_interface or_dir)
  add_library(onnxruntime_iface_lib INTERFACE)
  target_include_directories(onnxruntime_iface_lib INTERFACE ${or_dir}/include)
  target_link_directories(onnxruntime_iface_lib INTERFACE ${or_dir}/lib)
  target_link_libraries(onnxruntime_iface_lib INTERFACE onnxruntime)
endfunction()
