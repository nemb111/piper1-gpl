# Piper Divergence Tests

Cross-variant audio similarity tests comparing Python API, native C++ libpiper, and WASM/Emscripten builds.

## Overview

The test suite synthesizes 20 public domain quotes through all three build variants (60 WAV files total) and compares them pairwise by transcribing back to text using [Vosk](https://github.com/alphacep/vosk-api) speech recognition and computing SequenceMatcher word-list ratio. All three variants should produce perceptually identical audio for the same input.

## Setup

Install divergence dependencies and set up the environment:

```sh
pip install "piper-tts[divergence]"
python3 tests/divergence_tests/setup.py all
# Individual steps: deps | build-native | download-model
```

Also ensure the WASM build artifacts exist at `wasm_piper/build/` (run `cmake -B wasm_piper/build -S wasm_piper` if needed).

## Running

Run all 60 tests:

```sh
pytest tests/test_divergence.py -v
```

Run a single comparison type:

```sh
pytest tests/test_divergence.py -v -k "test_python_vs_native"
pytest tests/test_divergence.py -v -k "test_python_vs_wasm"
pytest tests/test_divergence.py -v -k "test_native_vs_wasm"
```

## What Happens on First Run

1. **Native build** — `tests/divergence_tests/CMakeLists.txt` builds the native C++ test binary (`tests/divergence_tests/build/native_divergence_test`) via CMake. This includes an ExternalProject build of espeak-ng and onnxruntime.
2. **Synthesis** — All 60 WAV files are generated (32-bit float) and written to `tests/divergence_wav/{python,native,wasm}/div_01.wav` through `div_20.wav`. Synthesized files are cached; existing WAVs are reused on subsequent runs.
3. **Comparison** — Each test transcribes a pair of WAVs with Vosk (model at `external/vosk-model-en-us-0.22`) and computes SequenceMatcher word-list ratio.

## Test Structure

| Test | Compares |
|------|------|
| `test_python_vs_native` | Python API vs native C++ libpiper |
| `test_python_vs_wasm` | Python API vs WASM/Emscripten |
| `test_native_vs_wasm` | Native C++ libpiper vs WASM/Emscripten |

Each test is parameterized with 20 quotes, yielding 20 test instances per comparison = 60 total.
Similarity threshold: 0.95 (exact word-level match required).

## Negative Tests

| Test | Purpose |
|------|---------|
| `test_different_texts_not_similar` | Verifies different text produces different audio (similarity < 0.5) |

## Skip Conditions

Tests skip automatically when:
- WASM build artifacts are missing (WASM build not found)
- CMake fails to configure/build the native binary (Native CMake configure/build failed)
