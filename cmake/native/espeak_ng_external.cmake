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

# Get common CMAKE_ARGS shared between native and cross-compilation builds
function(get_espeak_ng_common_cmake_args INSTALL_DIR OUT_VAR)
    set(${OUT_VAR}
        -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}
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
        PARENT_SCOPE
    )
endfunction()

# Create imported targets for espeak-ng libraries
function(create_espeak_ng_targets TARGET_NAME BUILD_SRC INSTALL_DIR STATIC_LIB UCD_LIB)
    if(NOT TARGET espeakng)
        add_library(espeakng STATIC IMPORTED)
    endif()
    add_dependencies(espeakng ${TARGET_NAME})
    set_target_properties(espeakng PROPERTIES
        IMPORTED_LOCATION ${STATIC_LIB}
    )

    if(NOT TARGET ucd)
        add_library(ucd STATIC IMPORTED)
    endif()
    add_dependencies(ucd ${TARGET_NAME})
    set_target_properties(ucd PROPERTIES
        IMPORTED_LOCATION ${UCD_LIB}
    )

    if(NOT TARGET espeakng_iface_lib)
        add_library(espeakng_iface_lib INTERFACE)
        target_link_libraries(espeakng_iface_lib INTERFACE espeakng ucd)
        target_include_directories(espeakng_iface_lib INTERFACE
            ${INSTALL_DIR}/include
        )
    endif()
    add_dependencies(espeakng_iface_lib ${TARGET_NAME})
endfunction()

function(configure_espeak_ng_external)
    # Optional parameters for flexibility
    set(options "")
    set(oneValueArgs TARGET_NAME UPDATE_DISCONNECTED EXTRA_CMAKE_ARGS_PREFIX PREFIX C_FLAGS CXX_FLAGS SRC_DIR)
    set(multiValueArgs EXTRA_CMAKE_ARGS DEPENDS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Set defaults
    if(NOT ARG_TARGET_NAME)
        set(ARG_TARGET_NAME espeak_ng_external)
    endif()
    if(NOT ARG_UPDATE_DISCONNECTED)
        set(ARG_UPDATE_DISCONNECTED ${PIPER_ESPEAKNG_UPDATE_DISCONNECTED})
    endif()
    if(NOT ARG_EXTRA_CMAKE_ARGS_PREFIX)
        set(ARG_EXTRA_CMAKE_ARGS_PREFIX ${PIPER_ESPEAKNG_CMAKE_ARGS})
    endif()
    if(NOT ARG_PREFIX)
        set(ARG_PREFIX "${CMAKE_BINARY_DIR}/espeak_ng")
    endif()
    if(NOT ARG_C_FLAGS)
        set(ARG_C_FLAGS "-D_FILE_OFFSET_BITS=64 -I${ARG_PREFIX}/src/${ARG_TARGET_NAME}/src/ucd-tools/src/include")
    endif()
    if(NOT ARG_CXX_FLAGS)
        set(ARG_CXX_FLAGS "-D_FILE_OFFSET_BITS=64 -I${ARG_PREFIX}/src/${ARG_TARGET_NAME}/src/ucd-tools/src/include")
    endif()

    if(NOT ARG_SRC_DIR)
        set(ARG_SRC_DIR "")
    endif()

    # ── Mandatory variable check ─────────────────────────────
    if(NOT ARG_UPDATE_DISCONNECTED)
        message(FATAL_ERROR "Missing mandatory toolchain variable: UPDATE_DISCONNECTED. "
                "Set it before calling configure_espeak_ng_external().")
    endif()

    set(_ESPEAKNG_BUILD_DIR   "${ARG_PREFIX}")
    if(NOT DEFINED _ESPEAKNG_INSTALL_DIR_OVERRIDE)
        set(_ESPEAKNG_INSTALL_DIR "${CMAKE_BINARY_DIR}/espeak_ng-install")
    else()
        set(_ESPEAKNG_INSTALL_DIR "${_ESPEAKNG_INSTALL_DIR_OVERRIDE}")
    endif()

    set(_ESPEAKNG_BUILD_SRC  "${_ESPEAKNG_BUILD_DIR}/src/${ARG_TARGET_NAME}-build")

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

    # Get common args
    get_espeak_ng_common_cmake_args(${_ESPEAKNG_INSTALL_DIR} _COMMON_ARGS)

    set(_CMAKE_ARGS ${_COMMON_ARGS})
    if(ARG_C_FLAGS)
        list(APPEND _CMAKE_ARGS "-DCMAKE_C_FLAGS=${ARG_C_FLAGS}")
    endif()
    if(ARG_CXX_FLAGS)
        list(APPEND _CMAKE_ARGS "-DCMAKE_CXX_FLAGS=${ARG_CXX_FLAGS}")
    endif()
    list(APPEND _CMAKE_ARGS ${ARG_EXTRA_CMAKE_ARGS_PREFIX})
    list(APPEND _CMAKE_ARGS ${ARG_EXTRA_CMAKE_ARGS})

    if(ARG_SRC_DIR AND EXISTS "${ARG_SRC_DIR}")
        # Use user-provided source directory instead of git clone
        ExternalProject_Add(${ARG_TARGET_NAME}
            SOURCE_DIR ${ARG_SRC_DIR}
            PREFIX     ${_ESPEAKNG_BUILD_DIR}

            CMAKE_ARGS
                ${_CMAKE_ARGS}

            BUILD_BYPRODUCTS
                ${_ESPEAKNG_STATIC_LIB}
                ${_UCD_STATIC_LIB}

            UPDATE_DISCONNECTED ${ARG_UPDATE_DISCONNECTED}

            DEPENDS ${ARG_DEPENDS}
        )
    else()
        # Default: clone from git
        ExternalProject_Add(${ARG_TARGET_NAME}
            GIT_REPOSITORY https://github.com/espeak-ng/espeak-ng.git
            GIT_TAG        83cb7ecf6f5f3e66014102b3d4a5823e60182055
            PREFIX         ${_ESPEAKNG_BUILD_DIR}

            CMAKE_ARGS
                ${_CMAKE_ARGS}

            BUILD_BYPRODUCTS
                ${_ESPEAKNG_STATIC_LIB}
                ${_UCD_STATIC_LIB}

            UPDATE_DISCONNECTED ${ARG_UPDATE_DISCONNECTED}

            DEPENDS ${ARG_DEPENDS}
        )
    endif()

    create_espeak_ng_targets(${ARG_TARGET_NAME} ${_ESPEAKNG_BUILD_SRC} ${_ESPEAKNG_INSTALL_DIR} ${_ESPEAKNG_STATIC_LIB} ${_UCD_STATIC_LIB})
endfunction()
