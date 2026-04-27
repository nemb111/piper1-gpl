# Detect Emscripten SDK or download it automatically.
# Usage: include(find_emscripten.cmake)
#
# Variables set on success:
#   EMSDK_ROOT        - path to the emsdk installation
#   EMCC_PATH         - path to the emcc compiler
#   EMSCRIPTEN_VERSION - Emscripten tag used (e.g. "3.1.64")
#
# Download location: <PROJECT_ROOT>/external/emsdk
# To supply your own SDK, set EMSDK_ROOT before including this file.

# ── Configuration ────────────────────────────────────────────────
set(EMSCRIPTEN_VERSION "latest" CACHE STRING "Emscripten version to download (e.g. 'latest', '3.1.64')")

# Always walk up from CMAKE_CURRENT_LIST_DIR to find the project root.
# CMAKE_CURRENT_LIST_DIR is stable regardless of context:
#   - Toolchain file: cmake/emscripten/
#   - Include from project: cmake/emscripten/
# Either way, ../../ goes from cmake/emscripten/ to repo root.
get_filename_component(_PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../" ABSOLUTE)
set(_EMSDK_DIR "${_PROJECT_ROOT}/external/emsdk")

# ── User-supplied EMSDK_ROOT override ───────────────────
if(DEFINED EMSDK_ROOT AND EXISTS "${EMSDK_ROOT}")
    get_filename_component(_real_dir "${EMSDK_ROOT}" REALPATH)
    if(EXISTS "${_real_dir}/emsdk.py")
        message(STATUS "Using user-supplied EMSDK_ROOT: ${_real_dir}")
        set(_user_emcc "${_real_dir}/emsdk/upstream/emscripten/emcc")
        if(EXISTS "${_user_emcc}")
            set(EMCC_PATH "${_user_emcc}")
        else()
            find_program(EMCC_PATH NAMES emcc PATHS "${_real_dir}/emsdk/upstream/emscripten" NO_CACHE)
        endif()
        set(EMSDK_ROOT "${_real_dir}" CACHE PATH "Emscripten SDK root" FORCE)
        if(EMCC_PATH)
            execute_process(COMMAND "${EMCC_PATH}" -v ERROR_VARIABLE _v ERROR_STRIP_TRAILING_WHITESPACE)
            if(_v MATCHES "emcc \\(Emscripten[^)]+\\)[ ]+([0-9]+\\.[0-9]+\\.[0-9]+)")
                set(EMSCRIPTEN_VERSION "${CMAKE_MATCH_1}" CACHE STRING "Version" FORCE)
            endif()
        endif()
        message(STATUS "Emscripten SDK ready: ${EMSDK_ROOT} (${EMSCRIPTEN_VERSION})")
        return()
    endif()
endif()

# ── Attempt detection ────────────────────────────────────
# 1. Check for emcc at known emsdk location (emsdk.py activate doesn't modify PATH)
if(NOT EMCC_PATH AND EXISTS "${_EMSDK_DIR}/emsdk/upstream/emscripten/emcc")
    set(EMCC_PATH "${_EMSDK_DIR}/emsdk/upstream/emscripten/emcc")
    if(NOT DEFINED EMSDK_ROOT)
        set(EMSDK_ROOT "${_EMSDK_DIR}" CACHE PATH "Emscripten SDK root" FORCE)
    endif()
endif()
# 2. Check PATH
if(NOT EMCC_PATH)
    find_program(EMCC_PATH NAMES emcc PATHS ENV PATH NO_CACHE)
endif()

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
        # Try to find SDK root (emsdk layout), fall back to emcc's directory
        get_filename_component(_EMSDK_DIR_CANDIDATE "${EMCC_PATH}" DIRECTORY)
        if(EXISTS "${_EMSDK_DIR_CANDIDATE}/upstream/emscripten")
            set(EMSDK_ROOT "${_EMSDK_DIR_CANDIDATE}" CACHE PATH "Emscripten SDK root (auto-detected)")
        else()
            set(EMSDK_ROOT "system" CACHE PATH "Emscripten SDK root (system package)" FORCE)
        endif()
        set(EMSCRIPTEN_VERSION "${CMAKE_MATCH_1}" CACHE STRING "Detected Emscripten version" FORCE)
        # Set compilers so plain cmake (not emcmake) also builds for WASM
        set(CMAKE_C_COMPILER "${EMCC_PATH}" CACHE FILEPATH "C compiler (emscripten)" FORCE)
        set(CMAKE_CXX_COMPILER "${EMCC_PATH}" CACHE FILEPATH "C++ compiler (emscripten)" FORCE)
        set(CMAKE_ASM_COMPILER "${EMCC_PATH}" CACHE FILEPATH "ASM compiler (emscripten)" FORCE)
        return()
    endif()
endif()

# Also check EMSCRIPTEN cache variable (set by a prior emcmake run)
if(EMSCRIPTEN AND NOT EMSDK_ROOT)
    find_program(EMCC_PATH NAMES emcc PATHS "${EMSCRIPTEN}" NO_CACHE)
    if(EMCC_PATH)
        get_filename_component(EMSDK_ROOT "${EMSCRIPTEN}" REALPATH)
        set(EMCC_PATH "${EMSDK_ROOT}/upstream/emscripten/emcc" CACHE FILEPATH "emcc path" FORCE)
        message(STATUS "Emscripten found via EMSCRIPTEN cache: ${EMSDK_ROOT}")
        return()
    endif()
endif()

message(STATUS "Emscripten not found on PATH — downloading SDK to ${_EMSDK_DIR}")

# ── Download emsdk via emsdk auto-archive tarball ─────────────────
set(_EMSDK_ARCHIVE "${_EMSDK_DIR}/emsdk-package.tar.gz")
set(_EMSDK_SRC_DIR "${_EMSDK_DIR}/emsdk")
set(_EMSDK_UPSTREAM "${_EMSDK_DIR}/emsdk/upstream")

# Step 1: fetch emsdk itself
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
    # The tar extracts to emsdk-master/ — rename to emsdk/
    if(EXISTS "${_EMSDK_DIR}/emsdk-master")
        # Remove leftover emsdk/ dir if it exists (from previous partial run)
        if(EXISTS "${_EMSDK_DIR}/emsdk")
            file(REMOVE_RECURSE "${_EMSDK_DIR}/emsdk")
        endif()
        file(RENAME "${_EMSDK_DIR}/emsdk-master" "${_EMSDK_SRC_DIR}")
    endif()
endif()

# Step 2: use emsdk to install the specific version
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

# ── Resolve paths after install/activate ─────────────────────────
get_filename_component(_real_dir "${_EMSDK_DIR}" REALPATH)
set(EMSDK_ROOT "${_real_dir}" CACHE PATH "Emscripten SDK root")
set(EMCC_PATH "${_real_dir}/emsdk/upstream/emscripten/emcc" CACHE FILEPATH "Path to emcc")

# emsdk.py activate modifies env vars in the subprocess, but cmake doesn't see them.
# So we explicitly set EMCC_PATH from the known emsdk location.
if(NOT EMCC_PATH OR NOT EXISTS "${EMCC_PATH}")
    set(EMCC_PATH "${_real_dir}/emsdk/upstream/emscripten/emcc")
    set(EMCC_PATH "${EMCC_PATH}" CACHE FILEPATH "Path to emcc" FORCE)
endif()

if(NOT EXISTS "${EMCC_PATH}")
    message(FATAL_ERROR "emcc not found at ${EMCC_PATH} after install")
endif()

message(STATUS "Emscripten SDK ready: ${EMSDK_ROOT} (${EMSCRIPTEN_VERSION})")
message(STATUS "  emcc : ${EMCC_PATH}")
