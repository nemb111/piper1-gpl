# Find ONNX Runtime WASM static library and set up targets.
#
# Usage:
#   include(emscripten/find_onnxruntime_web)
#   # On first build this will error with instructions to build the library.
#   # After building, link against onnxruntime_web_iface_lib.
#
# Expected artifacts (produced by script/build_onnxruntime_web.py):
#   external/onnxruntime/libonnxruntime_webassembly.a
#   external/onnxruntime/include/         (headers)

get_filename_component(_repo_root "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(_LIB_FILE "${_repo_root}/external/onnxruntime/libonnxruntime_webassembly.a")
set(_HEADER_DIR "${_repo_root}/external/onnxruntime/include")

if(TARGET onnxruntime_web_iface_lib)
    return()
endif()

if(NOT EXISTS "${_LIB_FILE}")
    message(FATAL_ERROR
        "ONNX Runtime WASM static library not found: ${_LIB_FILE}\n"
        "Build it first by running:\n"
        "    python3 script/build_onnxruntime_web.py --extra-args --parallel 4\n"
        "This downloads ~2 GB and takes 30-60 minutes.\n"
        "Alternatively, use cmake -DONNXRUNTIME_WEB_EXTRA_ARGS=\"--parallel 4\" "
        "in the WASM project."
    )
endif()

add_library(onnxruntime_web_iface_lib INTERFACE)
target_include_directories(onnxruntime_web_iface_lib INTERFACE
    ${_HEADER_DIR}
)
target_link_libraries(onnxruntime_web_iface_lib INTERFACE
    "${_LIB_FILE}"
)

message(STATUS "ONNX Runtime Web: found ${_LIB_FILE}")
message(STATUS "  Headers: ${_HEADER_DIR}")
