# Shared CMake module: configure espeak-ng ExternalProject for native or WASM builds.
#
# Usage:
#   # Before calling, set PIPER_ESPEAKNG_* variables (see CMakeLists.txt examples)
#   include(espeak_ng_external)
#   configure_espeak_ng_external([PREBUILT_DATA_DIR])
#
# Mandatory variables (set by caller):
#   PIPER_ESPEAKNG_UPDATE_DISCONNECTED  — ON for native (skip re-download), OFF for WASM
#   PIPER_ESPEAKNG_PATCH_SCRIPT         — absolute path to cmake/patch_espeak_data.sh
# Optional variable (set by caller for cross-compilation):
#   PIPER_ESPEAKNG_CMAKE_ARGS           — extra CMAKE_ARGS for ExternalProject
#
# Optional argument:
#   PREBUILT_DATA_DIR                   — path to prebuilt espeak-ng-data (WASM only)

include(ExternalProject)

function(configure_espeak_ng_external)
    set(_prebuilt "")
    if(ARGN)
        list(GET ARGN 0 _prebuilt)
    endif()

    # ── Mandatory variable check ─────────────────────────────
    foreach(_var
        PIPER_ESPEAKNG_UPDATE_DISCONNECTED
        PIPER_ESPEAKNG_PATCH_SCRIPT
    )
        if(NOT DEFINED ${_var})
            message(FATAL_ERROR "Missing mandatory toolchain variable: ${_var}. "
                    "Set it before calling configure_espeak_ng_external().")
        endif()
    endforeach()

    set(_ESPEAKNG_BUILD_DIR   "${CMAKE_BINARY_DIR}/espeak_ng")
    set(_ESPEAKNG_INSTALL_DIR "${CMAKE_BINARY_DIR}/espeak_ng-install")

    set(_ESPEAKNG_BUILD_SRC  "${_ESPEAKNG_BUILD_DIR}/src/espeak_ng_external-build")

    if(WIN32)
        set(_ESPEAKNG_STATIC_LIB ${_ESPEAKNG_INSTALL_DIR}/lib/espeak-ng.lib)
        set(_UCD_STATIC_LIB      ${_ESPEAKNG_BUILD_SRC}/src/ucd-tools/libucd.lib)
    else()
        set(_ESPEAKNG_STATIC_LIB ${_ESPEAKNG_INSTALL_DIR}/lib/libespeak-ng.a)
        set(_UCD_STATIC_LIB      ${_ESPEAKNG_BUILD_SRC}/src/ucd-tools/libucd.a)
    endif()

    # WASM-only: remove cached source so PATCH_COMMAND always runs (shallow clone is fast)
    if(_prebuilt)
        file(REMOVE_RECURSE "${_ESPEAKNG_BUILD_DIR}/src/espeak_ng_external")
    endif()

    # UCD include: needed for native builds (ucd-tools source lives in the git clone)
    # For WASM builds, ucd-tools is disabled so this is empty.
    set(_ucd_include "")
    if(NOT _prebuilt)
        set(_ucd_include " -I${_ESPEAKNG_BUILD_DIR}/src/espeak_ng_external/src/ucd-tools/src/include")
    endif()

    ExternalProject_Add(espeak_ng_external
        GIT_REPOSITORY https://github.com/espeak-ng/espeak-ng.git
        GIT_TAG        212928b394a96e8fd2096616bfd54e17845c48f6
        PREFIX         ${_ESPEAKNG_BUILD_DIR}

        PATCH_COMMAND
            bash ${PIPER_ESPEAKNG_PATCH_SCRIPT} <SOURCE_DIR> ${_prebuilt}

        CMAKE_ARGS
            -DCMAKE_INSTALL_PREFIX=${_ESPEAKNG_INSTALL_DIR}
            -DBUILD_SHARED_LIBS:BOOL=OFF
            -DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON
            -DUSE_ASYNC:BOOL=OFF
            -DUSE_MBROLA:BOOL=OFF
            -DUSE_LIBSONIC:BOOL=OFF
            -DUSE_LIBPCAUDIO:BOOL=OFF
            -DUSE_KLATT:BOOL=OFF
            -DUSE_SPEECHPLAYER:BOOL=OFF
            -DEXTRA_cmn:BOOL=ON
            -DEXTRA_ru:BOOL=ON
            "-DCMAKE_C_FLAGS=-D_FILE_OFFSET_BITS=64${_ucd_include}"
            "-DCMAKE_CXX_FLAGS=-D_FILE_OFFSET_BITS=64${_ucd_include}"
            ${PIPER_ESPEAKNG_CMAKE_ARGS}

        BUILD_BYPRODUCTS
            ${_ESPEAKNG_STATIC_LIB}
            ${_UCD_STATIC_LIB}

        UPDATE_DISCONNECTED ${PIPER_ESPEAKNG_UPDATE_DISCONNECTED}
    )

    add_library(espeakng STATIC IMPORTED)
    add_dependencies(espeakng espeak_ng_external)
    set_target_properties(espeakng PROPERTIES
        IMPORTED_LOCATION ${_ESPEAKNG_STATIC_LIB}
    )

    add_library(ucd STATIC IMPORTED)
    add_dependencies(ucd espeak_ng_external)
    set_target_properties(ucd PROPERTIES
        IMPORTED_LOCATION ${_UCD_STATIC_LIB}
    )

    add_library(espeakng_iface_lib INTERFACE)
    add_dependencies(espeakng_iface_lib espeak_ng_external)
    target_link_libraries(espeakng_iface_lib INTERFACE espeakng ucd)
    target_include_directories(espeakng_iface_lib INTERFACE
        ${_ESPEAKNG_INSTALL_DIR}/include
    )
endfunction()
