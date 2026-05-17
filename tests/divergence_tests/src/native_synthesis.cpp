// Native C++ divergence test binary.
// Synthesizes arbitrary text using piper C API and writes 32-bit float WAV.
//
// Usage: native_divergence_test <config.json> <model.onnx> <espeak-data-dir> <text> <output.wav>

#include "piper.h"
#include <espeak-ng/speak_lib.h>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <memory>
#include <vector>

// RAII wrapper for FILE* to guarantee fclose.
struct FileDeleter { void operator()(FILE *f) const { if (f) std::fclose(f); } };
using UniqueFile = std::unique_ptr<FILE, FileDeleter>;

static UniqueFile make_unique_file(const char *path, const char *mode) {
    FILE *f = std::fopen(path, mode);
    return UniqueFile(f);
}

// Write a 32-bit float WAV file.
//
// WAV is a RIFF container with two mandatory chunks:
//   fmt  — describes the audio encoding (PCM format=1, IEEE float=3)
//   data — raw sample bytes
//
// RIFF header:
//   "RIFF" (4B)  — file type marker
//   file_size (4B) — size of everything after this field, i.e.
//                    4 ("WAVE") + fmt chunk size + data chunk size
//                    = 4 + 24 (fmt body) + 8 + data_size = 44 + data_size
//   "WAVE" (4B)  — format subtype
//
// fmt chunk (24 bytes total in file: 4 header + 4 size + 16 body):
//   "fmt "  (4B) — chunk ID
//   16      (4B) — size of the fmt body. 16 = "basic" PCM/float layout.
//                  18 would mean extra cbSize data follows.
//   3       (2B) — audio format: 1=PCM, 3=IEEE float, 6=A-law, 7=µ-law
//   num_channels (2B) — number of audio channels (1=mono, 2=stereo)
//   sample_rate (4B) — samples per second (e.g. 16000, 22050, 44100)
//   byte_rate (4B) = sample_rate × num_channels × bits_per_sample / 8
//                    — how many bytes stream processes per second
//   block_align (2B) = num_channels × bits_per_sample / 8
//                      — bytes per single sample position (one channel tick)
//   bits_per_sample (2B) — bits per sample value (16, 24, 32 for float)
//
// data chunk:
//   "data"  (4B) — chunk ID
//   data_size (4B) — number of bytes of sample data
//   raw_bytes — interleaved sample values (little-endian)
static bool write_wav(FILE *f, const std::vector<float> &samples, int sample_rate) {
    if (samples.empty()) return false;

    constexpr int num_channels = 1;       // mono
    constexpr int bits_per_sample = 32;   // 32-bit IEEE 754 float
    int data_size = static_cast<int>(samples.size()) * (bits_per_sample / 8);
    int file_size = 44 + data_size;       // 44 = RIFF header (12) + fmt chunk (24) + data chunk header (8)

    fwrite("RIFF", 1, 4, f);
    fwrite(&file_size, 4, 1, f);
    fwrite("WAVE", 1, 4, f);

    // fmt chunk
    fwrite("fmt ", 1, 4, f);
    int fmt_chunk_size = 16;              // no extra parameters (cbSize = 0)
    fwrite(&fmt_chunk_size, 4, 1, f);
    uint16_t audio_format = 3;            // WAVE_FORMAT_IEEE_FLOAT
    fwrite(&audio_format, 2, 1, f);
    fwrite(&num_channels, 2, 1, f);
    fwrite(&sample_rate, 4, 1, f);
    int byte_rate = sample_rate * num_channels * (bits_per_sample / 8);
    fwrite(&byte_rate, 4, 1, f);
    uint16_t block_align = num_channels * (bits_per_sample / 8);
    fwrite(&block_align, 2, 1, f);
    fwrite(&bits_per_sample, 2, 1, f);

    // data chunk
    fwrite("data", 1, 4, f);
    fwrite(&data_size, 4, 1, f);
    fwrite(samples.data(), 1, data_size, f);

    return true;
}

static int synthesize_to_wav(const char *config_path, const char *model_path,
      	                 const char *data_path, const char *text,
      	                 const char *wav_path) {
    int sr = espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, data_path, espeakCHARS_AUTO);
    if (sr < 0) return 1;

    piper_synthesizer *synth = piper_create(model_path, config_path, data_path);
    if (!synth) return 2;

    piper_synthesize_options opts = piper_default_synthesize_options(synth);
    int rc = piper_synthesize_start(synth, text, &opts);

    std::vector<float> all_samples;
    all_samples.reserve(160000);    // ~10 seconds at 16 kHz
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

    if (all_samples.empty()) {
        piper_free(synth);
        return 4;
    }

    UniqueFile f = make_unique_file(wav_path, "wb");
    if (!f) {
        piper_free(synth);
        return 3;
    }

    if (!write_wav(f.get(), all_samples, sample_rate)) {
        piper_free(synth);
        return 5;
    }

    return 0;
}

int main(int argc, char *argv[]) {
    if (argc != 6) {
        fprintf(stderr, "Usage: %s <config.json> <model.onnx> <espeak-data-dir> <text> <output.wav>\n",
                argc ? argv[0] : "native_divergence_test");
        return 1;
    }
    return synthesize_to_wav(argv[1], argv[2], argv[3], argv[4], argv[5]);
}
