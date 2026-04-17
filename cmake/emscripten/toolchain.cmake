# Emscripten toolchain file for WASM builds
# Usage: cmake -B build -DCMAKE_TOOLCHAIN_FILE=wasm_tests/cmake/toolchain.cmake
#
# Sets emcc as the C/C++ compiler by auto-detecting it on PATH or downloading it.
# Guard: if EMCC_PATH was already set, skip to avoid running twice.

if(DEFINED EMCC_PATH)
    return()
endif()

# ── Configuration ──────────────────────────────────────────────
set(EMSCRIPTEN_VERSION "latest" CACHE STRING "Emscripten version (e.g. 'latest', '3.1.64')")
set(_EMSDK_DIR "${CMAKE_CURRENT_LIST_DIR}/../emscripten_download")

# ── Attempt detection ─────────────────────────────────────────
find_program(EMCC_PATH NAMES emcc PATHS ENV PATH NO_CACHE)

if(EMCC_PATH)
    execute_process(
        COMMAND "${EMCC_PATH}" -v
        ERROR_VARIABLE  _EMCC_VERSION_ERR
        RESULT_VARIABLE _EMCC_VERSION_RC
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE
    )
    if(_EMCC_VERSION_RC EQUAL 0 AND _EMCC_VERSION_ERR MATCHES "emcc \\(Emscripten[^)]+\\)[ ]+([0-9]+\\.[0-9]+\\.[0-9]+)" )
        message(STATUS "Emscripten found: ${EMCC_PATH} (version ${CMAKE_MATCH_1})")
        set(CMAKE_C_COMPILER "${EMCC_PATH}" CACHE FILEPATH "C compiler (emscripten)" FORCE)
        set(CMAKE_CXX_COMPILER "${EMCC_PATH}" CACHE FILEPATH "C++ compiler (emscripten)" FORCE)
        set(CMAKE_ASM_COMPILER "${EMCC_PATH}" CACHE FILEPATH "ASM compiler (emscripten)" FORCE)
        return()
    endif()
endif()

message(STATUS "Emscripten not found on PATH — downloading SDK to ${_EMSDK_DIR}")

# ── Download emsdk via emsdk auto-archive tarball ──────────────
set(_EMSDK_ARCHIVE "${_EMSDK_DIR}/emsdk-package.tar.gz")
set(_EMSDK_SRC_DIR "${_EMSDK_DIR}/emsdk")
set(_EMSDK_UPSTREAM "${_EMSDK_DIR}/emsdk/upstream")

if(NOT EXISTS "${_EMSDK_SRC_DIR}/emsdk.py")
    message(STATUS "Downloading emsdk ...")
    file(DOWNLOAD
        "https://github.com/emscripten-core/emsdk/archive/refs/heads/master.tar.gz"
        "${_EMSDK_ARCHIVE}"
        SHOW_PROGRESS
        STATUS _dl_status
    )
    list(GET _dl_status 0 _dl_code)
    if(NOT _dl_code EQUAL 0)
        list(GET _dl_status 1 _dl_msg)
        message(FATAL_ERROR "Failed to download emsdk: code=${_dl_code} msg=${_dl_msg}")
    endif()
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E tar xf "${_EMSDK_ARCHIVE}"
        WORKING_DIRECTORY "${_EMSDK_DIR}"
        RESULT_VARIABLE _untar_rc
    )
    if(NOT _untar_rc EQUAL 0)
        message(FATAL_ERROR "Failed to extract emsdk archive")
    endif()
    if(EXISTS "${_EMSDK_DIR}/emsdk-master")
        file(RENAME "${_EMSDK_DIR}/emsdk-master" "${_EMSDK_SRC_DIR}")
    endif()
endif()

if(NOT EXISTS "${_EMSDK_UPSTREAM}/emscripten")
    message(STATUS "Installing Emscripten ${EMSCRIPTEN_VERSION} ...")
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E env
            PATH="${_EMSDK_SRC_DIR}:$ENV{PATH}"
            python3 "${_EMSDK_SRC_DIR}/emsdk.py" install "${EMSCRIPTEN_VERSION}"
        WORKING_DIRECTORY "${_EMSDK_DIR}"
        RESULT_VARIABLE _install_rc
    )
    if(NOT _install_rc EQUAL 0)
        message(FATAL_ERROR "emsdk install ${EMSCRIPTEN_VERSION} failed (rc=${_install_rc})")
    endif()

    execute_process(
        COMMAND ${CMAKE_COMMAND} -E env
            PATH="${_EMSDK_SRC_DIR}:$ENV{PATH}"
            python3 "${_EMSDK_SRC_DIR}/emsdk.py" activate "${EMSCRIPTEN_VERSION}"
        WORKING_DIRECTORY "${_EMSDK_DIR}"
        RESULT_VARIABLE _activate_rc
    )
    if(NOT _activate_rc EQUAL 0)
        message(FATAL_ERROR "emsdk activate ${EMSCRIPTEN_VERSION} failed (rc=${_activate_rc})")
    endif()
endif()

get_filename_component(_real_dir "${_EMSDK_DIR}" REALPATH)
set(EMSDK_ROOT "${_real_dir}" CACHE PATH "Emscripten SDK root")
set(EMCC_PATH "${_real_dir}/emsdk/upstream/emscripten/emcc" CACHE FILEPATH "Path to emcc" FORCE)

if(NOT EXISTS "${EMCC_PATH}")
    message(FATAL_ERROR "emcc not found at ${EMCC_PATH} after install")
endif()

set(CMAKE_C_COMPILER "${EMCC_PATH}" CACHE FILEPATH "C compiler (emscripten)" FORCE)
set(CMAKE_CXX_COMPILER "${EMCC_PATH}" CACHE FILEPATH "C++ compiler (emscripten)" FORCE)
set(CMAKE_ASM_COMPILER "${EMCC_PATH}" CACHE FILEPATH "ASM compiler (emscripten)" FORCE)

message(STATUS "Emscripten SDK ready: ${EMSDK_ROOT} (${EMSCRIPTEN_VERSION})")
