cmake_minimum_required(VERSION 3.26)

project(wasm_piper)

enable_language(C)
enable_language(CXX)

include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/emscripten/espeak_ng_external.cmake)

# Required by configure_espeak_ng_external() called inside configure_espeak_ng_emscripten()
set(PIPER_ESPEAKNG_UPDATE_DISCONNECTED ON)
configure_espeak_ng_emscripten()

add_custom_target(build_espeak_wasm ALL)
add_dependencies(build_espeak_wasm espeak_ng_cross)
