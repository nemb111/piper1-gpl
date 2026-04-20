/**
 * Thin wrapper exposing the piper C API for WASM / Node.js testing.
 *
 * Each function mirrors the API declared in piper.h (from libpiper/src/piper.cpp)
 * with EMSCRIPTEN_KEEPALIVE so the symbols are exported for JS ccall access.
 *
 * This file is compiled into the WASM target alongside piper.cpp (or its mock).
 * The piper_* functions are already extern "C" in piper.cpp — this wrapper
 * re-adds EMSCRIPTEN_KEEPALIVE so Emscripten retains the symbols.
 */

#include <emscripten.h>
#include "piper.h"

extern "C" {

EMSCRIPTEN_KEEPALIVE
piper_synthesizer* piper_wasm_create(const char* model_path,
                                     const char* config_path,
                                     const char* espeak_data_path) {
    return piper_create(model_path, config_path, espeak_data_path);
}

EMSCRIPTEN_KEEPALIVE
void piper_wasm_free(piper_synthesizer* synth) {
    piper_free(synth);
}

EMSCRIPTEN_KEEPALIVE
void piper_wasm_default_synthesize_options(piper_synthesizer* synth,
                                           void* out_opts) {
    piper_synthesize_options opts = piper_default_synthesize_options(synth);
}

EMSCRIPTEN_KEEPALIVE
int piper_wasm_synthesize_start(piper_synthesizer* synth,
                                const char* text,
                                const void* options) {
    return piper_synthesize_start(synth, text,
                                  (const piper_synthesize_options*)options);
}

EMSCRIPTEN_KEEPALIVE
int piper_wasm_synthesize_next(piper_synthesizer* synth, void* chunk) {
    return piper_synthesize_next(synth, (piper_audio_chunk*)chunk);
}

} // extern "C"
