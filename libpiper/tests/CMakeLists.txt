# Piper Tests CMake Configuration
#
# This CMakeLists.txt provides a modular test target for piper tests.
# It exports mock libraries and provides easy integration with the parent piper CMakeLists.txt
#

cmake_minimum_required(VERSION 3.26)

# =============================================================================
# Mock Libraries
# =============================================================================

# Mock espeak-ng API library
add_library(mock_espeak_ng STATIC
    mock_espeak_ng.cpp
)

target_include_directories(mock_espeak_ng PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(mock_espeak_ng PUBLIC cxx_std_17)

# Mock ONNX Runtime API library
add_library(mock_onnxruntime STATIC
    mock_onnxruntime.cpp
)

target_include_directories(mock_onnxruntime PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(mock_onnxruntime PUBLIC cxx_std_17)

# =============================================================================
# Test Executables
# =============================================================================

# Main test executable with Google Test
if(TARGET piper)
    add_executable(test_simple
        test_simple.cpp
    )

    target_link_libraries(test_simple PRIVATE
        piper
        mock_espeak_ng
        mock_onnxruntime
        GTest::gtest_main
    )

    add_dependencies(test_simple
        piper
        mock_espeak_ng
        mock_onnxruntime
    )

endif()

# =============================================================================
# Test Configuration Options
# =============================================================================

# Enable/disable compile tests
option(PIPER_ENABLE_COMPILE_TESTS "Enable compile-time API verification" ON)

# =============================================================================
# Compile-Test Workflow
# =============================================================================
#
# To perform compile-time API verification:
#
# 1. Build tests with mocks:
#    cmake -B build -DPIPER_ENABLE_COMPILE_TESTS=ON
#    cmake --build build
#
# 2. Swap mock libraries with real implementations:
#    Replace piper_mock_espeak_ng with libespeak-ng.a
#    Replace piper_mock_onnxruntime with onnxruntime.so
#
# 3. Rebuild:
#    cmake --build build
#
# 4. Successful compilation = API compatibility verified
#
# =============================================================================