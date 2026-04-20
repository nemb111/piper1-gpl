/**
 * Compile test for espeak-ng API using ONNX Runtime mocks
 *
 * This file verifies that espeak-ng API functions compile correctly with
 * ONNX Runtime mocks. It is a compile-time test - no assertions or test runner
 * is required. Successful compilation proves API interface compatibility.
 */

#include <espeak-ng/espeak_ng.h>
#include "mock_onnxruntime.h"

int main() {
    // Test espeak-ng API calls
    espeak_ng_ERROR_CONTEXT context;
    espeak_ng_STATUS status;
    int result;

    // Test espeak_ng_Initialize()
    result = espeak_ng_Initialize(&context);

    // Test espeak_ng_SetVoiceByName()
    status = espeak_ng_SetVoiceByName("test");

    // Test espeak_ng_SetVoiceByFile()
    status = espeak_ng_SetVoiceByFile("test.voice");

    // Test espeak_ng_SetParameter()
    result = espeak_ng_SetParameter(espeakRATE, 150, 0);

    // Test espeak_ng_GetSampleRate()
    result = espeak_ng_GetSampleRate();

    // Test espeak_ng_Cancel()
    result = espeak_ng_Cancel();

    // Test espeak_ng_Terminate()
    result = espeak_ng_Terminate();

    return 0;
}