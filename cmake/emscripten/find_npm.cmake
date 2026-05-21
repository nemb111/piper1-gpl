# ── Node/npm downloader for WASM builds ── Downloads a pinned node binary
# (which bundles npm) to external/ Ensures reproducible builds regardless of
# system npm version.
#
# Usage: include(find_npm.cmake) # Optional: set NODE_VERSION "22.16.0" before
# calling configure_npm_external() # Result: NPM_BIN and NPM_DIR are set

if(TARGET npm_iface_lib)
  return()
endif()

# ── Default version (LTS) ──
if(NOT DEFINED NODE_VERSION)
  set(NODE_VERSION
      "22.16.0"
      CACHE STRING "Node.js / npm version to download")
endif()

# ── Directory layout ──
get_filename_component(_npx_root "${CMAKE_CURRENT_LIST_DIR}/../../external"
                       ABSOLUTE)
set(NODE_DOWNLOAD_DIR
    "${_npx_root}/node-v${NODE_VERSION}"
    CACHE PATH "Node.js download directory")

# ── Platform detection ── CMAKE_HOST_SYSTEM_PROCESSOR not set before project()
# — use uname -m instead
execute_process(
  COMMAND uname -m
  RESULT_VARIABLE _uname_result
  OUTPUT_VARIABLE _uname_output
  OUTPUT_STRIP_TRAILING_WHITESPACE)
if(_uname_result EQUAL 0)
  set(_host_arch "${_uname_output}")
else()
  set(_host_arch "x86_64")
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux" AND _host_arch STREQUAL "x86_64")
  set(_node_platform "linux-x64")
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux" AND _host_arch MATCHES
                                                   "aarch64|armv7l")
  set(_node_platform "linux-arm64")
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin" AND _host_arch MATCHES
                                                    "x86_64|arm64")
  set(_node_platform "darwin-${_host_arch}")
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
  set(_node_platform "win-x64")
else()
  message(
    WARNING "Unsupported platform ${CMAKE_HOST_SYSTEM_NAME} ${_host_arch} "
            "for node download - falling back to system node/npm.\n"
            "If system node/npm is also unavailable, run build.py first.\n"
            "Note: For automated setup, run: python3 build.py")
  set(_node_platform "")
endif()

set(_node_tarball "node-v${NODE_VERSION}-${_node_platform}.tar.xz")
set(_node_url "https://nodejs.org/dist/v${NODE_VERSION}/${_node_tarball}")

# ── Hashes (update when changing NODE_VERSION) ──
set(_node_hashes
    "SHA256=f4cb75bb036f0d0eddf6b79d9596df1aaab9ddccd6a20bf489be5abe9467e84e")

# ── Internal function: download and extract node ──
function(_node_download_and_extract node_dir tarball_path url hashes)
  file(REMOVE_RECURSE "${node_dir}")
  file(MAKE_DIRECTORY "${node_dir}")

  if(NOT EXISTS "${tarball_path}")
    message(STATUS "Downloading Node.js ${NODE_VERSION} from ${url}")
    file(
      DOWNLOAD "${url}" "${tarball_path}.tmp"
      SHOW_PROGRESS
      EXPECTED_HASH ${hashes}
      STATUS download_status)
    list(GET download_status 0 status_code)
    if(NOT status_code EQUAL 0)
      list(GET download_status 1 error_msg)
      file(REMOVE "${tarball_path}.tmp")
      message(WARNING "Failed to download Node.js: ${error_msg}\n"
                      "Run build.py first to download tools, or set NPM_DIR.\n"
                      "Note: For automated setup, run: python3 build.py")
      set(PIPER_WASM_DEPS_MISSING
          ON
          CACHE
            BOOL
            "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up."
      )
      return()
    endif()
    file(RENAME "${tarball_path}.tmp" "${tarball_path}")
  else()
    message(STATUS "Node.js ${NODE_VERSION} cache found at ${tarball_path}")
  endif()

  message(STATUS "Extracting Node.js to ${node_dir}")
  execute_process(
    COMMAND tar xf "${tarball_path}" --strip-components=1
    WORKING_DIRECTORY "${node_dir}"
    RESULT_VARIABLE extract_result)
  if(NOT extract_result EQUAL 0)
    message(WARNING "Failed to extract Node.js tarball\n"
                    "Run build.py first to download tools, or set NPM_DIR.\n"
                    "Note: For automated setup, run: python3 build.py")
    set(PIPER_WASM_DEPS_MISSING
        ON
        CACHE
          BOOL
          "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up."
    )
    return()
  endif()
endfunction()

# ── Main function: ensure node/npm is available ──
function(configure_npm_external)
  # ── User-provided NPM_DIR ──
  if(NPM_DIR)
    if(EXISTS "${NPM_DIR}/npm")
      set(NPM_BIN
          "${NPM_DIR}/npm"
          CACHE FILEPATH "Path to npm binary" FORCE)
      set(NODE_BIN
          "${NPM_DIR}/node"
          CACHE FILEPATH "Path to node binary" FORCE)
      message(
        STATUS "Node.js/npm ready (user-provided): ${NODE_BIN} / ${NPM_BIN}")
      return()
    else()
      message(
        WARNING
          "NPM_DIR is set but does not contain npm: ${NPM_DIR}\n"
          "Run build.py first to download tools, or set NPM_DIR to a valid node/bin directory.\n"
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

  set(BIN_DIR
      "${NODE_DOWNLOAD_DIR}/bin"
      CACHE PATH "Node.js binary directory")
  set(NPM_BIN
      "${BIN_DIR}/npm"
      CACHE FILEPATH "Path to npm binary" FORCE)
  set(NODE_BIN
      "${BIN_DIR}/node"
      CACHE FILEPATH "Path to node binary" FORCE)

  if(EXISTS "${NODE_BIN}")
    message(STATUS "Using Node.js/npm from ${NODE_DOWNLOAD_DIR}")
    return()
  endif()

  if(NOT _node_platform)
    message(WARNING "Cannot download Node.js — falling back to system node/npm")
    find_program(NPM_BIN npm)
    find_program(NODE_BIN node)
    if(NOT NPM_BIN OR NOT NODE_BIN)
      message(
        WARNING
          "Node/npm not found on system PATH and could not be downloaded.\n"
          "Run build.py first to download tools.\n"
          "Note: For automated setup, run: python3 build.py")
      set(PIPER_WASM_DEPS_MISSING
          ON
          CACHE
            BOOL
            "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up."
      )
      return()
    endif()
    message(STATUS "Using system Node.js/npm: ${NODE_BIN} / ${NPM_BIN}")
    return()
  endif()

  get_filename_component(_cache_dir "${CMAKE_BINARY_DIR}/external/node"
                         ABSOLUTE)
  set(tarball_path "${_cache_dir}/${_node_tarball}")

  _node_download_and_extract("${NODE_DOWNLOAD_DIR}" "${tarball_path}"
                             "${_node_url}" "${_node_hashes}")

  if(NOT EXISTS "${NODE_BIN}")
    message(
      WARNING "Node.js binary not found at ${NODE_BIN} after extraction.\n"
              "Run build.py first to download tools, or set NPM_DIR.\n"
              "Note: For automated setup, run: python3 build.py")
    set(PIPER_WASM_DEPS_MISSING
        ON
        CACHE
          BOOL
          "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up."
    )
    return()
  endif()

  message(STATUS "Node.js ${NODE_VERSION} installed to ${NODE_DOWNLOAD_DIR}")
  message(STATUS "  node: ${NODE_BIN}")
  message(STATUS "  npm:  ${NPM_BIN}")
endfunction()
