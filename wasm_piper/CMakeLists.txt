cmake_minimum_required(VERSION 3.26)

# ── Auto-detect/download Emscripten SDK before project() ──
include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/emscripten/find_emscripten.cmake)

# ── Ort Shim (ONNX Runtime C++ API → onnxruntime-web bridge) ──
set(SHIM_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/shim/src)
include(${SHIM_SRC_DIR}/ort_shim_external.cmake)

project(wasm_piper)

# ── Repo root ──
get_filename_component(_repo_root "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)

# ── Auto-install onnxruntime-web (WASM JS synthesis script dependency) ──
get_filename_component(_wasm_piper_dir "${CMAKE_CURRENT_SOURCE_DIR}" ABSOLUTE)
get_filename_component(_ort_npm_dir "${_repo_root}/external/node_modules" ABSOLUTE)
if(NOT EXISTS "${_ort_npm_dir}/onnxruntime-web")
    file(WRITE "${CMAKE_BINARY_DIR}/.install_ort.sh"
"#!/bin/sh\nset -e\ncd \"${_wasm_piper_dir}\"\nnpm install\nmkdir -p \"${_ort_npm_dir}\"\ncp -a \"node_modules/.\" \"${_ort_npm_dir}/\"\nrm -rf node_modules\nln -sfn \"${_ort_npm_dir}\" node_modules\n")
    execute_process(
        COMMAND sh "${CMAKE_BINARY_DIR}/.install_ort.sh"
        RESULT_VARIABLE _npm_result
    )
    if(NOT _npm_result EQUAL 0)
        message(FATAL_ERROR "npm install onnxruntime-web failed (exit code ${_npm_result})")
    endif()
endif()

enable_language(C)
enable_language(CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Emscripten espeak-ng build ──
include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/emscripten/espeak_ng_external.cmake)

get_filename_component(PIPER_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)

configure_espeak_ng_emscripten()

if(TARGET espeak_ng_cross)
    add_custom_target(build_espeak_wasm ALL DEPENDS espeak_ng_cross)
else()
    add_custom_target(build_espeak_wasm ALL)
endif()

# ── Piper WASM executable ──
# Uses real piper.cpp with ort_shim (ONNX Runtime C++ API shim → onnxruntime-web)
add_executable(piper_wasm
    ${CMAKE_CURRENT_SOURCE_DIR}/../libpiper/src/piper.cpp
)

set_target_properties(piper_wasm PROPERTIES
    LINK_FLAGS "-s ALLOW_MEMORY_GROWTH=1 -s MODULARIZE=1 -s EXPORT_NAME='piperWasm' -s EXPORTED_FUNCTIONS='[_malloc,_free,_piper_create,_piper_default_synthesize_options,_piper_synthesize_start,_piper_synthesize_next,_piper_free]' -s EXPORTED_RUNTIME_METHODS='[ccall,cwrap,stackAlloc,stackRestore,stackSave,UTF8ToString,stringToUTF8,lengthBytesUTF8,getValue,setValue,HEAP8,HEAPU8,HEAPU16,HEAPU32,HEAPF32,HEAP64,FS]' -s ASYNCIFY=1 -s EXIT_RUNTIME=1 -s WASM_BIGINT=1 -s FILESYSTEM=1 -s INITIAL_MEMORY=2147483648 -s STACK_SIZE=67108864 -s DISABLE_EXCEPTION_CATCHING=0 -s ALLOW_TABLE_GROWTH=1 -s DISABLE_DEPRECATED_FIND_EVENT_TARGET_BEHAVIOR=1 --no-entry --preload-file ${CMAKE_CURRENT_SOURCE_DIR}/tests/data@/"
    OUTPUT_NAME "piper_wasm"
    SUFFIX ".js"
)

target_link_libraries(piper_wasm
    PUBLIC
        espeakng_iface_lib
)
target_include_directories(piper_wasm PRIVATE
    ${SHIM_SRC_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${_repo_root}/libpiper/include
)
