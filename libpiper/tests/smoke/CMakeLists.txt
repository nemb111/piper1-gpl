# Smoke tests: fast compile-time API consistency checks
# Successful compilation proves interface compatibility

if(TARGET ${ESPEAKNG_STATIC_LIB})
    add_library(espeak_compile_test_lib STATIC
        test_espeak_compile.cpp
    )
    target_include_directories(espeak_compile_test_lib PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_BINARY_DIR}/espeak_ng-install/include
    )
    target_link_libraries(espeak_compile_test_lib PUBLIC
        ${ESPEAKNG_STATIC_LIB}
        ${UCD_STATIC_LIB}
    )
    target_compile_features(espeak_compile_test_lib PUBLIC cxx_std_17)

    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.30.0")
        namespace_alias(piper::test::espeak_compile espeak_compile_test_lib)
    else()
        add_library(piper::test::espeak_compile ALIAS espeak_compile_test_lib)
    endif()

    add_executable(espeak_compile_test test_espeak_compile.cpp)
    target_link_libraries(espeak_compile_test PRIVATE
        piper
        espeak_compile_test_lib
        mock_espeak_ng
        mock_onnxruntime
        GTest::gtest_main
    )
    add_dependencies(espeak_compile_test
        espeak_ng_external
        piper
        espeak_compile_test_lib
        mock_espeak_ng
        mock_onnxruntime
    )
endif()
