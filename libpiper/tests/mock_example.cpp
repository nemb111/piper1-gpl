/**
 * Example: Using mocks for testing libpiper
 *
 * This file demonstrates how to use the mock APIs to test libpiper
 * without requiring actual espeak-ng or ONNX Runtime installations.
 */

#include "piper.h"
#include "mock_espeak_ng.h"
#include "mock_onnxruntime.h"
#include <iostream>
#include <cassert>

// Mock callback for custom phoneme output
static void custom_phoneme_callback(const char* text, const char** phonemes, int* terminator) {
    // This would be called by espeak_TextToPhonemesWithTerminator
    // For testing, you can customize the phoneme output
    *phonemes = "kɪˈlɑm";
    *terminator = CLAUSE_PERIOD;
}

int main() {
    std::cout << "=== Mock Testing Example ===\n\n";

    // Reset mock state
    mock_espeak_reset();
    MockOrt::reset_mock_state();

    // Test 1: Basic initialization
    std::cout << "Test 1: Basic initialization\n";
    piper_synthesizer* synth = piper_create(
        "/path/to/model.onnx",
        "/path/to/config.json",
        "/path/to/espeak_data"
    );

    assert(synth != nullptr);
    assert(mock_espeak_get_initialize_call_count() == 1);
    assert(std::string(mock_espeak_get_initialize_data_path()) == "/path/to/espeak_data");
    std::cout << "  ✓ piper_create called espeak_Initialize\n";
    std::cout << "  ✓ Data path correctly passed\n\n";

    // Test 2: Synthesis with custom phoneme result
    std::cout << "Test 2: Custom phoneme result\n";
    mock_espeak_set_phoneme_result("tɛsˈtɪŋ");
    int result = piper_synthesize_start(synth, "Testing", nullptr);
    assert(result == PIPER_OK);
    assert(mock_espeak_get_text_to_phonemes_call_count() == 1);
    assert(std::string(mock_espeak_get_text_to_phonemes_result()) == "tɛsˈtɪŋ");
    std::cout << "  ✓ Custom phoneme result captured\n";
    std::cout << "  ✓ Text to phonemes conversion successful\n\n";

    // Test 3: Error simulation
    std::cout << "Test 3: Error simulation\n";
    mock_espeak_set_error_simulation(false, true, false);
    result = piper_synthesize_start(synth, "Test voice", nullptr);
    assert(result == PIPER_ERR_GENERIC);
    assert(mock_espeak_get_set_voice_result() == EE_ERROR);
    std::cout << "  ✓ Voice set error detected\n\n";

    // Test 4: ONNX Runtime tensor creation tracking
    std::cout << "Test 4: ONNX Runtime tensor creation\n";
    result = piper_synthesize_next(synth, nullptr);
    assert(result == PIPER_OK);
    assert(MockOrt::get_tensor_create_call_count() == 4); // 4 input tensors created
    std::cout << "  ✓ 4 input tensors created\n";

    // Check first tensor (phoneme_ids)
    const auto& tensors = MockOrt::Value::GetLastCreatedTensors();
    assert(tensors.size() >= 1);
    assert(tensors[0].tensor_type_ == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64);
    std::cout << "  ✓ phoneme_ids tensor created with correct type\n";

    // Check scales tensor
    assert(tensors[2].tensor_type_ == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    std::cout << "  ✓ scales tensor created with correct type\n";

    // Test 5: Session configuration tracking
    std::cout << "\nTest 5: Session configuration\n";
    MockOrt::SessionOptions opts;
    opts.DisableCpuMemArena();
    opts.DisableMemPattern();
    opts.DisableProfiling();
    assert(opts.cpu_mem_arena_disabled == true);
    assert(opts.mem_pattern_disabled == true);
    assert(opts.profiling_disabled == true);
    std::cout << "  ✓ All session options disabled\n";

    // Test 6: Mock output configuration
    std::cout << "\nTest 6: Mock output configuration\n";
    MockOrt::mock_session_set_single_output(100, nullptr, 0); // 100 samples

    result = piper_synthesize_next(synth, nullptr);
    assert(result == PIPER_OK);
    assert(MockOrt::get_run_call_count() == 1);
    assert(MockOrt::Session::last_session_->run_called == true);
    std::cout << "  ✓ Session Run called\n";
    std::cout << "  ✓ Mock output configured correctly\n";

    // Test 7: Cleanup
    std::cout << "\nTest 7: Cleanup\n";
    piper_free(synth);
    std::cout << "  ✓ piper_free called\n";
    std::cout << "  ✓ All resources cleaned up\n";

    // Test 8: Complex scenario - multiple syntheses
    std::cout << "\nTest 8: Multiple syntheses\n";
    synth = piper_create("/path/to/model.onnx", nullptr, nullptr);
    assert(synth != nullptr);

    const char* test_texts[] = {"Hello", "World", "Test"};
    for (int i = 0; i < 3; i++) {
        result = piper_synthesize_start(synth, test_texts[i], nullptr);
        assert(result == PIPER_OK);
        result = piper_synthesize_next(synth, nullptr);
        assert(result == PIPER_OK);
    }

    assert(mock_espeak_get_text_to_phonemes_call_count() == 3);
    assert(MockOrt::get_run_call_count() == 3);
    std::cout << "  ✓ Multiple syntheses completed\n";
    std::cout << "  ✓ All espeak calls tracked\n";
    std::cout << "  ✓ All ONNX Runtime calls tracked\n";

    piper_free(synth);

    std::cout << "\n=== All tests passed! ===\n";

    return 0;
}