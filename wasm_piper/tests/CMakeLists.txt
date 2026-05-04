# Build WASM integration test (mock ONNX)
#
# Build:
#   cmake -B wasm_piper/build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=<emsdk>/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake \
#     -DCMAKE_C_COMPILER=emcc -DCMAKE_CXX_COMPILER=emcc
#   cmake --build wasm_piper/build

cmake_minimum_required(VERSION 3.26)
project(wasm_piper_integration LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

get_filename_component(_repo_root "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)

# espeak-ng (required by piper.cpp)
set(_ESPEAK_INSTALL "${ESPEAKNG_INSTALL}" CACHE PATH "espeak-ng install directory")
set(_ESPEAK_UCD "${ESPEAKNG_UCD}" CACHE PATH "libucd.a path")

# ── Mock build (baseline) ──
add_executable(piper_wasm_mock_integration_test
    "${_repo_root}/libpiper/src/piper.cpp"
    "${_repo_root}/libpiper/tests/mock_onnxruntime.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/wasm_integration_main.cpp"
)

target_compile_definitions(piper_wasm_mock_integration_test PUBLIC MOCK_BUILD=1)
target_include_directories(piper_wasm_mock_integration_test PUBLIC
    "${_repo_root}/libpiper/include"
    "${_repo_root}/libpiper/tests"
    "${_ESPEAK_INSTALL}/include"
)
target_link_libraries(piper_wasm_mock_integration_test PRIVATE
    "${_ESPEAK_INSTALL}/lib/libespeak-ng.a"
    "${_ESPEAK_UCD}"
)
target_link_options(piper_wasm_mock_integration_test PRIVATE
    -O0
    -sALLOW_MEMORY_GROWTH
    -sMODULARIZE=1
    -sEXPORT_NAME="createModule"
    -sWASM_BIGINT=1
    -sENVIRONMENT=node
    -sEXPORTED_FUNCTIONS='[_malloc,_free,_piper_create,_piper_default_synthesize_options,_piper_synthesize_start,_piper_synthesize_next,_piper_free]'
    -sEXPORTED_RUNTIME_METHODS=["stringToUTF8","UTF8ToString","ccall","cwrap","FS"]
)
set(_data_dir "${CMAKE_CURRENT_SOURCE_DIR}/data")
set_target_properties(piper_wasm_mock_integration_test PROPERTIES
    LINK_FLAGS "--preload-file=\"${_data_dir}/espeak-ng-data@/espeak-ng-data\" --preload-file=\"${_data_dir}/test_voice.onnx.json@/test-data/test_voice.onnx.json\" --preload-file=\"${_data_dir}/test_voice.onnx@/test-data/test_voice.onnx\""
)
set_target_properties(piper_wasm_mock_integration_test PROPERTIES SUFFIX ".js")
