# Builds native_divergence_test executable for cross-variant audio comparison.
#
# Build:
#   cmake -B tests/divergence_tests/build -S tests/divergence_tests
#   cmake --build tests/divergence_tests/build

cmake_minimum_required(VERSION 3.26)
project(native_divergence_test LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── libpiper (handles espeak-ng + onnxruntime setup) ──
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../libpiper libpiper_build)

# ── Test executable ──
add_executable(native_divergence_test
    ${CMAKE_CURRENT_SOURCE_DIR}/src/native_synthesis.cpp
)

target_link_libraries(native_divergence_test PRIVATE piper)
