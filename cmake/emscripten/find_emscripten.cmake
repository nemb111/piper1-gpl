set(EMSCRIPTEN_VERSION "5.0.6" CACHE STRING "Emscripten version")

get_filename_component(_PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../" ABSOLUTE)
set(_EMSDK_DIR     "${_PROJECT_ROOT}/external/emsdk-${EMSCRIPTEN_VERSION}")
set(_EMSDK_ARCHIVE "${_EMSDK_DIR}/emsdk.tar.gz")
set(_EMSDK_SRC     "${_EMSDK_DIR}/emsdk")
set(_EXTRACTED_DIR "${_EMSDK_DIR}/emsdk-${EMSCRIPTEN_VERSION}")

# Compiler paths — emcc for C, em++ for C++
set(_EMCC "${_EMSDK_DIR}/emsdk/upstream/emscripten/emcc")
set(_EMXX "${_EMSDK_DIR}/emsdk/upstream/emscripten/em++")

# Resolve a system emcc on PATH and derive em++ from it
function(_set_system_emcc _found_path)
    set(EMCC_PATH "${_found_path}" CACHE FILEPATH "")
    get_filename_component(_bin_dir "${_found_path}" DIRECTORY)
    set(EMSDK_ROOT "system" CACHE PATH "")
    set(CMAKE_C_COMPILER   "${EMCC_PATH}" CACHE FILEPATH "")
    set(CMAKE_CXX_COMPILER "${_bin_dir}/em++" CACHE FILEPATH "")
    set(CMAKE_ASM_COMPILER "${EMCC_PATH}" CACHE FILEPATH "")
    message(STATUS "Emscripten ready: ${EMCC_PATH} (${EMSCRIPTEN_VERSION})")
endfunction()

# Check known local path (both emcc and em++)
if(EXISTS "${_EMCC}" AND EXISTS "${_EMXX}")
    set(EMCC_PATH "${_EMCC}" CACHE FILEPATH "")
    set(EMSDK_ROOT "${_EMSDK_DIR}" CACHE PATH "")
    set(CMAKE_C_COMPILER   "${EMCC_PATH}" CACHE FILEPATH "")
    set(CMAKE_CXX_COMPILER "${_EMXX}" CACHE FILEPATH "")
    set(CMAKE_ASM_COMPILER "${EMCC_PATH}" CACHE FILEPATH "")
    message(STATUS "Emscripten ready: ${EMCC_PATH} (${EMSCRIPTEN_VERSION})")
    return()
endif()

# Check PATH
find_program(_EMCC_PATH "emcc" NO_CACHE)
if(_EMCC_PATH)
    _set_system_emcc("${_EMCC_PATH}")
    return()
endif()

# Download archive if not present
if(NOT EXISTS "${_EMSDK_ARCHIVE}")
    message(STATUS "Downloading emsdk ${EMSCRIPTEN_VERSION}...")
    file(DOWNLOAD
        "https://github.com/emscripten-core/emsdk/archive/refs/tags/${EMSCRIPTEN_VERSION}.tar.gz"
        "${_EMSDK_ARCHIVE}"
        SHOW_PROGRESS
        STATUS _status
    )
    list(GET _status 0 _code)
    if(NOT _code EQUAL 0)
        list(GET _status 1 _msg)
        message(FATAL_ERROR "Download failed: ${_msg}")
    endif()
endif()

# Extract archive -- always overwrite
if(EXISTS "${_EMSDK_SRC}")
    file(REMOVE_RECURSE "${_EMSDK_SRC}")
endif()
file(MAKE_DIRECTORY "${_EMSDK_SRC}")
execute_process(COMMAND tar xf "${_EMSDK_ARCHIVE}" --strip-components=1 WORKING_DIRECTORY "${_EMSDK_SRC}")

# Install and activate
message(STATUS "Installing Emscripten ${EMSCRIPTEN_VERSION}...")
execute_process(
    COMMAND ${CMAKE_COMMAND} -E env PATH="${_EMSDK_SRC}:$ENV{PATH}"
        python3 "${_EMSDK_SRC}/emsdk.py" install "${EMSCRIPTEN_VERSION}"
    WORKING_DIRECTORY "${_EMSDK_DIR}"
    RESULT_VARIABLE _rc
)
if(NOT _rc EQUAL 0)
    message(FATAL_ERROR "Install failed")
endif()

execute_process(
    COMMAND ${CMAKE_COMMAND} -E env PATH="${_EMSDK_SRC}:$ENV{PATH}"
        python3 "${_EMSDK_SRC}/emsdk.py" activate "${EMSCRIPTEN_VERSION}"
    WORKING_DIRECTORY "${_EMSDK_DIR}"
)

set(EMSDK_ROOT "${_EMSDK_DIR}" CACHE PATH "")
set(EMCC_PATH  "${_EMCC}" CACHE FILEPATH "")
set(CMAKE_C_COMPILER   "${EMCC_PATH}" CACHE FILEPATH "")
set(CMAKE_CXX_COMPILER "${_EMXX}" CACHE FILEPATH "")
set(CMAKE_ASM_COMPILER "${EMCC_PATH}" CACHE FILEPATH "")
message(STATUS "Emscripten ready: ${EMCC_PATH} (${EMSCRIPTEN_VERSION})")
