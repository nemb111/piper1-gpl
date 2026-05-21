# Shared CMake module: configure espeak-ng ExternalProject for native builds.
#
# Usage: # Before calling, set PIPER_ESPEAKNG_* variables (see CMakeLists.txt
# examples) include(native/espeak_ng_external) configure_espeak_ng_external()
#
# Mandatory variable (set by caller): PIPER_ESPEAKNG_UPDATE_DISCONNECTED  -- ON
# to skip re-download Optional variable (set by caller for cross-compilation):
# piper_espeakng_cmake_args           -- extra CMAKE_ARGS for ExternalProject

include(ExternalProject)
include(${CMAKE_CURRENT_LIST_DIR}/options.cmake)

# Get common CMAKE_ARGS shared between native and cross-compilation builds
function(get_espeak_ng_common_cmake_args install_dir out_var)
  set(${out_var}
      -DCMAKE_INSTALL_PREFIX=${install_dir}
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
      PARENT_SCOPE)
endfunction()

# Create imported targets for espeak-ng libraries
function(create_espeak_ng_targets target_name build_src install_dir static_lib
         ucd_lib)
  if(NOT TARGET espeakng)
    add_library(espeakng STATIC IMPORTED)
  endif()
  add_dependencies(espeakng ${target_name})
  set_target_properties(espeakng PROPERTIES IMPORTED_LOCATION ${static_lib})

  if(NOT TARGET ucd)
    add_library(ucd STATIC IMPORTED)
  endif()
  add_dependencies(ucd ${target_name})
  set_target_properties(ucd PROPERTIES IMPORTED_LOCATION ${ucd_lib})

  if(NOT TARGET espeakng_iface_lib)
    add_library(espeakng_iface_lib INTERFACE)
    target_link_libraries(espeakng_iface_lib INTERFACE espeakng ucd)
    target_include_directories(espeakng_iface_lib
                               INTERFACE ${install_dir}/include)
  endif()
  add_dependencies(espeakng_iface_lib ${target_name})
endfunction()

# Configure espeak-ng ExternalProject for native builds. @brief Downloads,
# builds, and installs espeak-ng. Caller sets PIPER_ESPEAKNG_UPDATE_DISCONNECTED
# before calling.
function(configure_espeak_ng_external)
  set(options "")
  set(oneValueArgs
      TARGET_NAME
      UPDATE_DISCONNECTED
      EXTRA_CMAKE_ARGS_PREFIX
      PREFIX
      C_FLAGS
      CXX_FLAGS
      SRC_DIR)
  set(multiValueArgs EXTRA_CMAKE_ARGS DEPENDS)

  cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}"
                        ${ARGN})

  _resolve_espeak_ng_defaults()

  if(NOT ARG_UPDATE_DISCONNECTED)
    message(
      FATAL_ERROR "Missing mandatory toolchain variable: UPDATE_DISCONNECTED. "
                  "Set it before calling configure_espeak_ng_external().")
  endif()

  set(espeakng_build_dir "${ARG_PREFIX}")
  if(NOT DEFINED espeakng_install_dir_override)
    set(espeakng_install_dir "${CMAKE_BINARY_DIR}/espeak_ng-install")
  else()
    set(espeakng_install_dir "${espeakng_install_dir_override}")
  endif()
  set(espeakng_build_src "${espeakng_build_dir}/src/${ARG_TARGET_NAME}-build")

  # Platform-specific library paths
  if(WIN32)
    set(espeakng_static_lib ${espeakng_install_dir}/lib/espeak-ng.lib)
    set(ucd_static_lib ${espeakng_build_src}/src/ucd-tools/libucd.lib)
  else()
    set(espeakng_static_lib ${espeakng_install_dir}/lib/libespeak-ng.a)
    set(ucd_static_lib ${espeakng_build_src}/src/ucd-tools/libucd.a)
  endif()

  # Early exit if library already built
  if(EXISTS "${espeakng_static_lib}")
    return()
  endif()

  # Build CMAKE_ARGS
  get_espeak_ng_common_cmake_args(${espeakng_install_dir} common_cmake_args)
  set(build_cmake_args ${common_cmake_args})
  if(ARG_C_FLAGS)
    list(APPEND build_cmake_args "-DCMAKE_C_FLAGS=${ARG_C_FLAGS}")
  endif()
  if(ARG_CXX_FLAGS)
    list(APPEND build_cmake_args "-DCMAKE_CXX_FLAGS=${ARG_CXX_FLAGS}")
  endif()
  if(ARG_EXTRA_CMAKE_ARGS_PREFIX)
    list(APPEND build_cmake_args ${ARG_EXTRA_CMAKE_ARGS_PREFIX})
  endif()
  if(DEFINED ARG_EXTRA_CMAKE_ARGS)
    string(REPLACE ";" "\;" _escaped "${ARG_EXTRA_CMAKE_ARGS}")
    # ARG_EXTRA_CMAKE_ARGS is a semicolon-separated string from cmake_parse_arguments
    # Split it back into a list for build_cmake_args
    set(extra_list ${ARG_EXTRA_CMAKE_ARGS})
    list(APPEND build_cmake_args ${extra_list})
  endif()

  # Add ExternalProject based on source configuration
  if(ARG_SRC_DIR AND EXISTS "${ARG_SRC_DIR}")
    ExternalProject_Add(
      ${ARG_TARGET_NAME}
      SOURCE_DIR ${ARG_SRC_DIR}
      PREFIX ${espeakng_build_dir}
      CMAKE_ARGS ${build_cmake_args}
      BUILD_BYPRODUCTS ${espeakng_static_lib} ${ucd_static_lib}
      UPDATE_DISCONNECTED ${ARG_UPDATE_DISCONNECTED}
      DEPENDS ${ARG_DEPENDS_LIST})
  else()
    ExternalProject_Add(
      ${ARG_TARGET_NAME}
      GIT_REPOSITORY "https://github.com/espeak-ng/espeak-ng.git"
      GIT_TAG "83cb7ecf6f5f3e66014102b3d4a5823e60182055"
      PREFIX ${espeakng_build_dir}
      CMAKE_ARGS ${build_cmake_args}
      BUILD_BYPRODUCTS ${espeakng_static_lib} ${ucd_static_lib}
      UPDATE_DISCONNECTED ${ARG_UPDATE_DISCONNECTED}
      DEPENDS ${ARG_DEPENDS_LIST})
  endif()

  create_espeak_ng_targets(
    ${ARG_TARGET_NAME} ${espeakng_build_src} ${espeakng_install_dir}
    ${espeakng_static_lib} ${ucd_static_lib})
endfunction()

# Resolve default values for espeak-ng configuration
function(_resolve_espeak_ng_defaults)
  if(NOT DEFINED ARG_TARGET_NAME)
    set(ARG_TARGET_NAME "espeak_ng_external" PARENT_SCOPE)
  endif()
  if(NOT DEFINED ARG_UPDATE_DISCONNECTED)
    set(ARG_UPDATE_DISCONNECTED "${PIPER_ESPEAKNG_UPDATE_DISCONNECTED}" PARENT_SCOPE)
  endif()
  # Caller may pass EXTRA_CMAKE_ARGS (multiValue) or EXTRA_CMAKE_ARGS_PREFIX (oneValue)
  if(NOT DEFINED ARG_EXTRA_CMAKE_ARGS_PREFIX)
    if(DEFINED piper_espeakng_cmake_args)
      set(ARG_EXTRA_CMAKE_ARGS_PREFIX "${piper_espeakng_cmake_args}" PARENT_SCOPE)
    endif()
  endif()
  if(NOT DEFINED ARG_PREFIX)
    set(ARG_PREFIX "${CMAKE_BINARY_DIR}/espeak_ng" PARENT_SCOPE)
  endif()
  if(NOT DEFINED ARG_SRC_DIR)
    set(ARG_SRC_DIR "" PARENT_SCOPE)
  endif()
endfunction()
