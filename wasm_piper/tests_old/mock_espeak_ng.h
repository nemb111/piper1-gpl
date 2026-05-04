/**
 * Mock espeak-ng API for testing
 *
 * This file provides mock implementations of espeak-ng functions that can be
 * used in unit tests without requiring a full espeak-ng installation.
 */

#ifndef MOCK_ESPEAK_NG_H_
#define MOCK_ESPEAK_NG_H_

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Constants */
#define espeakCHARS_AUTO 0
#define espeakPHONEMES_IPA 1
#define EE_OK 0
#define EE_ERROR -1

/* Audio output modes */
#define AUDIO_OUTPUT_SYNCHRONOUS 1

/* Clause types for TextToPhonemesWithTerminator */
#define CLAUSE_INTONATION_FULL_STOP 0x00000000
#define CLAUSE_INTONATION_COMMA 0x00001000
#define CLAUSE_INTONATION_QUESTION 0x00002000
#define CLAUSE_INTONATION_EXCLAMATION 0x00003000
#define CLAUSE_TYPE_CLAUSE 0x00040000
#define CLAUSE_TYPE_SENTENCE 0x00080000
#define CLAUSE_PERIOD (40 | CLAUSE_INTONATION_FULL_STOP | CLAUSE_TYPE_SENTENCE)
#define CLAUSE_COMMA (20 | CLAUSE_INTONATION_COMMA | CLAUSE_TYPE_CLAUSE)
#define CLAUSE_QUESTION (40 | CLAUSE_INTONATION_QUESTION | CLAUSE_TYPE_SENTENCE)
#define CLAUSE_EXCLAMATION (45 | CLAUSE_INTONATION_EXCLAMATION | CLAUSE_TYPE_SENTENCE)
#define CLAUSE_COLON (30 | CLAUSE_INTONATION_FULL_STOP | CLAUSE_TYPE_CLAUSE)
#define CLAUSE_SEMICOLON (30 | CLAUSE_INTONATION_COMMA | CLAUSE_TYPE_CLAUSE)

/* Mock State Tracking */
typedef struct {
    int initialize_call_count;
    const char *initialize_data_path;
    int initialize_audio_output;
    int initialize_buffer_size;

    int terminate_call_count;

    int set_voice_call_count;
    const char *set_voice_name;
    int set_voice_result;

    int text_to_phonemes_call_count;
    const char *text_to_phonemes_text;
    int text_to_phonemes_chars;
    int text_to_phonemes_mode;
    const char *text_to_phonemes_result;
    int text_to_phonemes_result_length;
    int *text_to_phonemes_terminator;

    /* Configuration for mock behavior */
    bool simulate_error_on_initialize;
    bool simulate_error_on_set_voice;
    bool simulate_error_on_text_to_phonemes;
    const char *mock_phoneme_result;  /* Custom phoneme result */
} mock_espeak_state_t;

/* Global mock state */
extern mock_espeak_state_t mock_espeak_state;

/* API Function Declarations */

/**
 * Mock espeak_Initialize
 * @param audio_output Audio output mode
 * @param buffer_size Buffer size (unused in synchronous mode)
 * @param espeak_data_path Path to espeak-ng data directory
 * @param options Options
 * @return 0 on success, -1 on error
 */
int espeak_Initialize(int audio_output, int buffer_size, const char *espeak_data_path,
                      int options);

/**
 * Mock espeak_Terminate
 * Cleans up espeak-ng resources
 */
void espeak_Terminate(void);

/**
 * Mock espeak_SetVoiceByName
 * @param name Voice name
 * @return EE_OK on success, error code otherwise
 */
int espeak_SetVoiceByName(const char *name);

/**
 * Mock espeak_TextToPhonemesWithTerminator
 * @param text Pointer to text pointer (modified in-place)
 * @param chars Text encoding mode
 * @param mode Phoneme output mode
 * @param terminator Pointer to store terminator value
 * @return Pointer to phoneme string on success, NULL on error
 */
const char *espeak_TextToPhonemesWithTerminator(const void **text, int chars, int mode,
                                                int *terminator);

/**
 * Mock espeak_GetVersion
 * @return Mock version number
 */
int espeak_GetVersion(void);

// Disabled for now - requires espeak-ng header
// /**
//  * Mock espeak_GetVoiceList
//  * @return Mock voice list
//  */
// const espeak_VOICE *espeak_GetVoiceList(void);

/**
 * Mock espeak_CompileDictionary
 * @param path Path to dictionary
 * @param filename Dictionary filename
 * @param options Options
 * @return 0 on success, -1 on error
 */
int espeak_CompileDictionary(const char *path, const char *filename, int options);

/**
 * Mock espeak_SetPhonemeTrace
 * @param trace Enable/disable phoneme trace
 */
void espeak_SetPhonemeTrace(int trace);

/* Helper Functions for Testing */

/**
 * Reset mock state to initial values
 */
void mock_espeak_reset(void);

/**
 * Configure mock to return specific phoneme result
 * @param phonemes Phoneme string to return
 */
void mock_espeak_set_phoneme_result(const char *phonemes);

/**
 * Configure mock to simulate errors
 * @param error_on_initialize Whether to return error on initialize
 * @param error_on_set_voice Whether to return error on set_voice
 * @param error_on_text_to_phonemes Whether to return error on text_to_phonemes
 */
void mock_espeak_set_error_simulation(bool error_on_initialize,
                                      bool error_on_set_voice,
                                      bool error_on_text_to_phonemes);

/* Getters for test assertions */
int mock_espeak_get_initialize_call_count(void);
const char *mock_espeak_get_initialize_data_path(void);
int mock_espeak_get_set_voice_call_count(void);
const char *mock_espeak_get_set_voice_name(void);
int mock_espeak_get_set_voice_result(void);
int mock_espeak_get_text_to_phonemes_call_count(void);
const char *mock_espeak_get_text_to_phonemes_text(void);
const char *mock_espeak_get_text_to_phonemes_result(void);
int mock_espeak_get_text_to_phonemes_result_length(void);
int *mock_espeak_get_text_to_phonemes_terminator(void);

#ifdef __cplusplus
}
#endif

#endif /* MOCK_ESPEAK_NG_H_ */