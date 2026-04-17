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
add_library(mock_onnxruntime INTERFACE
    mock_onnxruntime.cpp
)

target_include_directories(mock_onnxruntime INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(mock_onnxruntime INTERFACE cxx_std_17)

# =============================================================================
# espeak-ng Compile Test Library
# =============================================================================

# espeak-ng compile test library - verifies espeak-ng API compilation
# This library provides a clean espeak-ng API interface for compile tests
add_library(espeak_compile_test_lib STATIC
    test_espeak_compile.cpp
)

target_include_directories(espeak_compile_test_lib PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_BINARY_DIR}/espeak_ng-install/include
)

# Link against the actual espeak-ng library
target_link_libraries(espeak_compile_test_lib PUBLIC
    ${ESPEAKNG_STATIC_LIB}
    ${UCD_STATIC_LIB}
)

target_compile_features(espeak_compile_test_lib PUBLIC cxx_std_17)

# Target alias for explicit namespace scoping (CMake 3.30+)
if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.30.0")
    namespace_alias(piper::test::espeak_compile espeak_compile_test_lib)
else()
    # For older CMake versions, use a simple target name
    add_library(piper::test::espeak_compile ALIAS espeak_compile_test_lib)
endif()

add_library(piper_compile_test STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/../src/piper.cpp"
)

target_include_directories(piper_compile_test PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/../include"
)

target_link_libraries(piper_compile_test onnxruntime_iface_lib espeakng_iface_lib)


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
    

    # espeak-ng compile test executable (uses ONNX Runtime mocks)
    add_executable(espeak_compile_test
        test_espeak_compile.cpp
    )

    target_link_libraries(espeak_compile_test PRIVATE
        piper
        espeak_compile_test_lib
        mock_espeak_ng
        mock_onnxruntime
        GTest::gtest_main
    )

    add_dependencies(espeak_compile_test
        espeak_ng_external
        piper
        espeak_compile_test_lib
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