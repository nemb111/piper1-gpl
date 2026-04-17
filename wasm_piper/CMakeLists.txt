# Compile piper.cpp to WebAssembly using mock libraries
#
# Uses the mock implementations from the parent tests/ directory to provide
# espeak-ng and ONNX Runtime function definitions so piper.cpp compiles
# without the real libraries.
#
# Build (WASM, from tests/ parent):
#   cmake -B build -DCMAKE_TOOLCHAIN_FILE=wasm_tests/cmake/toolchain.cmake
#   cmake --build build --target piper_wasm_compile_test_wasm
#
# Output: build/wasm_tests/piper_wasm_compile_test_wasm.wasm
#
# NOTE: This entire file is gated by IF(EMSCRIPTEN). It only takes effect
# when the emscripten toolchain file is provided (via -DCMAKE_TOOLCHAIN_FILE).
# Native builds ignore this subdirectory entirely.
#
# For native builds, use: cmake -B build && cmake --build build
#
cmake_minimum_required(VERSION 3.26)
project(wasm_piper)

add_subdirectory(../libpiper libpiper)

# Only build WASM targets when emscripten compiler is active
IF(NOT CMAKE_CXX_COMPILER MATCHES "emcc")
    # message(FATAL_ERROR "emcc not configured")
ENDIF()

# ── Build settings ─────────────────────────────────────────────────
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── WASM compile target (depends on parent's mock libraries) ─────────
add_library(piper_wasm_compile_test STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/../libpiper/src/piper.cpp"
)

target_include_directories(piper_wasm_compile_test PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/../libpiper/include"
)

target_link_libraries(piper_wasm_compile_test
    mock_onnxruntime
    espeakng_iface_lib
)

# ── WASM executable (produces .wasm) ──────────────────────────────
add_executable(piper_wasm_compile_test_wasm wasm_main.cpp)

target_link_libraries(piper_wasm_compile_test_wasm
    piper_wasm_compile_test
    mock_onnxruntime
    mock_espeak_ng
)

target_link_options(piper_wasm_compile_test_wasm PRIVATE
    -sSTANDALONE_WASM
    -sEXPORT_ALL
    -sALLOW_MEMORY_GROWTH
    -sMODULARIZE=1
    -sEXPORT_NAME="createModule"
    -sWASM_BIGINT=1
)
