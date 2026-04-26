// WASM integration test entry point.
// Calls the full piper API and returns results as JSON.
//
// For mock builds (MOCK_BUILD=1): uses mock_onnxruntime.cpp for deterministic
// output. Used by the baseline compatibility test.
//
// For real builds (no MOCK_BUILD): uses real ONNX Runtime for inference.
// Used by the real-ONNX similarity test.
//
// For native builds: main() calls run_integration_test() and outputs
// the JSON result to stdout.
// For WASM builds: Node.js calls run_integration_test() and reads the
// result via get_result_string().

#include "piper.h"
#include <espeak-ng/speak_lib.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <fstream>
#include <vector>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#else
#define EMSCRIPTEN_KEEPALIVE
#endif

// Global result storage for WASM
static char *g_result_ptr = nullptr;
static size_t g_result_len = 0;

// UTF-8 encode a char32_t codepoint, append to output string
static void append_utf8(std::string &out, char32_t cp) {
    if (cp < 0x80) {
        out.push_back(static_cast<char>(static_cast<unsigned>(cp) & 0xFF));
    } else if (cp < 0x800) {
        out.push_back(static_cast<char>((0xC0 | (cp >> 6)) & 0xFF));
        out.push_back(static_cast<char>((0x80 | (cp & 0x3F)) & 0xFF));
    } else if (cp < 0x10000) {
        out.push_back(static_cast<char>((0xE0 | (cp >> 12)) & 0xFF));
        out.push_back(static_cast<char>((0x80 | ((cp >> 6) & 0x3F)) & 0xFF));
        out.push_back(static_cast<char>((0x80 | (cp & 0x3F)) & 0xFF));
    } else {
        out.push_back(static_cast<char>((0xF0 | (cp >> 18)) & 0xFF));
        out.push_back(static_cast<char>((0x80 | ((cp >> 12) & 0x3F)) & 0xFF));
        out.push_back(static_cast<char>((0x80 | ((cp >> 6) & 0x3F)) & 0xFF));
        out.push_back(static_cast<char>((0x80 | (cp & 0x3F)) & 0xFF));
    }
}

extern "C" {

EMSCRIPTEN_KEEPALIVE
int run_integration_test(const char *config_path, const char *model_path,
                         const char *data_path) {
#ifdef __EMSCRIPTEN__
    // Ensure /espeak-ng-data directory structure exists for espeak-ng internal file ops.
    // The actual data files are mounted via --preload-file in CMake.
    emscripten_run_script_string(
        "try { "
        "  if (!FS.analyzePath('/espeak-ng-data').exists) { "
        "    FS.mkdir('/espeak-ng-data'); "
        "    FS.mkdir('/espeak-ng-data/voices'); "
        "    FS.mkdir('/espeak-ng-data/voices/!v'); "
        "  } "
        "} catch(e) { if(typeof console !== 'undefined') console.warn('FS init:', e); }"
    );
#endif

    const char *effective_data = data_path;
    if (!data_path || strlen(data_path) == 0) {
        effective_data = "/espeak-ng-data";
    }

    int sr = espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, effective_data, espeakCHARS_AUTO);
    if (sr < 0) return 1;

    piper_synthesizer *synth = piper_create(model_path, config_path, effective_data);
    if (!synth) return 2;

    piper_synthesize_options opts = piper_default_synthesize_options(synth);
    int rc = piper_synthesize_start(synth, "hello world", &opts);

    std::vector<float> all_samples;
    std::vector<char32_t> all_phonemes_cp;
    int sample_rate = 0;

    if (rc == PIPER_OK) {
        piper_audio_chunk chunk{};
        while (true) {
            rc = piper_synthesize_next(synth, &chunk);
            sample_rate = chunk.sample_rate;

            if (chunk.num_samples > 0) {
                all_samples.insert(all_samples.end(), chunk.samples,
                                   chunk.samples + chunk.num_samples);
            }
            if (chunk.num_phonemes > 0) {
                for (size_t i = 0; i < (size_t)chunk.num_phonemes; i++) {
                    all_phonemes_cp.push_back(chunk.phonemes[i]);
                }
            }
            if (rc == PIPER_DONE || rc == PIPER_ERR_GENERIC) break;
        }
    }

    std::string json;
    json.reserve(2048);
    json += "{\n";
    json += "  \"sample_rate\": " + std::to_string(sample_rate) + ",\n";
    json += "  \"phonemes\": \"";

    for (size_t i = 0; i < all_phonemes_cp.size(); i++) {
        char32_t cp = all_phonemes_cp[i];
        if (cp == (char32_t)0) { json += "\\u0000"; }
        else if (cp == (char32_t)'"') { json += "\\\""; }
        else if (cp == (char32_t)'\\') { json += "\\\\"; }
        else { append_utf8(json, cp); }
    }

    json += "\",\n";
    json += "  \"audio_samples\": [";

    for (size_t i = 0; i < all_samples.size(); i++) {
        if (i > 0) json += ",";
        char buf[32];
        snprintf(buf, sizeof(buf), "%.6f", all_samples[i]);
        json += buf;
    }

    json += "],\n";
    json += "  \"num_samples\": " + std::to_string(all_samples.size()) + ",\n";
    json += "  \"rc\": " + std::to_string(rc) + "\n}\n";

    // Store in global for WASM
    free(g_result_ptr);
    g_result_ptr = (char *)malloc(json.size() + 1);
    memcpy(g_result_ptr, json.data(), json.size());
    g_result_ptr[json.size()] = '\0';
    g_result_len = json.size() + 1;

    // For native: output directly
#ifndef __EMSCRIPTEN__
    fwrite(json.data(), 1, json.size(), stdout);
    piper_free(synth);
    free(g_result_ptr);
    g_result_ptr = nullptr;
#endif

    return 0;
}

EMSCRIPTEN_KEEPALIVE
int run_wav_write(const char *config_path, const char *model_path,
                  const char *data_path, const char *wav_path) {
    int sr = espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, data_path, espeakCHARS_AUTO);
    if (sr < 0) return 1;

    piper_synthesizer *synth = piper_create(model_path, config_path, data_path);
    if (!synth) return 2;

    piper_synthesize_options opts = piper_default_synthesize_options(synth);
    int rc = piper_synthesize_start(synth, "hello world", &opts);

    std::vector<float> all_samples;
    int sample_rate = 0;

    if (rc == PIPER_OK) {
        piper_audio_chunk chunk{};
        while (true) {
            rc = piper_synthesize_next(synth, &chunk);
            sample_rate = chunk.sample_rate;

            if (chunk.num_samples > 0) {
                all_samples.insert(all_samples.end(), chunk.samples,
                                   chunk.samples + chunk.num_samples);
            }
            if (rc == PIPER_DONE || rc == PIPER_ERR_GENERIC) break;
        }
    }

    // Write WAV file
    FILE *f = fopen(wav_path, "wb");
    if (!f) {
        piper_free(synth);
        return 3;
    }

    int num_channels = 1;
    int bits_per_sample = 32;
    int data_size = all_samples.size() * 4;
    int header_size = 44;
    int file_size = header_size + data_size;

    // RIFF header
    fprintf(f, "RIFF");
    fwrite(&file_size, 4, 1, f);
    fprintf(f, "WAVE");

    // fmt chunk
    fprintf(f, "fmt ");
    int fmt_chunk_size = 16;
    fwrite(&fmt_chunk_size, 4, 1, f);
    uint16_t audio_format = 3; // float
    fwrite(&audio_format, 2, 1, f);
    fwrite(&num_channels, 2, 1, f);
    fwrite(&sample_rate, 4, 1, f);
    int byte_rate = sample_rate * num_channels * (bits_per_sample / 8);
    fwrite(&byte_rate, 4, 1, f);
    uint16_t block_align = num_channels * (bits_per_sample / 8);
    fwrite(&block_align, 2, 1, f);
    fwrite(&bits_per_sample, 2, 1, f);

    // data chunk
    fprintf(f, "data");
    fwrite(&data_size, 4, 1, f);
    fwrite(all_samples.data(), 1, data_size, f);

    fclose(f);
    piper_free(synth);
    return 0;
}

EMSCRIPTEN_KEEPALIVE
const char *get_result_string() { return g_result_ptr; }

EMSCRIPTEN_KEEPALIVE
void free_result_string() { free(g_result_ptr); g_result_ptr = nullptr; }

} // extern "C"

int main(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: %s <config> <model> <espeak_data>\n", argc ? argv[0] : "test");
        return 1;
    }
    int rc = run_integration_test(argv[1], argv[2], argv[3]);
    fflush(stdout);
    return rc;
}
