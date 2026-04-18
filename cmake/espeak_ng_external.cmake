# Shared CMake module: configure espeak-ng ExternalProject for native or WASM builds.
# Usage: include(espeak_ng_external)
#        configure_espeak_ng_external([PREBUILT_DATA_DIR])

include(ExternalProject)
#
# When PREBUILT_DATA_DIR is provided (WASM builds), the patch script is invoked.
# When not provided (native builds), UPDATE_DISCONNECTED and UCD include path are used.

function(configure_espeak_ng_external)
    set(_prebuilt "")
    if(ARGN)
        list(GET ARGN 0 _prebuilt)
    endif()

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

    # Auto-detect WASM vs native via EMCC_PATH (set by emscripten/toolchain.cmake)
    set(_is_wasm OFF)
    if(DEFINED EMCC_PATH)
        set(_is_wasm ON)
    endif()

    # WASM-only: remove cached source so patch always runs (shallow clone is fast)
    if(_is_wasm)
        file(REMOVE_RECURSE "${_ESPEAKNG_BUILD_DIR}/src/espeak_ng_external")
    endif()

    # ── UCD include (native-only, empty for WASM) ─────────────────
    set(_ucd_include "")
    if(NOT _is_wasm)
        set(_ucd_include " -I${_ESPEAKNG_BUILD_DIR}/src/espeak_ng_external/src/ucd-tools/src/include")
    endif()

    # Compute absolute path to patch script (repo root relative to this module)
    get_filename_component(_repo_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
    set(_patch_script "${_repo_root}/cmake/patch_espeak_data.sh")

    ExternalProject_Add(espeak_ng_external
        GIT_REPOSITORY https://github.com/espeak-ng/espeak-ng.git
        GIT_TAG        212928b394a96e8fd2096616bfd54e17845c48f6
        PREFIX         ${_ESPEAKNG_BUILD_DIR}

        PATCH_COMMAND
            bash ${_patch_script} <SOURCE_DIR> ${_prebuilt}

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

        BUILD_BYPRODUCTS
            ${_ESPEAKNG_STATIC_LIB}
            ${_UCD_STATIC_LIB}

        # Native-only: do not re-download on every configure
        UPDATE_DISCONNECTED ${_is_wasm}
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
