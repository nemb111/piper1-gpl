# Emscripten module: native build + cross-compile as proper CMake targets.
#
# Workflow:
#   1. Native build via ExternalProject (espeak-ng built with emscripten toolchain)
#   2. Cross-compile via ExternalProject (rebuilds with toolchain file from native output)
#
# Usage:
#   include(emscripten/espeak_ng_external)
#   configure_espeak_ng_emscripten()

include(${CMAKE_CURRENT_LIST_DIR}/../native/espeak_ng_external.cmake)
find_package(Patch QUIET)

if(NOT EMCC_PATH)
    message(FATAL_ERROR
        "emcc not found. Set EMSDK_ROOT or ensure emscripten is on PATH. "
        "Run cmake --build to trigger emscripten download.")
endif()

function(configure_espeak_ng_emscripten)

    configure_espeak_ng_external()

    # ── Ensure `espeak_ng_external` target exists even if configure_espeak_ng_external
    #    returned early (lib already present).  The cross-compile step (espeak_ng_cross)
    #    declares `DEPENDS espeak_ng_external` in ExternalProject_Add — it must exist.
    if(NOT TARGET espeak_ng_external)
        add_custom_target(espeak_ng_external)
    endif()

    # ── Step 2: Cross-compile via ExternalProject (emscripten toolchain) ──
    # Restore emscripten for cross build — clear native compiler override
    set(PIPER_ESPEAKNG_CMAKE_ARGS "")
    get_filename_component(_EMSCRIPTEN_DIR "${EMCC_PATH}" DIRECTORY)
    set(EM_CMAKE_FILE "${_EMSCRIPTEN_DIR}/cmake/Modules/Platform/Emscripten.cmake")
    set(_ESPEAKNG_INSTALL_DIR "${CMAKE_BINARY_DIR}/espeak_ng-install")
    set(_ESPEAKNG_BUILD_DIR "${CMAKE_BINARY_DIR}/espeak_ng")

    # Download & extract to external/ so the source tree lives outside build/
    get_filename_component(_PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
    set(_ESPEAKNG_EXTERNAL_DIR "${_PROJECT_ROOT}/external/espeak_ng")
    set(_CROSS_PREFIX "${_ESPEAKNG_EXTERNAL_DIR}/cross")
    set(_CROSS_SRC_DIR "${_CROSS_PREFIX}/src/espeak_ng_cross")
    set(_CROSS_BUILD_DIR "${_CROSS_SRC_DIR}-build")
    set(_NATIVE_BUILD_SRC "${_ESPEAKNG_BUILD_DIR}/src/espeak_ng_external-build")
    set(_CROSS_UCD_LIB "${_CROSS_BUILD_DIR}/src/ucd-tools/libucd.a")

    # Cross-compile needs its own install dir so the EXISTS check doesn't block it
    set(_CROSS_INSTALL_DIR "${CMAKE_BINARY_DIR}/espeak_ng-cross-install")
    set(_CROSS_ESPEAKNG_LIB "${_CROSS_INSTALL_DIR}/lib/libespeak-ng.a")
    set(_ESPEAKNG_INSTALL_DIR_OVERRIDE "${_CROSS_INSTALL_DIR}")

    configure_espeak_ng_external(
        TARGET_NAME espeak_ng_cross
        UPDATE_DISCONNECTED ON
        PREFIX ${_CROSS_PREFIX}
        C_FLAGS ""
        CXX_FLAGS ""
        EXTRA_CMAKE_ARGS -DCMAKE_TOOLCHAIN_FILE=${EM_CMAKE_FILE} -DNativeBuild_DIR=${_NATIVE_BUILD_SRC}/build/src
        DEPENDS espeak_ng_external
    )

    # ── After cross-configure, set up imported targets with cross-compiled paths ──
    if(NOT TARGET espeakng)
        add_library(espeakng STATIC IMPORTED)
        set_target_properties(espeakng PROPERTIES IMPORTED_LOCATION ${_CROSS_ESPEAKNG_LIB})
    else()
        set_target_properties(espeakng PROPERTIES IMPORTED_LOCATION ${_CROSS_ESPEAKNG_LIB})
    endif()

    if(NOT TARGET ucd)
        add_library(ucd STATIC IMPORTED)
    endif()
    set_target_properties(ucd PROPERTIES IMPORTED_LOCATION ${_CROSS_UCD_LIB})

    # ── Ensure espeakng_iface_lib uses cross-compiled targets ──
    if(NOT TARGET espeakng_iface_lib)
        add_library(espeakng_iface_lib INTERFACE)
        target_link_libraries(espeakng_iface_lib INTERFACE espeakng ucd)
    endif()
    set_target_properties(espeakng_iface_lib PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${_CROSS_INSTALL_DIR}/include"
    )
endfunction()
