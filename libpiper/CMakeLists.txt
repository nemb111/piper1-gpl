# Builds libpiper
cmake_minimum_required(VERSION 3.26)
project(piper LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Native build options (versions, flags, etc.) ──
include(${CMAKE_CURRENT_LIST_DIR}/../cmake/native/options.cmake)

include(${CMAKE_CURRENT_LIST_DIR}/../cmake/native/espeak_ng_external.cmake)
configure_espeak_ng_external()


include(${CMAKE_CURRENT_LIST_DIR}/../cmake/native/onnxruntime_external.cmake)
configure_onnxruntime_external()

# ---- libpiper ---

add_library(piper SHARED
    ${CMAKE_CURRENT_SOURCE_DIR}/src/piper.cpp
)

target_include_directories(piper PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(piper
    espeakng_iface_lib
    onnxruntime_iface_lib
)

# ---- install ---

include(GNUInstallDirs)

install(TARGETS piper
    DESTINATION ${CMAKE_INSTALL_PREFIX}
)

install(
    FILES ${CMAKE_CURRENT_SOURCE_DIR}/include/piper.h
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(
    DIRECTORY ${ONNXRUNTIME_DIR}/lib/
    DESTINATION ${CMAKE_INSTALL_LIBDIR}
)


