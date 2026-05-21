cmake_minimum_required(VERSION 3.26)

# Allow overriding the external data directory (handles multi-mount-path setups).
# When not set, falls back to ${CMAKE_CURRENT_SOURCE_DIR}/../external.
if(NOT DEFINED PIPER_WASM_DATA_DIR)
    get_filename_component(PIPER_WASM_DATA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../external" ABSOLUTE)
else()
    set(PIPER_WASM_DATA_DIR "${PIPER_WASM_DATA_DIR}" CACHE PATH "Directory for --preload-file (build-time resolved path)" FORCE)
endif()

# ── Auto-detect/download Emscripten SDK before project() ──
include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/emscripten/find_emscripten.cmake)

# ── Ort Shim (ONNX Runtime C++ API → onnxruntime-web bridge) ──
set(SHIM_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/shim/src)
include(${SHIM_SRC_DIR}/ort_shim_external.cmake)
configure_ort_shim_external()

# ── Download pinned Node.js/npm (bundles npm) ──
include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/emscripten/find_npm.cmake)
CONFIGURE_NPM_EXTERNAL()

project(wasm_piper)

# ── Centralized options (auto-included by find_emscripten.cmake — explicit for clarity) ──
include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/emscripten/options.cmake)

# ── Repo root ──
get_filename_component(_repo_root "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)

# ── Auto-install onnxruntime-web (WASM JS synthesis script dependency) ──
get_filename_component(_wasm_piper_dir "${CMAKE_CURRENT_SOURCE_DIR}" ABSOLUTE)
get_filename_component(_ort_npm_dir "${_repo_root}/external/node_modules" ABSOLUTE)
if(NOT EXISTS "${_ort_npm_dir}/onnxruntime-web")
    get_filename_component(_npm_bin_dir "${NPM_BIN}" DIRECTORY ABSOLUTE)
    file(WRITE "${CMAKE_BINARY_DIR}/.install_ort.sh"
"#!/bin/sh\nset -e\ncd \"${_wasm_piper_dir}\"\nexport PATH=\"${_npm_bin_dir}:\$PATH\"\n\"${NPM_BIN}\" install\nmkdir -p \"${_ort_npm_dir}\"\ncp -a \"node_modules/.\" \"${_ort_npm_dir}/\"\nrm -rf node_modules\nln -sfn \"${_ort_npm_dir}\" node_modules\n")
    execute_process(
        COMMAND sh "${CMAKE_BINARY_DIR}/.install_ort.sh"
        RESULT_VARIABLE _npm_result
    )
    if(NOT _npm_result EQUAL 0)
        message(WARNING "npm install onnxruntime-web failed (exit code ${_npm_result})\n"
                        "Run build.py first to install dependencies.\n"
                        "Note: For automated setup, run: python3 build.py")
        set(PIPER_WASM_DEPS_MISSING ON CACHE BOOL "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up.")
    endif()
endif()

# ── Find ONNX Runtime Web library (pre-built, optional) ──
include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/emscripten/find_onnxruntime_web.cmake)

enable_language(C)
enable_language(CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Emscripten espeak-ng build ──
include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/emscripten/espeak_ng_external.cmake)

get_filename_component(PIPER_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)

configure_espeak_ng_emscripten()

if(TARGET espeak_ng_cross)
    add_custom_target(build_espeak_wasm ALL DEPENDS espeak_ng_cross)
else()
    add_custom_target(build_espeak_wasm ALL)
endif()

# ── Copy native espeak-ng data to cross-compile install dir (missing from Emscripten install) ──
# Also clean up broken symlinks in bin/ that break file_packager
add_custom_command(TARGET build_espeak_wasm POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_BINARY_DIR}/espeak_ng-install/share/espeak-ng-data"
        "${CMAKE_BINARY_DIR}/espeak_ng_cross_host/share/espeak-ng-data"
    COMMAND ${CMAKE_COMMAND} -E rm -rf "${CMAKE_BINARY_DIR}/espeak_ng_cross_host/bin"
    COMMENT "Copying native espeak-ng data to WASM FS dir and cleaning up"
    VERBATIM)

# ── Piper WASM executable ──
# Uses real piper.cpp with ort_shim (ONNX Runtime C++ API shim → onnxruntime-web)
add_executable(piper_wasm
    ${CMAKE_CURRENT_SOURCE_DIR}/../libpiper/src/piper.cpp
)

set_target_properties(piper_wasm PROPERTIES
    LINK_FLAGS 
        "-s ALLOW_MEMORY_GROWTH=1 -s MODULARIZE=1 -s EXPORT_NAME='piperWasm' \
         -s EXPORTED_FUNCTIONS='[_malloc,_free,_piper_create,_piper_default_synthesize_options,_piper_synthesize_start,_piper_synthesize_next,_piper_free]' \
         -s EXPORTED_RUNTIME_METHODS='[ccall,cwrap,UTF8ToString,stringToUTF8,getValue,setValue,HEAPU8,FS]' \
         -s ASYNCIFY=1 -s WASM_BIGINT=1 -s FILESYSTEM=1 \
         -s DISABLE_EXCEPTION_CATCHING=0 \
         -s ALLOW_TABLE_GROWTH=1 -s DISABLE_DEPRECATED_FIND_EVENT_TARGET_BEHAVIOR=1 --no-entry \
         -s EXIT_RUNTIME=0 \
         --preload-file ${CMAKE_CURRENT_BINARY_DIR}/espeak_ng_cross_host@/ --preload-file ${CMAKE_CURRENT_BINARY_DIR}/espeak_ng-install/share/espeak-ng-data@/ --preload-file ${PIPER_WASM_DATA_DIR}/piper_voices@/"
    OUTPUT_NAME "piper_wasm"
    SUFFIX ".js"
)

target_link_libraries(piper_wasm
    PUBLIC
        espeakng_iface_lib
)
target_include_directories(piper_wasm PRIVATE
    ${SHIM_SRC_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${_repo_root}/libpiper/include
)

# ── Merge ort_shim.js into piper_wasm.js ──
# 1. Strip ort_shim.js's module.exports (it would overwrite piperWasm).
# 2. Prepend cleaned ort_shim.js to piper_wasm.js so ortShimModule is
#    available as a global, but piperWasm remains the module.exports.
add_custom_command(TARGET piper_wasm POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E echo "Merging ort_shim.js into piper_wasm.js..."
    COMMAND sh -c "sed '/^if (typeof module/,$d' '${SHIM_SRC_DIR}/ort_shim.js' > '${CMAKE_CURRENT_BINARY_DIR}/ort_shim_stripped.js' && cat '${CMAKE_CURRENT_BINARY_DIR}/ort_shim_stripped.js' '${CMAKE_CURRENT_BINARY_DIR}/piper_wasm.js' > '${CMAKE_CURRENT_BINARY_DIR}/piper_wasm.js.merged' && mv '${CMAKE_CURRENT_BINARY_DIR}/piper_wasm.js.merged' '${CMAKE_CURRENT_BINARY_DIR}/piper_wasm.js'"
    COMMENT "Merging ort_shim.js into piper_wasm.js"
    VERBATIM
)

# ── Report missing dependencies ──
if(PIPER_WASM_DEPS_MISSING)
    message(WARNING "
One or more external dependencies are missing or could not be located:
  - Emscripten SDK (emsdk)
  - Node.js / npm
  - ONNX Runtime Web static library
  - espeak-ng source (if EMSDK_PATH not set)

Without these dependencies the build will fail or produce incomplete output.

To set up all dependencies automatically, run:
    python3 build.py

Alternatively, set these CMake options to provide your own paths:
    cmake -DEMSDK_PATH=/path/to/emsdk
          -DNPM_DIR=/path/to/node/bin
          -DONNXRUNTIME_WEB_LIB_PATH=/path/to/libonnxruntime_webassembly.a
          -DESPEAKNG_SRC_PATH=/path/to/espeak-ng-source

Configure will continue, but the build may fail for missing components.")
endif()
