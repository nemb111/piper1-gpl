# Piper Tests CMake Configuration
#
# This CMakeLists.txt provides a modular test target for piper tests.
# It exports mock libraries and provides easy integration with the parent piper CMakeLists.txt
#

cmake_minimum_required(VERSION 3.26)
project(piper_tests LANGUAGES C CXX)

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

# BEGIN - DO NOT MODIFY!!!
add_library(piper_compile_test STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/../src/piper.cpp"
)

target_include_directories(piper_compile_test PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/../include"
)

target_compile_definitions(piper_compile_test PRIVATE MOCK_BUILD)

target_link_libraries(piper_compile_test mock_onnxruntime espeakng_iface_lib)
# END - DO NOT MODIFY!!!


# =============================================================================
# Test Subdirectories
# =============================================================================

# smoke/  - fast compile-time API consistency checks
# mock/   - full GTest suites and examples using mock libraries
add_subdirectory(smoke)
add_subdirectory(mock)


