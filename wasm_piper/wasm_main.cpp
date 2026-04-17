#include "piper.h"

// Ensure every public Piper API is referenced so the compile test
// actually verifies that all functions link correctly.
void call_all_apis() {
    // Types
    piper_synthesizer *synth = nullptr;
    piper_audio_chunk chunk{};
    piper_synthesize_options opts{};

    // Functions
    synth = piper_create(nullptr, nullptr, nullptr);
    opts = piper_default_synthesize_options(synth);
    (void)opts;
    int rc = piper_synthesize_start(synth, "", nullptr);
    (void)rc;
    rc = piper_synthesize_next(synth, &chunk);
    (void)rc;
    piper_free(synth);

    // Error codes
    (void)PIPER_OK;
    (void)PIPER_DONE;
    (void)PIPER_ERR_GENERIC;
}

int main() {
    call_all_apis();
    return 0;
}
