/**
 * Mock espeak-ng implementation
 */

#include "mock_espeak_ng.h"
#include <cstring>
#include <cstdlib>

/* Global mock state */
mock_espeak_state_t mock_espeak_state = {
    .initialize_call_count = 0,
    .initialize_data_path = nullptr,
    .initialize_audio_output = 0,
    .initialize_buffer_size = 0,

    .terminate_call_count = 0,

    .set_voice_call_count = 0,
    .set_voice_name = nullptr,
    .set_voice_result = EE_OK,

    .text_to_phonemes_call_count = 0,
    .text_to_phonemes_text = nullptr,
    .text_to_phonemes_chars = 0,
    .text_to_phonemes_mode = 0,
    .text_to_phonemes_result = nullptr,
    .text_to_phonemes_result_length = 0,
    .text_to_phonemes_terminator = nullptr,

    .simulate_error_on_initialize = false,
    .simulate_error_on_set_voice = false,
    .simulate_error_on_text_to_phonemes = false,
    .mock_phoneme_result = nullptr
};

/* API Implementations */

int espeak_Initialize(int audio_output, int buffer_size, const char *espeak_data_path,
                      int options) {
    mock_espeak_state.initialize_call_count++;
    mock_espeak_state.initialize_audio_output = audio_output;
    mock_espeak_state.initialize_buffer_size = buffer_size;
    if (espeak_data_path) {
        mock_espeak_state.initialize_data_path = strdup(espeak_data_path);
    } else {
        mock_espeak_state.initialize_data_path = nullptr;
    }

    if (mock_espeak_state.simulate_error_on_initialize) {
        return EE_ERROR;
    }

    return EE_OK;
}

void espeak_Terminate(void) {
    mock_espeak_state.terminate_call_count++;

    if (mock_espeak_state.initialize_data_path) {
        free((void*)mock_espeak_state.initialize_data_path);
        mock_espeak_state.initialize_data_path = nullptr;
    }
}

int espeak_SetVoiceByName(const char *name) {
    mock_espeak_state.set_voice_call_count++;
    if (name) {
        mock_espeak_state.set_voice_name = strdup(name);
    } else {
        mock_espeak_state.set_voice_name = nullptr;
    }

    if (mock_espeak_state.simulate_error_on_set_voice) {
        return mock_espeak_state.set_voice_result;
    }

    return mock_espeak_state.set_voice_result;
}

const char *espeak_TextToPhonemesWithTerminator(const void **text, int chars, int mode,
                                                int *terminator) {
    mock_espeak_state.text_to_phonemes_call_count++;
    if (*text) {
        mock_espeak_state.text_to_phonemes_text = strdup((const char*)*text);
    } else {
        mock_espeak_state.text_to_phonemes_text = nullptr;
    }
    mock_espeak_state.text_to_phonemes_chars = chars;
    mock_espeak_state.text_to_phonemes_mode = mode;
    if (terminator) {
        mock_espeak_state.text_to_phonemes_terminator = terminator;
    }

    if (mock_espeak_state.simulate_error_on_text_to_phonemes) {
        return nullptr;
    }

    if (mock_espeak_state.mock_phoneme_result) {
        mock_espeak_state.text_to_phonemes_result = strdup(mock_espeak_state.mock_phoneme_result);
    } else {
        // Default mock phoneme result: "hello world" in IPA
        mock_espeak_state.text_to_phonemes_result = strdup("həˈloʊ wɜːld");
    }
    mock_espeak_state.text_to_phonemes_result_length = strlen(mock_espeak_state.text_to_phonemes_result);

    // Set default terminator
    if (terminator) {
        *terminator = CLAUSE_PERIOD;
    }

    return mock_espeak_state.text_to_phonemes_result;
}

int espeak_GetVersion(void) {
    return 15000; // Mock version
}

// Disabled for now - requires espeak-ng header
// const espeak_VOICE *espeak_GetVoiceList(void) {
//     // Mock voice list - return NULL for now
//     return nullptr;
// }

int espeak_CompileDictionary(const char *path, const char *filename, int options) {
    return EE_OK; // Mock success
}

void espeak_SetPhonemeTrace(int trace) {
    // Mock implementation
}

/* Helper Functions */

void mock_espeak_reset(void) {
    if (mock_espeak_state.initialize_data_path) {
        free((void*)mock_espeak_state.initialize_data_path);
    }
    if (mock_espeak_state.set_voice_name) {
        free((void*)mock_espeak_state.set_voice_name);
    }
    if (mock_espeak_state.text_to_phonemes_text) {
        free((void*)mock_espeak_state.text_to_phonemes_text);
    }
    if (mock_espeak_state.text_to_phonemes_result) {
        free((void*)mock_espeak_state.text_to_phonemes_result);
    }

    memset(&mock_espeak_state, 0, sizeof(mock_espeak_state));
}

void mock_espeak_set_phoneme_result(const char *phonemes) {
    mock_espeak_state.mock_phoneme_result = phonemes ? strdup(phonemes) : nullptr;
}

void mock_espeak_set_error_simulation(bool error_on_initialize,
                                      bool error_on_set_voice,
                                      bool error_on_text_to_phonemes) {
    mock_espeak_state.simulate_error_on_initialize = error_on_initialize;
    mock_espeak_state.simulate_error_on_set_voice = error_on_set_voice;
    mock_espeak_state.simulate_error_on_text_to_phonemes = error_on_text_to_phonemes;
}

/* Getters for testing */

int mock_espeak_get_initialize_call_count(void) {
    return mock_espeak_state.initialize_call_count;
}

const char *mock_espeak_get_initialize_data_path(void) {
    return mock_espeak_state.initialize_data_path;
}

int mock_espeak_get_set_voice_call_count(void) {
    return mock_espeak_state.set_voice_call_count;
}

const char *mock_espeak_get_set_voice_name(void) {
    return mock_espeak_state.set_voice_name;
}

int mock_espeak_get_set_voice_result(void) {
    return mock_espeak_state.set_voice_result;
}

int mock_espeak_get_text_to_phonemes_call_count(void) {
    return mock_espeak_state.text_to_phonemes_call_count;
}

const char *mock_espeak_get_text_to_phonemes_text(void) {
    return mock_espeak_state.text_to_phonemes_text;
}

const char *mock_espeak_get_text_to_phonemes_result(void) {
    return mock_espeak_state.text_to_phonemes_result;
}

int mock_espeak_get_text_to_phonemes_result_length(void) {
    return mock_espeak_state.text_to_phonemes_result_length;
}

int *mock_espeak_get_text_to_phonemes_terminator(void) {
    return mock_espeak_state.text_to_phonemes_terminator;
}