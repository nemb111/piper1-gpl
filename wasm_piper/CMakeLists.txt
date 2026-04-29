cmake_minimum_required(VERSION 3.26)

project(wasm_piper)

enable_language(C)
enable_language(CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Repo root (needed by cmake/emscripten/espeak_ng_external.cmake fallback) ──
get_filename_component(_repo_root "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)

include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/emscripten/espeak_ng_external.cmake)
include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/onnxruntime_web_external.cmake)

# ── Required by configure_espeak_ng_external() called inside configure_espeak_ng_emscripten() ──
set(PIPER_ESPEAKNG_UPDATE_DISCONNECTED ON)
configure_espeak_ng_emscripten()

add_custom_target(build_espeak_wasm ALL)
add_dependencies(build_espeak_wasm espeak_ng_cross)

# ── Add libpiper/include to espeakng_iface_lib (transitively for piper.cpp) ──
target_include_directories(espeakng_iface_lib INTERFACE
    ${_repo_root}/libpiper/include
)

# ── Mock ONNX Runtime (WASM: real ONNX Runtime not available) ──
# Carries all deps: libpiper/include, libpiper/tests, MOCK_BUILD define.

add_library(mock_onnxruntime
    ${CMAKE_CURRENT_SOURCE_DIR}/../libpiper/tests/mock_onnxruntime.cpp
)
target_include_directories(mock_onnxruntime PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/../libpiper/tests
)
target_compile_definitions(mock_onnxruntime PUBLIC MOCK_BUILD)
add_dependencies(mock_onnxruntime espeak_ng_cross)

# ── Piper WASM executable ──

add_executable(piper_wasm piper_wasm.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../libpiper/src/piper.cpp
)

set_target_properties(piper_wasm PROPERTIES
    LINK_FLAGS "-s ALLOW_MEMORY_GROWTH=1"
)

# mock_onnxruntime carries: libpiper/include (via espeakng_iface_lib), libpiper/tests, MOCK_BUILD
# espeakng_iface_lib carries: espeak-ng include + libs
target_link_libraries(piper_wasm
    PRIVATE
        mock_onnxruntime
        espeakng_iface_lib
)
add_dependencies(piper_wasm espeak_ng_cross)  

configure_onnxruntime_web_external()
# onnxruntime_web_external.cmake is not included (mock ONNX used for WASM)
add_custom_target(build_onnxruntime_web ALL)
add_dependencies(build_onnxruntime_web onnxruntime_web_iface_lib)
