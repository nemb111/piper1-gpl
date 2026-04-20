# Shared CMake module: download and build ONNX Runtime for WebAssembly.
#
# Produces libonnxruntime_webassembly.a and C/C++ headers in the build tree.
# Used by the WASM build of piper for real ONNX inference (no mocks).
#
# Usage:
#   include(onnxruntime_web_external)
#   configure_onnxruntime_web_external()
#
# Required cache vars (set before include):
#   ONNXRUNTIME_WEB_VERSION  - e.g. "1.22.0"
#   ONNXRUNTIME_WEB_HASH     - SHA256 of the tarball
#
# After configure, link against onnxruntime_web_iface_lib.

include(ExternalProject)

# Defaults (set before including this module)
set(ONNXRUNTIME_WEB_VERSION "1.22.0" CACHE STRING "ONNX Runtime version for WASM build")
set(ONNXRUNTIME_WEB_HASH   "08b078eb7afbf376064b2b0f1781e3d78151cac0592988a0c0ec78bf72fde810"
    CACHE STRING "SHA256 hash of ONNX Runtime tarball")
set(ONNXRUNTIME_WEB_EXTRA_ARGS "" CACHE STRING "Extra args passed to build.sh")

function(configure_onnxruntime_web_external)
    # Already provided?
    if(TARGET onnxruntime_web_iface_lib)
        return()
    endif()

    set(_OUT_DIR "${CMAKE_BINARY_DIR}/onnxruntime_web")
    set(_SRC_DIR "${_OUT_DIR}/src/onnxruntime")
    set(_LIB_DIR "${_OUT_DIR}/lib")
    set(_LIB_FILE "${_LIB_DIR}/libonnxruntime_webassembly.a")
    set(_HEADER_DIR "${_OUT_DIR}/include")

    message(STATUS "ONNX Runtime Web: building WASM static library for real ONNX inference")
    message(STATUS "  Version: ${ONNXRUNTIME_WEB_VERSION}")
    message(STATUS "  Output:  ${_LIB_FILE}")
    message(STATUS "  Note: First build takes ~30-60 min and downloads its own Emscripten SDK")

    if(NOT EXISTS "${_LIB_FILE}")
        ExternalProject_Add(onnxruntime_web_external
            URL "https://github.com/microsoft/onnxruntime/archive/refs/tags/v${ONNXRUNTIME_WEB_VERSION}.tar.gz"
            URL_HASH "SHA256=${ONNXRUNTIME_WEB_HASH}"
            PREFIX "${_OUT_DIR}"
            SOURCE_DIR "${_SRC_DIR}"
            CONFIGURE_COMMAND ""
            BUILD_IN_SOURCE 1
            BUILD_COMMAND
                ${CMAKE_COMMAND} -E env
                PATH="${_SRC_DIR}/emsdk_port_dir/emsdk/upstream/emscripten:$ENV{PATH}"
                PYTHON="${PYTHON_EXECUTABLE}"
                ${_SRC_DIR}/build.sh
                    --build_wasm_static_lib
                    --config Release
                    --skip_tests
                    ${ONNXRUNTIME_WEB_EXTRA_ARGS}
            INSTALL_COMMAND ""
            TEST_COMMAND ""
        )
    endif()

    add_library(onnxruntime_web_iface_lib INTERFACE)
    target_include_directories(onnxruntime_web_iface_lib INTERFACE
        ${_HEADER_DIR}
    )
    add_dependencies(onnxruntime_web_iface_lib onnxruntime_web_external)
endfunction()
