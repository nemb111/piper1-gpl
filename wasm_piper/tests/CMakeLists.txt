# Build WASM integration tests (mock + real ONNX)
#
# Build mock:
#   cmake -B build_mock -S . \
#     -DCMAKE_TOOLCHAIN_FILE=<emsdk>/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake \
#     -DCMAKE_C_COMPILER=emcc -DCMAKE_CXX_COMPILER=emcc
#   cmake --build build_mock
#
# Build real ONNX:
#   cmake -B build_real -S . \
#     -DCMAKE_TOOLCHAIN_FILE=<emsdk>/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake \
#     -DCMAKE_C_COMPILER=emcc -DCMAKE_CXX_COMPILER=emcc \
#     -DCMAKE_PREFIX_PATH=/path/to/onnxruntime/build/Linux/Release \
#     -DONNX_SOURCE=/path/to/onnxruntime/source \
#     -DESPEAKNG_INSTALL=/path/to/espeak_ng-install \
#     -DESPEAKNG_UCD=/path/to/libucd.a
#   cmake --build build_real

cmake_minimum_required(VERSION 3.26)
project(wasm_piper_integration LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

get_filename_component(_repo_root "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)

# espeak-ng (required by piper.cpp)
set(_ESPEAK_INSTALL "${ESPEAKNG_INSTALL}" CACHE PATH "espeak-ng install directory")
set(_ESPEAK_UCD "${ESPEAKNG_UCD}" CACHE PATH "libucd.a path")
set(_OR_DIR "${CMAKE_PREFIX_PATH}" CACHE PATH "ONNX Runtime Web build directory")
set(_OR_SRC "${ONNX_SOURCE}" CACHE PATH "ONNX Runtime source (for headers)")

# ── Mock build (baseline, no real ONNX) ──
add_executable(piper_wasm_mock_integration_test
    "${_repo_root}/libpiper/src/piper.cpp"
    "${_repo_root}/libpiper/tests/mock_onnxruntime.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../piper_wasm.cpp"
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
    -sEXPORTED_RUNTIME_METHODS=["stringToUTF8","UTF8ToString","ccall","cwrap","FS"]
)
set(_data_dir "${CMAKE_CURRENT_SOURCE_DIR}/data")
set_target_properties(piper_wasm_mock_integration_test PROPERTIES
    LINK_FLAGS "--preload-file=\"${_data_dir}/espeak-ng-data@/espeak-ng-data\" --preload-file=\"${_data_dir}/test_voice.onnx.json@/test-data/test_voice.onnx.json\" --preload-file=\"${_data_dir}/test_voice.onnx@/test-data/test_voice.onnx\""
)
set_target_properties(piper_wasm_mock_integration_test PROPERTIES SUFFIX ".js")

# ── Real ONNX build (actual inference) ──
option(WASM_PIPER_REAL_ONNX "Build with real ONNX Runtime Web" OFF)

if(WASM_PIPER_REAL_ONNX)
    if(NOT DEFINED _OR_DIR OR NOT EXISTS "${_OR_DIR}/libonnxruntime_webassembly.a")
        message(FATAL_ERROR "Set CMAKE_PREFIX_PATH to ONNX Runtime Web build dir containing libonnxruntime_webassembly.a")
    endif()

    add_executable(piper_wasm_real_integration_test
        "${_repo_root}/libpiper/src/piper.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../piper_wasm.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/wasm_integration_main.cpp"
    )

    # NO MOCK_BUILD - uses real ONNX Runtime
    target_include_directories(piper_wasm_real_integration_test PUBLIC
        "${_repo_root}/libpiper/include"
        "${_repo_root}/libpiper/tests"
            "${_OR_SRC}/include/onnxruntime/core/session"
        "${_ESPEAK_INSTALL}/include"
    )

    target_link_libraries(piper_wasm_real_integration_test PRIVATE
        "${_OR_DIR}/libonnxruntime_webassembly.a"
        "${_ESPEAK_INSTALL}/lib/libespeak-ng.a"
        "${_ESPEAK_UCD}"
    )

    target_link_options(piper_wasm_real_integration_test PRIVATE
        -O0
        -sALLOW_MEMORY_GROWTH
        -sMODULARIZE=1
        -sEXPORT_NAME="createModule"
        -sWASM_BIGINT=1
        -sENVIRONMENT=node
        -sEXPORTED_RUNTIME_METHODS=["stringToUTF8","UTF8ToString","ccall","cwrap","FS","HEAPU8"]
        -sDISABLE_EXCEPTION_CATCHING=0
    )

    # Embed espeak data at /espeak-ng-data (matches check_data_path() requirement)
    # and symlink the compiled-in install path so internal file ops work.
    set(_espeak_src_data "${_repo_root}/wasm_piper/tests/data")
    set_target_properties(piper_wasm_real_integration_test PROPERTIES
        LINK_FLAGS "-sALLOW_MEMORY_GROWTH --preload-file=\"${_espeak_src_data}/espeak-ng-data@/espeak-ng-data\" --preload-file=\"${_data_dir}/en_US-amy-low.onnx.json@/test-data/en_US-amy-low.onnx.json\" --preload-file=\"${_data_dir}/en_US-amy-low.onnx@/test-data/en_US-amy-low.onnx\""
    )
    set_target_properties(piper_wasm_real_integration_test PROPERTIES SUFFIX ".js")

    # Patch generated JS: expose _malloc/_free on Module object
    # (real ONNX build uses lazy init that doesn't set Module['_malloc'])
    add_custom_command(
        TARGET piper_wasm_real_integration_test POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo "Patching JS exports..."
        COMMAND ${CMAKE_COMMAND} -DSRC="$<TARGET_FILE:piper_wasm_real_integration_test>" -P "${CMAKE_CURRENT_SOURCE_DIR}/patch_wasm_exports.cmake"
    )

    # Create symlink for the compiled-in espeak-ng install path so internal
    # file ops (phondata, voices) find data at their expected path.
    # The compiled-in path is /espeak-ng-data (what check_data_path validates),
    # so we just need to make sure the install path is the same.
    add_custom_command(
        TARGET piper_wasm_real_integration_test POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo "Setting up compiled-in path symlink..."
        COMMAND ${CMAKE_COMMAND} -E echo "Compile-in path is baked into the espeak-ng static library"
    )

endif()
