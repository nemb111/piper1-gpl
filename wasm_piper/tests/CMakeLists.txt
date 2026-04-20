# Native test for WASM integration comparison
cmake_minimum_required(VERSION 3.26)
project(wasm_piper_native_test LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Use the native espeak-ng that was built by the parent piper CMake
get_filename_component(_repo_root "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(_NATIVE_BUILD "${_repo_root}/build")
set(_NATIVE_ESPEAK "${_NATIVE_BUILD}/espeak_ng-install")

# ── Mock ONNX test (baseline) ──────────────────
add_executable(native_piper_test
    "${_repo_root}/libpiper/src/piper.cpp"
    "${_repo_root}/libpiper/tests/mock_onnxruntime.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/wasm_integration_main.cpp"
)

target_compile_definitions(native_piper_test PUBLIC MOCK_BUILD=1)
target_include_directories(native_piper_test PUBLIC
    "${_repo_root}/libpiper/include"
    "${_repo_root}/libpiper/tests"
    "${_NATIVE_ESPEAK}/include"
)

target_link_libraries(native_piper_test PRIVATE
    "${_NATIVE_ESPEAK}/lib/libespeak-ng.a"
    "${_NATIVE_BUILD}/espeak_ng/src/espeak_ng_external-build/src/ucd-tools/libucd.a"
)

# ── Real ONNX test (actual inference comparison) ────
# Links real ONNX Runtime for real audio output
# Build with: cmake -B build_real -S wasm_piper/tests -DCMAKE_PREFIX_PATH=<onnxruntime_dir>
option(WASM_PIPER_REAL_ONNX "Build with real ONNX Runtime" OFF)

if(WASM_PIPER_REAL_ONNX)
    if(NOT DEFINED ENV{ONNXRUNTIME_DIR})
        message(FATAL_ERROR "Set ONNXRUNTIME_DIR env var or CMAKE_PREFIX_PATH for real ONNX build")
    endif()

    set(_OR_DIR "$ENV{ONNXRUNTIME_DIR}")

    add_executable(native_piper_real_test
        "${_repo_root}/libpiper/src/piper.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/wasm_integration_main.cpp"
    )

    # NO MOCK_BUILD - uses real ONNX Runtime
    target_include_directories(native_piper_real_test PUBLIC
        "${_repo_root}/libpiper/include"
        "${_repo_root}/libpiper/tests"
        "${_NATIVE_ESPEAK}/include"
        "${_OR_DIR}/include"
    )

    target_link_libraries(native_piper_real_test PRIVATE
        "${_NATIVE_ESPEAK}/lib/libespeak-ng.a"
        "${_NATIVE_BUILD}/espeak_ng/src/espeak_ng_external-build/src/ucd-tools/libucd.a"
        "${_OR_DIR}/lib/libonnxruntime.so"
    )
endif()
