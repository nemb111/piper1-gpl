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

# Ensure onnxruntime-web npm package is installed in wasm_piper/
if(NOT DEFINED onnxruntime_web_npm_dir)
    get_filename_component(_ort_wasm_dir "${CMAKE_CURRENT_LIST_DIR}/../../wasm_piper" ABSOLUTE)
else()
    set(_ort_wasm_dir "${onnxruntime_web_npm_dir}")
endif()
if(NOT EXISTS "${_ort_wasm_dir}/node_modules/onnxruntime-web")
    if(NOT COMMAND npm)
        message(FATAL_ERROR
            "onnxruntime-web npm package not found.\n"
            "Install Node.js and run:\n"
            "    cd wasm_piper && npm install\n"
            "Or pass -Donnxruntime_web_npm_dir=/path/to/wasm_piper"
        )
    endif()
    message(STATUS "onnxruntime-web not found — installing in ${_ort_wasm_dir}")
    execute_process(
        COMMAND npm install
        WORKING_DIRECTORY "${_ort_wasm_dir}"
        RESULT_VARIABLE _npm_result
    )
    if(NOT _npm_result EQUAL 0)
        message(FATAL_ERROR "npm install onnxruntime-web failed (exit code ${_npm_result})")
    endif()
endif()

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
