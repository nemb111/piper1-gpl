# Mock-based integration tests (GTest suites + example)
# Tests the mocked boundaries of libpiper against espeak-ng and ONNX Runtime

find_package(GTest QUIET)

if(TARGET GTest::gtest_main)
    add_executable(test_simple test_simple.cpp)
    target_link_libraries(test_simple PRIVATE
        piper
        mock_espeak_ng
        mock_onnxruntime
        GTest::gtest_main
    )
    add_dependencies(test_simple piper mock_espeak_ng mock_onnxruntime)
endif()
