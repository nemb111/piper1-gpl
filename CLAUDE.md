# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Piper is a fast, local neural text-to-speech (TTS) engine built by the Open Home Foundation. It uses espeak-ng for phonemization and ONNX Runtime for inference. The project has two main code paths:

- **Python package** (`src/piper/`): The primary interface, providing a CLI (`piper`), Python API (`PiperVoice`), and Flask HTTP server. This is the main development focus.
- **C/C++ library** (`libpiper/`): A standalone C API (`piper_create`, `piper_synthesize_start`, `piper_synthesize_next`) for embedding Piper in other applications. It bundles espeak-ng and onnxruntime.

### Key Components

| Area | Location | Purpose |
|------|----------|---------|
| Core Python API | `src/piper/voice.py` | `PiperVoice` class: loads ONNX models, phonemizes text, synthesizes audio |
| Configuration | `src/piper/config.py` | `PiperConfig`, `SynthesisConfig` dataclasses |
| C-bridge (build) | `src/piper/espeakbridge.c` | Python stable ABI bridge to embedded espeak-ng (built via CMake) |
| Training pipeline | `src/piper/train/` | VITS-based training: models, dataset, lightning, export to ONNX |
| Training VITS internals | `src/piper/train/vits/` | VITS model architecture (attention, mel spectrograms, monotonic alignment) |
| Chinese phonemizer | `src/piper/phonemize_chinese.py` | g2pW-based pinyin phonemizer |
| Arabic diacritics | `src/piper/tashkeel/` | ONNX-based diacritization model for Arabic |
| CLI entry point | `src/piper/__main__.py` | `piper` command: file/stdin/argument input, WAV output or ffplay playback |
| HTTP server | `src/piper/http_server.py` | Flask API: `/`, `/voices`, `/all-voices`, `/download` |
| Voice downloads | `src/piper/download_voices.py` | Downloads `.onnx` + `.json` from HuggingFace piper-voices repo |
| C API | `libpiper/` | C++ library with C bindings; see `libpiper/include/piper.h` |
| CMake build | `CMakeLists.txt` | Builds espeak-ng as ExternalProject, compiles `espeakbridge.c` module |
| Python setup | `setup.py` | scikit-build setup: CMake module, package data (espeak-ng-data, tashkeel) |
| WASM | `wasm_piper/` | WebAssembly build of libpiper for browser use |

### Build System

- **Python + C extension**: `setup.py` uses scikit-build to call CMake. The CMake build compiles espeak-ng from source and links it into `espeakbridge.c` (Python stable ABI module).
- **Development install**: `script/setup --dev` then `script/dev_build` (or `python3 setup.py build_ext --inplace`)
- **CMake modules are split by platform**: `cmake/native/` (native: `espeak_ng_external.cmake`, `onnxruntime_external.cmake`, `options.cmake`), `cmake/emscripten/` (WASM: `espeak_ng_external.cmake`, `find_emscripten.cmake`, `options.cmake`). Options like `ONNXRUNTIME_VERSION` and `PIPER_ESPEAKNG_UPDATE_DISCONNECTED` default in `cmake/native/options.cmake`; `EMSCRIPTEN_VERSION` defaults in `cmake/emscripten/options.cmake` (auto-included by `find_emscripten.cmake`).
- **WASM build**: `cmake -B wasm_piper/build -S wasm_piper` (uses `find_emscripten.cmake` before `project()` for auto-download + compiler detection).
- **WASM onnxruntime**: Real onnxruntime is x86_64 Linux only — not WASM. Compile `mock_onnxruntime.cpp` directly into the target and define a no-op `onnxruntime_iface_lib` before `configure_onnxruntime_external()` to skip download.
- **ONNX Runtime Web (Node.js)**: Use `ort.env.wasm.numThreads = 1` to avoid thread affinity errors on headless servers. Import via `const ort = require('onnxruntime-web')`.
- **ort_shim moved**: `onnxruntime_cxx_api.h`, `ort_shim.js` → `wasm_piper/shim/src/`. `ort_shim_external.cmake` also moved there. `ort_shim.cpp` deleted (stub with no actual definitions).
- **ort_shim header-only**: Every definition in `onnxruntime_cxx_api.h` is header-only (EM_JS inline, template methods, inline class bodies). Nothing can move to a `.cpp`.
- **WASM test target**: `piper_wasm_mock_integration_test` (mock ONNX, baseline compatibility), built via `cmake -B wasm_piper/build -S wasm_piper`.
- **WASM build**: `cmake -B wasm_piper/build -S wasm_piper`. The `SHIM_SRC_DIR` variable must be set to `${CMAKE_CURRENT_SOURCE_DIR}/shim/src` before including `ort_shim_external.cmake`. INTERFACE include dirs don't always propagate — add `${SHIM_SRC_DIR}` directly to `target_include_directories(piper_wasm)` in the main CMakeLists.txt.
- INTERFACE libraries can't be linked (`target_link_libraries` will try to find `-l<name>` and fail). Use INTERFACE only for include paths; link real libraries directly.
- **WASM tests**: Run `node wasm_piper/tests/test_wasm_integration.js` (mock mode).
- **ort_shim (WASM ONNX bridge)**: `wasm_piper/shim/src/onnxruntime_cxx_api.h` defines `Ort` namespace forwarding ONNX C++ API to `wasm_piper/shim/src/ort_shim.js` via EM_JS. Session init is async (done externally by JS via `ort_shim_init()`). Input tensors are queued via `ort_shim_set_input_data()` and inference is triggered from JS (`startNextInference()`). The shim replaces the real ONNX Runtime header via include path resolution.
- **ort_shim test harness**: `wasm_piper/tests/run_piper.js` uses piper_create for setup, then handles ONNX inference entirely from JS — phonemize via `spawnSync` on espeak-ng CLI, run ONNX via `ort.InferenceSession`, write WAV. This avoids C++ path async issues.
- **Test voice models**: `en_US-amy-low.onnx` (63MB) in `wasm_piper/tests/data/`. Downloaded from `rhasspy/piper-voices` HuggingFace repo.
- **ONNX switch**: `piper_impl.hpp` uses `#ifdef MOCK_BUILD` to choose mock vs real ONNX Runtime. Real builds include `<onnxruntime_cxx_api.h>`.
- **ONNX input shapes**: `input` is `[1, N]` phoneme IDs, `input_lengths` is `[1]` (scalar count), `scales` is `[3]` (noise_scale, length_scale, noise_w). Multi-speaker models also need `sid` as `[1]` speaker ID.
- **Wheels**: `python3 -m build` or `script/package`

### CMake ExternalProject Gotchas

- `if()/endif()` blocks do NOT work inside `ExternalProject_Add()` — use variable substitution.
- `@`-prefixed CMake variable expansion does NOT work for `PATCH_COMMAND` — use a shell script that no-ops on empty args.
- `CMAKE_CURRENT_SOURCE_DIR` resolves inside the ExternalProject context, not the caller. Use `get_filename_component(_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)` to reach the repo root.
- When including native cmake modules from subdirectories, use `${CMAKE_CURRENT_LIST_DIR}/../cmake/native/...` pattern (not `${_repo_root}/cmake/...`), matching how `libpiper/CMakeLists.txt` includes `espeak_ng_external.cmake` and `onnxruntime_external.cmake`.
- `configure_espeak_ng_external()` requires mandatory toolchain vars (`PIPER_ESPEAKNG_UPDATE_DISCONNECTED`, `PIPER_ESPEAKNG_PATCH_SCRIPT`, `PIPER_ESPEAKNG_CMAKE_ARGS`). Set before calling; the function validates and errors if missing.
- `configure_onnxruntime_external()` checks `if(TARGET onnxruntime_iface_lib)` as a no-op guard — WASM callers predefine it; native callers let the function create it.
- When including a CMake module from a subdirectory (e.g. `shim/src/ort_shim_external.cmake`), `CMAKE_CURRENT_SOURCE_DIR` inside the included file resolves to the _caller's_ source dir, not the module's directory. Use caller-set variables (e.g. `SHIM_SRC_DIR`) instead.
- External library downloads go in `CMAKE_BINARY_DIR/external/` — never in the source tree. Deleting `build/` removes everything and reconfiguration re-downloads.
- ExternalProject does NOT inherit CMAKE_C/CXX_COMPILER from parent config — must pass via CMAKE_ARGS or env vars. For WASM, set `PIPER_ESPEAKNG_CMAKE_ARGS "-DCMAKE_C_COMPILER=${EMCC_PATH}" "-DCMAKE_CXX_COMPILER=${EMCC_PATH}"`.

### Running and Testing

```sh
# Setup dev environment
script/setup --dev

# Build C extension
script/dev_build

# Run CLI
python3 -m piper --model en_US-lessac-medium.onnx --output-file out.wav "Hello world"

# Run tests
script/test

# Run tests directly (skip slow Chinese phonemizer test)
pytest tests/

# Synthesize audio for comparison (native vs WASM)
python3 wasm_piper/tests/synthesize.py model.onnx model.onnx.json "text" output.wav
node wasm_piper/tests/synthesize_node.js model.onnx model.onnx.json "text" output.wav

# WASM JS test harness (handles ONNX inference from JS to avoid EM_ASYNC_JS crash)
node wasm_piper/tests/run_piper.js "text to synthesize" output.wav (ort_shim.js require path updated to shim/src/)
```

The test suite (`tests/`) includes:
- `test_piper.py` - Core synthesis tests
- `test_espeak_phonemizer.py` - espeak-ng phonemization
- `test_tashkeel.py` - Arabic diacritization
- `test_chinese_phonemizer.py` - g2pW Chinese phonemizer (excluded from default pytest run)
- `libpiper/tests/` - C/C++ tests with mock espeak-ng and onnxruntime

### Training

Training code is in `src/piper/train/`. Requires `torch` and `lightning` (`script/setup --train`). Key files:
- `src/piper/train/__main__.py` - Entry point
- `src/piper/train/vits/lightning.py` - PyTorch Lightning module
- `src/piper/train/vits/models.py` - VITS model architecture
- `src/piper/train/export_onnx.py` - Export trained model to ONNX

## Architecture Notes

- **Phonemization flow**: Text -> (Tashkeel for Arabic) -> espeak-ng/g2pW/text -> phoneme list -> phoneme IDs -> ONNX inference -> audio
- **PiperConfig** lives in a JSON sidecar file (e.g., `voice.onnx.json`). It's loaded when constructing `PiperVoice`.
- **espeak-ng-data** is bundled as part of the CMake build (copied from espeak-ng install to `src/piper/espeak-ng-data/`).
- **ONNX models** are the voice files. They accept `input` (phoneme IDs), `input_lengths`, `scales` (noise, length, noise_w), optional `sid` (speaker ID). Outputs: audio waveform (+ optionally alignment data).
- **Multi-speaker voices**: `num_speakers > 1` in config, `sid` input required for inference.
- **Phoneme types**: `espeak` (default), `text` (raw IPA), `pinyin` (Chinese g2pW).
- **espeak-ng data injection (WASM)**: Pre-compiled data files from a native build are copied into the espeak-ng source tree via `cmake/patch_espeak_data.sh` (PATCH_COMMAND). Never try to run the espeak-ng WASM binary to generate data.
- **ONNX CPU vs WASM audio**: When running the same ONNX model on CPU (onnxruntime) vs WASM (onnxruntime-web), floating-point divergence is significant — cosine similarity of raw waveforms was ~0.07 for identical inputs. Use perceptual metrics (openl3) for meaningful comparison, not sample-wise similarity.
- **EM_ASYNC_JS crash in Emscripten 5.0.6**: EM_ASYNC_JS + ASYNCIFY crashes during stack restoration (Asyncify `doRewind`). Keep async logic in JS layer; C++ EM_JS must be synchronous.
- **WASM piper_audio_chunk layout (32-bit)**: 10 fields at offsets [0,4,8,12,16,20,24,28,32,36] — samples ptr, num_samples, sample_rate, is_last, phonemes ptr, num_phonemes, phoneme_ids ptr, num_phoneme_ids, alignments ptr, num_alignments. Total: 40 bytes.
- **piper_default_synthesize_options**: Returns struct by value — cannot use `ccall` for this. Must manually write option values to WASM heap (speaker_id as i32 at offset 0, length_scale/f32 at offset 4, noise_scale/f32 at offset 8, noise_w/f32 at offset 12).
