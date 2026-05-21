# Find ONNX Runtime WASM static library and set up targets.
#
# Usage: include(emscripten/find_onnxruntime_web) # On first build this will
# warn with instructions to build the library. # After building, link against
# onnxruntime_web_iface_lib.
#
# Expected artifacts (produced by script/build_onnxruntime_web.py):
# external/onnxruntime/libonnxruntime_webassembly.a
# external/onnxruntime/include/         (headers)

get_filename_component(_repo_root "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(_lib_file "${_repo_root}/external/onnxruntime/libonnxruntime_webassembly.a")
set(_header_dir "${_repo_root}/external/onnxruntime/include")

# ── User-provided library path ──
if(ONNXRUNTIME_WEB_LIB_PATH)
  if(EXISTS "${ONNXRUNTIME_WEB_LIB_PATH}")
    set(_lib_file "${ONNXRUNTIME_WEB_LIB_PATH}")
    # Use default header directory (can be overridden if needed)
    if(NOT DEFINED _header_dir)
      get_filename_component(_lib_dir "${_lib_file}" DIRECTORY ABSOLUTE)
      set(_header_dir "${_lib_dir}/../include")
    endif()
    message(STATUS "ONNX Runtime Web: found user-provided library ${_lib_file}")
    add_library(onnxruntime_web_iface_lib INTERFACE)
    target_include_directories(onnxruntime_web_iface_lib
                               INTERFACE "${_header_dir}")
    target_link_libraries(onnxruntime_web_iface_lib INTERFACE "${_lib_file}")
    return()
  else()
    message(
      WARNING
        "ONNXRUNTIME_WEB_LIB_PATH is set but does not exist: ${ONNXRUNTIME_WEB_LIB_PATH}\n"
        "Run build.py first, or set ONNXRUNTIME_WEB_LIB_PATH to a valid .a file.\n"
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

# Ensure onnxruntime-web npm package is installed in wasm_piper/
if(NOT DEFINED onnxruntime_web_npm_dir)
  get_filename_component(_ort_wasm_dir
                         "${CMAKE_CURRENT_LIST_DIR}/../../wasm_piper" ABSOLUTE)
else()
  set(_ort_wasm_dir "${onnxruntime_web_npm_dir}")
endif()
if(NOT EXISTS "${_ort_wasm_dir}/node_modules/onnxruntime-web")
  if(NOT COMMAND npm)
    message(
      WARNING "onnxruntime-web npm package not found.\n"
              "Install Node.js and run:\n"
              "    cd wasm_piper && npm install\n"
              "Or pass -Donnxruntime_web_npm_dir=/path/to/wasm_piper\n"
              "Note: For automated setup, run: python3 build.py")
  else()
    message(STATUS "onnxruntime-web not found — installing in ${_ort_wasm_dir}")
    execute_process(
      COMMAND npm install
      WORKING_DIRECTORY "${_ort_wasm_dir}"
      RESULT_VARIABLE _npm_result)
    if(NOT _npm_result EQUAL 0)
      message(
        WARNING
          "npm install onnxruntime-web failed (exit code ${_npm_result})\n"
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
endif()

# If ort_shim is providing onnxruntime_iface_lib (WASM path), skip static
# library check
if(TARGET onnxruntime_iface_lib)
  return()
endif()

if(TARGET onnxruntime_web_iface_lib)
  return()
endif()

if(NOT EXISTS "${_lib_file}")
  message(
    WARNING
      "ONNX Runtime WASM static library not found: ${_lib_file}\n"
      "Build it by running:\n"
      "    python3 script/build_onnxruntime_web.py --extra-args --parallel 4\n"
      "This downloads ~2 GB and takes 30-60 minutes.\n"
      "Or use cmake -DONNXRUNTIME_WEB_EXTRA_ARGS=\"--parallel 4\" "
      "in the WASM project.\n"
      "Note: For automated setup, run: python3 build.py")
  set(PIPER_WASM_DEPS_MISSING
      ON
      CACHE
        BOOL
        "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up."
  )
  return()
endif()

add_library(onnxruntime_web_iface_lib INTERFACE)
target_include_directories(onnxruntime_web_iface_lib INTERFACE ${_header_dir})
target_link_libraries(onnxruntime_web_iface_lib INTERFACE "${_lib_file}")

message(STATUS "ONNX Runtime Web: found ${_lib_file}")
message(STATUS "  Headers: ${_header_dir}")
