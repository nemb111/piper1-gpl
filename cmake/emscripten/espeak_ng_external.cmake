# Emscripten module: native build + cross-compile as proper CMake targets.
#
# Workflow: 1. Native build via ExternalProject (espeak-ng built with emscripten
# toolchain) 2. Cross-compile via ExternalProject (rebuilds with toolchain file
# from native output)
#
# Usage: include(emscripten/espeak_ng_external) configure_espeak_ng_emscripten()

include(${CMAKE_CURRENT_LIST_DIR}/../native/espeak_ng_external.cmake)
find_package(Patch QUIET)

# Configure espeak-ng for Emscripten cross-compilation via ExternalProject. Sets
# up imported targets: espeakng, ucd, espeakng_iface_lib.
function(configure_espeak_ng_emscripten)
  if(NOT EMCC_PATH)
    message(
      WARNING
        "emcc not found. Emscripten cross-compile will not be available.\n"
        "Run build.py first to download tools, or set EMSDK_PATH.\n"
        "Note: For automated setup, run: python3 build.py")
    set(PIPER_WASM_DEPS_MISSING
        ON
        CACHE
          BOOL
          "External dependencies (emsdk, node, onnxruntime-web) are missing. Run 'python3 build.py' to set them up."
    )
    if(NOT DEFINED ESPEAKNG_SRC_PATH OR NOT ESPEAKNG_SRC_PATH)
      return()
    endif()
  endif()

  # ── Step 1: Native build via ExternalProject (espeak-ng built with native compiler) ──
  configure_espeak_ng_external()

  # ── Ensure `espeak_ng_external` target exists even if
  # configure_espeak_ng_external returned early (lib already present).  The
  # cross-compile step (espeak_ng_cross) declares `DEPENDS espeak_ng_external`
  # in ExternalProject_Add — it must exist.
  if(NOT TARGET espeak_ng_external)
    add_custom_target(espeak_ng_external COMMENT "Placeholder target for cross-compile dependency")
  endif()

  # ── Step 2: Cross-compile via ExternalProject (emscripten toolchain) ──
  # Restore emscripten for cross build — clear native compiler override
  set(piper_espeakng_cmake_args "")
  get_filename_component(emscripten_dir "${EMCC_PATH}" DIRECTORY)
  set(em_cmake_file
      "${emscripten_dir}/cmake/Modules/Platform/Emscripten.cmake")
  set(espeakng_install_dir "${CMAKE_BINARY_DIR}/espeak_ng-install")
  set(espeakng_build_dir "${CMAKE_BINARY_DIR}/espeak_ng")

  # Download & extract to external/ so the source tree lives outside build/
  get_filename_component(project_root "${CMAKE_CURRENT_LIST_DIR}/../.."
                         ABSOLUTE)
  set(espeakng_external_dir "${project_root}/external/espeak_ng")
  set(cross_prefix "${espeakng_external_dir}/cross")
  set(cross_src_dir "${cross_prefix}/src/espeak_ng_cross")
  set(cross_build_dir "${cross_src_dir}-build")
  set(native_build_src "${espeakng_build_dir}/src/espeak_ng_external-build")
  set(cross_ucd_lib "${cross_build_dir}/src/ucd-tools/libucd.a")

  # Cross-compile needs its own install dir so the EXISTS check doesn't block
  # it. We install to a host-accessible path and assemble the WASM FS dir.
  set(cross_install_dir "${CMAKE_BINARY_DIR}/espeak_ng_cross_host")
  set(cross_espeakng_lib "${cross_install_dir}/lib/libespeak-ng.a")
  # Install to host path instead of Emscripten virtual fs root
  set(espeakng_install_dir_override "${cross_install_dir}")

  configure_espeak_ng_external(
    TARGET_NAME
    espeak_ng_cross
    UPDATE_DISCONNECTED
    ON
    PREFIX
    ${cross_prefix}
    C_FLAGS
    ""
    CXX_FLAGS
    ""
    EXTRA_CMAKE_ARGS
    -DCMAKE_TOOLCHAIN_FILE=${em_cmake_file}
    -DNativeBuild_DIR=${native_build_src}/build/src
    DEPENDS
    espeak_ng_external
    SRC_DIR
    ${ESPEAKNG_SRC_PATH})

  # ── After cross-configure, set up imported targets with cross-compiled paths
  # ──
  if(NOT TARGET espeakng)
    add_library(espeakng STATIC IMPORTED)
  endif()
  set_target_properties(espeakng PROPERTIES IMPORTED_LOCATION "${cross_espeakng_lib}")

  if(NOT TARGET ucd)
    add_library(ucd STATIC IMPORTED)
  endif()
  set_target_properties(ucd PROPERTIES IMPORTED_LOCATION ${cross_ucd_lib})

  # ── Ensure espeakng_iface_lib uses cross-compiled targets ──
  if(NOT TARGET espeakng_iface_lib)
    add_library(espeakng_iface_lib INTERFACE)
    target_link_libraries(espeakng_iface_lib INTERFACE espeakng ucd)
  endif()
  set_target_properties(espeakng_iface_lib PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${espeakng_install_dir}/include")
endfunction()
