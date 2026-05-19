# Emscripten toolchain file for WASM builds
# Usage: cmake -B build -DCMAKE_TOOLCHAIN_FILE=wasm_tests/cmake/toolchain.cmake
#
# Sets emcc as the C/C++ compiler by delegating to find_emscripten.cmake.

# Delegate to find_emscripten.cmake (handles detection + download).
# find_emscripten.cmake sets CMAKE_C/CXX/ASM_COMPILER and returns.
include(${CMAKE_CURRENT_LIST_DIR}/find_emscripten.cmake)

# Verify emcc was found
if(NOT EMCC_PATH)
    message(FATAL_ERROR "emcc not found. Set EMSDK_ROOT or ensure emscripten is on PATH. "
            "Run cmake --build to trigger emscripten download.")
endif()

message(STATUS "Emscripten toolchain: emcc=${EMCC_PATH}")
