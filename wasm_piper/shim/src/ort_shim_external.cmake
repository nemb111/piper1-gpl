# ── ort_shim_external.cmake ──
#
# Provides onnxruntime_iface_lib for Emscripten/WASM builds.
#
# The shim replaces the real ONNX Runtime C++ API with EM_JS calls to
# onnxruntime-web. onnxruntime_iface_lib is an INTERFACE library that adds
# shim/src/ to the include path (so #include <onnxruntime_cxx_api.h>
# resolves to the shim instead of the real header from piper_impl.hpp).
#
# Additionally, ort_shim.js is merged into piper_wasm.js via a post-link
# step so that ortShimModule is globally available when EM_JS functions
# (ort_shim_run, ort_shim_set_input_data, etc.) execute.
#
# Usage (in wasm_piper/CMakeLists.txt, before project()):
#   set(SHIM_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/shim/src)
#   include(${SHIM_SRC_DIR}/ort_shim_external.cmake)
#
# If onnxruntime_iface_lib is already defined, this is a no-op.

function(configure_ort_shim_external)
    # No-op guard: if caller already defined onnxruntime_iface_lib, skip
    if(TARGET onnxruntime_iface_lib)
        return()
    endif()

    add_library(onnxruntime_iface_lib INTERFACE)

    # SHIM_SRC_DIR set by caller (wasm_piper/CMakeLists.txt)
    target_include_directories(onnxruntime_iface_lib INTERFACE
        ${SHIM_SRC_DIR}
    )
endfunction()
