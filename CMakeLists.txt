# Builds Python module for Piper using espeak-ng and cmake.
#
# This is called automatically by scikit-build from setup.py.
cmake_minimum_required(VERSION 3.26)
project(piper LANGUAGES C CXX)

include(ExternalProject)

# scikit-build-core will forward Python_* variables
find_package(Python COMPONENTS Development.Module Development.SABIModule REQUIRED)


include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/native/espeak_ng_external.cmake)
configure_espeak_ng_external()

set(ESPEAKNG_INSTALL_DIR ${CMAKE_BINARY_DIR}/espeak_ng-install)

if(WIN32)
    set(ESPEAKNG_STATIC_LIB ${ESPEAKNG_INSTALL_DIR}/lib/espeak-ng.lib)
    set(UCD_STATIC_LIB ${CMAKE_BINARY_DIR}/espeak_ng/src/espeak_ng_external-build/src/ucd-tools/libucd.lib)
else()
    set(ESPEAKNG_STATIC_LIB ${ESPEAKNG_INSTALL_DIR}/lib/libespeak-ng.a)
    set(UCD_STATIC_LIB ${CMAKE_BINARY_DIR}/espeak_ng/src/espeak_ng_external-build/src/ucd-tools/libucd.a)
endif()

include_directories(
    ${ESPEAKNG_INSTALL_DIR}/include
)

# espeak bridge
add_library(espeakbridge MODULE
    src/piper/espeakbridge.c
)

add_dependencies(espeakbridge espeak_ng_external)
target_link_libraries(espeakbridge
    ${ESPEAKNG_STATIC_LIB}
    ${UCD_STATIC_LIB}
    Python::SABIModule
)
target_include_directories(espeakbridge PRIVATE
    ${ESPEAKNG_INSTALL_DIR}/include
)

if(WIN32)
    # Fix dll thunk issue (__imp_SYMBOL not found)
    target_compile_definitions(espeakbridge PRIVATE LIBESPEAK_NG_EXPORT)

    # Fix .dll suffix
    set_target_properties(espeakbridge PROPERTIES
        PREFIX ""
        SUFFIX ".pyd"
    )
else()
    set_target_properties(espeakbridge PROPERTIES
        PREFIX ""
    )
endif()

install(TARGETS espeakbridge
    LIBRARY DESTINATION .
    RUNTIME DESTINATION .
)

# Copy espeak-ng-data
set(DATA_SRC ${ESPEAKNG_INSTALL_DIR}/share/espeak-ng-data)
set(DATA_DST ${CMAKE_CURRENT_SOURCE_DIR}/src/piper/espeak-ng-data)

add_custom_target(copy_espeak_ng_data ALL
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${DATA_SRC} ${DATA_DST}
    DEPENDS espeak_ng_external
    COMMENT "Copying espeak-ng-data after espeak-ng external project builds"
)
