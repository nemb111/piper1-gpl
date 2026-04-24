cmake_minimum_required(VERSION 3.26)

include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/emscripten/espeak_ng_external.cmake)

add_custom_target(build_espeak_wasm ALL espeak_ng_cross)
