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
    # Path to the emscripten-specific patch for espeak-ng CMake data handling
    get_filename_component(_EMSCRIPTEN_PATCH "${CMAKE_CURRENT_LIST_DIR}/../cmake/emscripten/cmake-data.patch" ABSOLUTE)

    configure_espeak_ng_external()

    # ── Step 2: Cross-compile via ExternalProject (emscripten toolchain) ──
    # Restore emscripten for cross build — clear native compiler override
    set(PIPER_ESPEAKNG_CMAKE_ARGS "")
    get_filename_component(_EMSCRIPTEN_DIR "${EMCC_PATH}" DIRECTORY)
    set(EM_CMAKE_FILE "${_EMSCRIPTEN_DIR}/cmake/Modules/Platform/Emscripten.cmake")
    set(_ESPEAKNG_BUILD_DIR "${CMAKE_BINARY_DIR}/espeak_ng")
    set(_ESPEAKNG_INSTALL_DIR "${CMAKE_BINARY_DIR}/espeak_ng-install")
    set(_NATIVE_BUILD_SRC "${_ESPEAKNG_BUILD_DIR}/src/espeak_ng_external-build")

    ExternalProject_Add(espeak_ng_cross
        PREFIX ${_ESPEAKNG_BUILD_DIR}/cross
        GIT_REPOSITORY https://github.com/espeak-ng/espeak-ng.git
        GIT_TAG        724808c5a83f9ef95fdd0db886ba7ba537ff224a
        UPDATE_DISCONNECTED ON

        PATCH_COMMAND
            ${Patch_EXECUTABLE} -p1 -i "${_EMSCRIPTEN_PATCH}"

        CMAKE_ARGS
            -DCMAKE_TOOLCHAIN_FILE=${EM_CMAKE_FILE}
            -DNativeBuild_DIR=${_NATIVE_BUILD_SRC}/build/src
            -DCMAKE_INSTALL_PREFIX=${_ESPEAKNG_INSTALL_DIR}
            -DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON
            -DBUILD_SHARED_LIBS:BOOL=OFF

        BUILD_BYPRODUCTS
            ${_ESPEAKNG_INSTALL_DIR}/lib/libespeak-ng.a
            ${_NATIVE_BUILD_SRC}/src/ucd-tools/libucd.a

        DEPENDS espeak_ng_external
    )

    # ── Reuse interface library from native module ──
    # The native module defines espeakng_iface_lib INTERFACE target.
    # Cross build produces the same outputs, so the interface is shared.
    if(TARGET espeakng)
        set_target_properties(espeakng PROPERTIES
            IMPORTED_LOCATION ${_ESPEAKNG_INSTALL_DIR}/lib/libespeak-ng.a
        )
        add_dependencies(espeakng espeak_ng_cross)
    endif()
    if(TARGET ucd)
        set_target_properties(ucd PROPERTIES
            IMPORTED_LOCATION ${_NATIVE_BUILD_SRC}/src/ucd-tools/libucd.a
        )
        add_dependencies(ucd espeak_ng_cross)
    endif()
endfunction()
