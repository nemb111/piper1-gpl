include(${CMAKE_CURRENT_LIST_DIR}/options.cmake)

get_filename_component(_PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../"
                       ABSOLUTE)

# ── User-provided EMSDK_PATH ──
if(EMSDK_PATH)
  if(EXISTS "${EMSDK_PATH}/emsdk.py")
    set(EMCC_PATH
        "${EMSDK_PATH}/upstream/emscripten/emcc"
        CACHE FILEPATH "")
    set(EMXX_PATH
        "${EMSDK_PATH}/upstream/emscripten/em++"
        CACHE FILEPATH "")
    set(EMSDK_ROOT
        "${EMSDK_PATH}"
        CACHE PATH "")
    set(CMAKE_C_COMPILER
        "${EMCC_PATH}"
        CACHE FILEPATH "")
    set(CMAKE_CXX_COMPILER
        "${EMXX_PATH}"
        CACHE FILEPATH "")
    set(CMAKE_ASM_COMPILER
        "${EMCC_PATH}"
        CACHE FILEPATH "")
    message(
      STATUS
        "Emscripten ready (user-provided): ${EMCC_PATH} (${EMSCRIPTEN_VERSION})"
    )
    return()
  else()
    message(
      WARNING
        "EMSDK_PATH is set but does not contain emsdk.py: ${EMSDK_PATH}\n"
        "Run build.py first to download tools, or set EMSDK_PATH to a valid emsdk directory.\n"
        "Note: For automated setup, run: python3 build.py")
    set(PIPER_WASM_DEPS_MISSING
        ON
        CACHE
          BOOL
          "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up."
    )
    return()
  endif()
endif()

set(EMSDK_DIR "${_PROJECT_ROOT}/external/emsdk-${EMSCRIPTEN_VERSION}")
set(EMSDK_ARCHIVE "${EMSDK_DIR}/emsdk.tar.gz")
set(EMSDK_SRC "${EMSDK_DIR}/emsdk")

# Compiler paths — emcc for C, em++ for C++
set(EMCC_BIN "${EMSDK_DIR}/emsdk/upstream/emscripten/emcc")
set(EMXX_BIN "${EMSDK_DIR}/emsdk/upstream/emscripten/em++")

# Resolve a system emcc on PATH and derive em++ from it
function(_set_system_emcc found_emcc_path)
  set(EMCC_PATH
      "${found_emcc_path}"
      CACHE FILEPATH "")
  get_filename_component(bin_dir "${found_emcc_path}" DIRECTORY)
  set(EMSDK_ROOT
      "system"
      CACHE PATH "")
  set(CMAKE_C_COMPILER
      "${EMCC_PATH}"
      CACHE FILEPATH "")
  set(CMAKE_CXX_COMPILER
      "${bin_dir}/em++"
      CACHE FILEPATH "")
  set(CMAKE_ASM_COMPILER
      "${EMCC_PATH}"
      CACHE FILEPATH "")
  message(STATUS "Emscripten ready: ${EMCC_PATH} (${EMSCRIPTEN_VERSION})")
endfunction()

# Check known local path (both emcc and em++)
if(EXISTS "${EMCC_BIN}" AND EXISTS "${EMXX_BIN}")
  set(EMCC_PATH
      "${EMCC_BIN}"
      CACHE FILEPATH "")
  set(EMSDK_ROOT
      "${EMSDK_DIR}"
      CACHE PATH "")
  set(CMAKE_C_COMPILER
      "${EMCC_PATH}"
      CACHE FILEPATH "")
  set(CMAKE_CXX_COMPILER
      "${EMXX_BIN}"
      CACHE FILEPATH "")
  set(CMAKE_ASM_COMPILER
      "${EMCC_PATH}"
      CACHE FILEPATH "")
  message(STATUS "Emscripten ready: ${EMCC_PATH} (${EMSCRIPTEN_VERSION})")
  return()
endif()

# Check PATH
find_program(EMCC_PATH_FIND "emcc" NO_CACHE)
if(EMCC_PATH_FIND)
  _set_system_emcc("${EMCC_PATH_FIND}")
  return()
endif()

# Download archive if not present
if(NOT EXISTS "${EMSDK_ARCHIVE}")
  message(STATUS "Downloading emsdk ${EMSCRIPTEN_VERSION}...")
  file(
    DOWNLOAD
    "https://github.com/emscripten-core/emsdk/archive/refs/tags/${EMSCRIPTEN_VERSION}.tar.gz"
    "${EMSDK_ARCHIVE}"
    SHOW_PROGRESS
    STATUS status)
  list(GET status 0 EM_DOWNLOAD_CODE)
  if(NOT EM_DOWNLOAD_CODE EQUAL 0)
    list(GET status 1 _msg)
    message(WARNING "Failed to download emsdk ${EMSCRIPTEN_VERSION}: ${_msg}\n"
                    "Run build.py first to download tools, or set EMSDK_PATH.\n"
                    "Note: For automated setup, run: python3 build.py")
    set(PIPER_WASM_DEPS_MISSING
        ON
        CACHE
          BOOL
          "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up."
    )
    return()
  endif()
endif()

# Extract archive -- always overwrite
if(EXISTS "${EMSDK_SRC}")
  file(REMOVE_RECURSE "${EMSDK_SRC}")
endif()
file(MAKE_DIRECTORY "${EMSDK_SRC}")
execute_process(COMMAND tar xf "${EMSDK_ARCHIVE}" --strip-components=1
                WORKING_DIRECTORY "${EMSDK_SRC}")

# Install and activate
message(STATUS "Installing Emscripten ${EMSCRIPTEN_VERSION}...")
execute_process(
  COMMAND ${CMAKE_COMMAND} -E env PATH="${EMSDK_SRC}:$ENV{PATH}" python3
          "${EMSDK_SRC}/emsdk.py" install "${EMSCRIPTEN_VERSION}"
  WORKING_DIRECTORY "${EMSDK_DIR}"
  RESULT_VARIABLE _rc)
if(NOT _rc EQUAL 0)
  message(WARNING "Failed to install Emscripten ${EMSCRIPTEN_VERSION}\n"
                  "Run build.py first to download tools, or set EMSDK_PATH.\n"
                  "Note: For automated setup, run: python3 build.py")
  set(PIPER_WASM_DEPS_MISSING
      ON
      CACHE
        BOOL
        "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up."
  )
  return()
endif()

execute_process(
  COMMAND ${CMAKE_COMMAND} -E env PATH="${EMSDK_SRC}:$ENV{PATH}" python3
          "${EMSDK_SRC}/emsdk.py" activate "${EMSCRIPTEN_VERSION}"
  WORKING_DIRECTORY "${EMSDK_DIR}")

# Verify emcc was actually created after activation
if(NOT EXISTS "${EMCC_BIN}")
  message(WARNING "Emscripten activation did not produce emcc at ${EMCC_BIN}\n"
                  "Run build.py first to download tools, or set EMSDK_PATH.\n"
                  "Note: For automated setup, run: python3 build.py")
  set(PIPER_WASM_DEPS_MISSING
      ON
      CACHE
        BOOL
        "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up."
  )
  return()
endif()

set(EMSDK_ROOT
    "${EMSDK_DIR}"
    CACHE PATH "")
set(EMCC_PATH
    "${EMCC_BIN}"
    CACHE FILEPATH "")
set(CMAKE_C_COMPILER
    "${EMCC_PATH}"
    CACHE FILEPATH "")
set(CMAKE_CXX_COMPILER
    "${EMXX_BIN}"
    CACHE FILEPATH "")
set(CMAKE_ASM_COMPILER
    "${EMCC_PATH}"
    CACHE FILEPATH "")
message(STATUS "Emscripten ready: ${EMCC_PATH} (${EMSCRIPTEN_VERSION})")
