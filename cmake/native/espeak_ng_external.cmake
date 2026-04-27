# Shared CMake module: configure espeak-ng ExternalProject for native builds.
#
# Usage:
#   # Before calling, set PIPER_ESPEAKNG_* variables (see CMakeLists.txt examples)
#   include(native/espeak_ng_external)
#   configure_espeak_ng_external()
#
# Mandatory variable (set by caller):
#   PIPER_ESPEAKNG_UPDATE_DISCONNECTED  — ON to skip re-download
# Optional variable (set by caller for cross-compilation):
#   PIPER_ESPEAKNG_CMAKE_ARGS           — extra CMAKE_ARGS for ExternalProject

include(ExternalProject)
find_package(Patch QUIET)

function(configure_espeak_ng_external)
    # ── Mandatory variable check ─────────────────────────────
    foreach(_var
        PIPER_ESPEAKNG_UPDATE_DISCONNECTED
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

    # Guard with lib existence to avoid re-downloading/rebuilding when build dir already exists.
    if(EXISTS "${_ESPEAKNG_STATIC_LIB}")
        return()
    endif()

    # ── Compute patch paths ──
    # Prefer _repo_root set by caller (libpiper sets this), fall back to local dir
    if(DEFINED _repo_root)
        get_filename_component(_PROJECT_ROOT "${_repo_root}" ABSOLUTE)
    elseif(EXISTS "${CMAKE_CURRENT_LIST_DIR}/cmake-data.patch")
        get_filename_component(_PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}" ABSOLUTE)
    else()
        get_filename_component(_PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
    endif()
    set(_CROSS_PATCH "${_PROJECT_ROOT}/cmake/native/cmake-data.patch")

    ExternalProject_Add(espeak_ng_external
        GIT_REPOSITORY https://github.com/espeak-ng/espeak-ng.git
        GIT_TAG        83cb7ecf6f5f3e66014102b3d4a5823e60182055
        PREFIX         ${_ESPEAKNG_BUILD_DIR}

        CMAKE_ARGS
            -DCMAKE_INSTALL_PREFIX=${_ESPEAKNG_INSTALL_DIR}
            -DCMAKE_INSTALL_LIBDIR=lib
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
            "-DCMAKE_C_FLAGS=-D_FILE_OFFSET_BITS=64 -I${_ESPEAKNG_BUILD_DIR}/src/espeak_ng_external/src/ucd-tools/src/include"
            "-DCMAKE_CXX_FLAGS=-D_FILE_OFFSET_BITS=64 -I${_ESPEAKNG_BUILD_DIR}/src/espeak_ng_external/src/ucd-tools/src/include"
            ${PIPER_ESPEAKNG_CMAKE_ARGS}

        BUILD_BYPRODUCTS
            ${_ESPEAKNG_STATIC_LIB}

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
