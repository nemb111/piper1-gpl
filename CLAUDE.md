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
| C API | `libpiper/` | C++ library with C bindings; `libpiper/CMakeLists.txt` builds shared libpiper; see `libpiper/include/piper.h` |
| CMake build | `CMakeLists.txt` | Builds espeak-ng as ExternalProject, compiles `espeakbridge.c` module |
| Python setup | `setup.py` | scikit-build setup: CMake module, package data (espeak-ng-data, tashkeel) |
| WASM | `wasm_piper/` | WebAssembly build of libpiper for browser use |

### Build System

- **Python + C extension**: `setup.py` uses scikit-build to call CMake. The CMake build compiles espeak-ng from source and links it into `espeakbridge.c` (Python stable ABI module).
- **Development install**: `script/setup --dev` then `script/dev_build` (or `python3 setup.py build_ext --inplace`)
- **CMake modules are split by platform**: `cmake/native/` (native: `espeak_ng_external.cmake`, `onnxruntime_external.cmake`, `options.cmake`), `cmake/emscripten/` (WASM: `espeak_ng_external.cmake`, `find_emscripten.cmake`, `find_npm.cmake`, `find_onnxruntime_web.cmake`, `options.cmake`, `toolchain.cmake`). Options like `ONNXRUNTIME_VERSION` and `PIPER_ESPEAKNG_UPDATE_DISCONNECTED` default in `cmake/native/options.cmake`; `EMSCRIPTEN_VERSION` defaults in `cmake/emscripten/options.cmake` (auto-included by `find_emscripten.cmake`).
- **WASM build**: `cmake -B wasm_piper/build -S wasm_piper` (uses `find_emscripten.cmake` before `project()` for auto-download + compiler detection).
- **WASM onnxruntime**: Real onnxruntime is x86_64 Linux only — not WASM. Use `ort_shim` (header-only shim replacing `onnxruntime_cxx_api.h`) which forwards ONNX C++ API to onnxruntime-web via EM_JS. For mock builds (tests only), `mock_onnxruntime.cpp` is in `wasm_piper/tests_old/`.
- **ONNX Runtime Web (Node.js)**: Use `ort.env.wasm.numThreads = 1` to avoid thread affinity errors on headless servers. Import via `const ort = require('onnxruntime-web')`.
- **ort_shim moved**: `onnxruntime_cxx_api.h`, `ort_shim.js` → `wasm_piper/shim/src/`. `ort_shim_external.cmake` also moved there. `ort_shim.cpp` deleted (stub with no actual definitions).
- **ort_shim header-only**: Every definition in `onnxruntime_cxx_api.h` is header-only (EM_JS inline, template methods, inline class bodies). Nothing can move to a `.cpp`.
- **WASM test target**: `piper_wasm_mock_integration_test` (mock ONNX, baseline compatibility) — defined in `wasm_piper/tests/CMakeLists.txt`. Mock ONNX files are in `wasm_piper/tests_old/`.
- **ort_shim WASM build config**: `SHIM_SRC_DIR` must be set to `${CMAKE_CURRENT_SOURCE_DIR}/shim/src` before including `ort_shim_external.cmake` (in `wasm_piper/CMakeLists.txt`). INTERFACE include dirs don't always propagate — add `${SHIM_SRC_DIR}` directly to `target_include_directories(piper_wasm)` in the main CMakeLists.txt.
- INTERFACE libraries can't be linked (`target_link_libraries` will try to find `-l<name>` and fail). Use INTERFACE only for include paths; link real libraries directly.
- **WASM tests**: Run `node wasm_piper/tests/test_wasm_integration.js` (mock mode).
- **ort_shim (WASM ONNX bridge)**: `wasm_piper/shim/src/onnxruntime_cxx_api.h` defines `Ort` namespace forwarding ONNX C++ API to `wasm_piper/shim/src/ort_shim.js` via EM_JS. Session init is lazy (stored model path, init on first `Run()`). Input tensors queued via `ort_shim_set_input_data()`, inference triggered from `Session::Run()`. Audio copied from ort.js tensor to Emscripten heap (double-buffered). The shim replaces the real ONNX Runtime header via include path resolution.
- **Test voice models**: `en_US-amy-low.onnx` (63MB) in `external/piper_voices/`. Downloaded by `python3 tests/divergence_tests/setup.py download-voices --voice en_US-amy-low` from `rhasspy/piper-voices` HuggingFace repo. WASM preload maps `external/piper_voices/` → `/piper_voices/` in WASM FS.
- **ONNX header**: `piper_impl.hpp` unconditionally includes `<onnxruntime_cxx_api.h>`. For WASM builds, the ort_shim version is picked up via include path precedence (it sits first in the compiler's include search). For mock builds, `MOCK_BUILD=1` is passed to the compiler, and `mock_onnxruntime.cpp` is compiled instead of the real ONNX code.
- **ONNX input shapes**: `input` is `[1, N]` phoneme IDs, `input_lengths` is `[1]` (scalar count), `scales` is `[3]` (noise_scale, length_scale, noise_w). Multi-speaker models also need `sid` as `[1]` speaker ID.
- **Wheels**: `python3 -m build` or `script/package`

### CMake ExternalProject Gotchas

- `if()/endif()` blocks do NOT work inside `ExternalProject_Add()` — use variable substitution.
- `@`-prefixed CMake variable expansion does NOT work for `PATCH_COMMAND` — use a shell script that no-ops on empty args.
- `CMAKE_CURRENT_SOURCE_DIR` resolves inside the ExternalProject context, not the caller. Use `get_filename_component(_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)` to reach the repo root.
- When including native cmake modules from subdirectories, use `${CMAKE_CURRENT_LIST_DIR}/../cmake/native/...` pattern (not `${_repo_root}/cmake/...`), matching how `libpiper/CMakeLists.txt` includes `espeak_ng_external.cmake` and `onnxruntime_external.cmake`.
- `configure_espeak_ng_external()` requires mandatory toolchain vars (`PIPER_ESPEAKNG_UPDATE_DISCONNECTED`, `PIPER_ESPEAKNG_CMAKE_ARGS`). Set before calling; the function validates and errors if missing. The old `PIPER_ESPEAKNG_PATCH_SCRIPT` var is gone.
- `configure_onnxruntime_external()` checks `if(TARGET onnxruntime_iface_lib)` as a no-op guard — WASM callers predefine it; native callers let the function create it.
- When including a CMake module from a subdirectory (e.g. `shim/src/ort_shim_external.cmake`), `CMAKE_CURRENT_SOURCE_DIR` inside the included file resolves to the _caller's_ source dir, not the module's directory. Use caller-set variables (e.g. `SHIM_SRC_DIR`) instead.
- External library downloads go in `CMAKE_BINARY_DIR/external/` — never in the source tree. Deleting `build/` removes everything and reconfiguration re-downloads.
- ExternalProject does NOT inherit CMAKE_C/CXX_COMPILER from parent config — must pass via CMAKE_ARGS or env vars. For WASM, set `PIPER_ESPEAKNG_CMAKE_ARGS "-DCMAKE_C_COMPILER=${EMCC_PATH}" "-DCMAKE_CXX_COMPILER=${EMCC_PATH}"`.
- CMake's `file(CREATE_LINK)` fails in the Emscripten toolchain context — use `execute_process(COMMAND sh -c "ln -sfn ...")` instead.
- In `wasm_piper/CMakeLists.txt`, `_repo_root` must be defined via `get_filename_component` before any block (including auto-install) that references it.
- `wasm_piper/node_modules` is a symlink to `external/node_modules/`. CMake auto-installs onnxruntime-web there on first configure.
- Two mount points exist for the same repo: `/mnt/agent_workspace/` and `/home/claude/workspace/`. Ensure `pwd` and CMake `WORKING_DIRECTORY` align to avoid path mismatches.

### Running and Testing

```sh
# Setup dev environment
script/setup --dev

# Build C extension
script/dev_build

# Setup divergence tests (deps + native binary + Vosk model)
python3 tests/divergence_tests/setup.py all
# Individual steps: deps | build-native | download-model | download-voices | espeak-data | deterministic-config | build-wasm
# Select voice: python3 tests/divergence_tests/setup.py --voice en_US-amy-low all
# List voices:  python3 tests/divergence_tests/setup.py --list-voices

# Divergence tests use voices from external/piper_voices/ (no symlinks).
# Generated configs (deterministic onnx.json files): tests/divergence_tests/generated/ (auto-generated, do not commit)

# Run CLI
python3 -m piper --model en_US-lessac-medium.onnx --output-file out.wav "Hello world"

# Run tests
script/test

# Run tests directly (skip slow Chinese phonemizer test)
pytest tests/

# Synthesize audio (onnxruntime-web, WASM in Node)
node wasm_piper/synthesize.js model.onnx model.onnx.json "text" output.wav

# Divergence validation: run setup once, then compare Python vs native vs WASM output
python3 tests/divergence_tests/setup.py all && pytest tests/divergence_tests/test_divergence.py -v
# Quick subset: only Python vs native comparison
pytest tests/divergence_tests/test_divergence.py -v -k "test_python_vs_native"
# Negative test: verify metric can distinguish different text
pytest tests/divergence_tests/test_divergence.py -v -k "test_different_texts_not_similar"
```

**Acceptance criteria for WASM code changes:** Always run `python3 tests/divergence_tests/setup.py all` before running divergence tests — WASM builds (ort_shim, CMakeLists.txt, shim/src/) require the full divergence suite (Python vs native vs WASM) to validate correctness.

**openl3 install caveat (Python 3.12):** openl3 0.4.2 uses the removed `imp` module. Before `pip install "piper-tts[divergence]"`, patch `import imp` → `import importlib.util` + `imp.load_source()` → `importlib.util` in `openl3/setup.py`. Install with `--no-deps` to avoid dependency conflicts.

The test suite (`tests/`) includes:
- `test_piper.py` - Core synthesis tests
- `test_espeak_phonemizer.py` - espeak-ng phonemization
- `test_tashkeel.py` - Arabic diacritization
- `test_chinese_phonemizer.py` - g2pW Chinese phonemizer (excluded from default pytest run)
- `test_divergence.py` - Cross-variant audio similarity (Python vs native vs WASM). Compares pairwise by transcribing back to text using Vosk speech recognition and computing SequenceMatcher word-list ratio. Simulates synthesis via native C++ binary (`tests/divergence_tests/build/native_divergence_test`) and WASM (`wasm_piper/synthesize.js`). Includes negative tests (`test_different_texts_not_similar`) to verify metric can distinguish dissimilar audio. **63 tests total**: 20 quotes × 3 pairwise comparisons + 3 negative tests. Prerequisites: `python3 tests/divergence_tests/setup.py all` (installs deps, builds native binary, downloads voice models from `external/piper_voices/`, deterministic config, Vosk model). Deterministic config files live in `tests/divergence_tests/generated/` (not `data/`). When modifying the config copy in `setup.py`, use `ensure_ascii=True` in `json.dump` to preserve `\uXXXX` escape sequences matching the source voice model's encoding.
- `wasm_piper/tests/` - WASM integration tests (JS runner + C++ main). `wasm_piper/tests_old/` — stale mock ONNX/espeak-ng test files (mock_onnxruntime.cpp, mock_espeak_ng.cpp).

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
- **espeak-ng data (WASM)**: Pre-compiled espeak-ng data files are loaded via WASM FS `--preload-file` in the CMake link flags (e.g., `--preload-file tests/data/espeak-ng-data@/`). The old `cmake/patch_espeak_data.sh` script is gone; espeak-ng data is now preloaded directly.
- **ONNX CPU vs WASM audio**: When running the same ONNX model on CPU (onnxruntime) vs WASM (onnxruntime-web), floating-point divergence is significant. **For divergence tests, use log-mel spectrogram correlation + sigmoid** (`tests/test_divergence.py`): n_mels=24, sigmoid(k=10). Same-text ~0.93, different-text ~0.48. openl3 captures voice timbre not linguistic content — it gives ~0.99 similarity for any two clips from the same voice regardless of text. WASM divergence varies by quote (similarity 0.41-0.99); threshold ~0.80 catches significant divergence while being realistic.
- **Audio comparison for short TTS clips (2-5s, same voice)**: openl3 fails (captures timbre, ~0.99 always). Log-mel correlation with fewer bands (n_mels=24) + sigmoid(k=10) is content-sensitive. More bands increase WASM divergence impact. Correlation > cosine because it's robust to amplitude differences between variants.
- **EM_ASYNC_JS crash in Emscripten 5.0.6**: EM_ASYNC_JS + ASYNCIFY crashes during stack restoration (Asyncify `doRewind`). Keep async logic in JS layer; C++ EM_JS must be synchronous.
- **WASM piper_audio_chunk layout (32-bit)**: 10 fields at offsets [0,4,8,12,16,20,24,28,32,36] — samples ptr, num_samples, sample_rate, is_last, phonemes ptr, num_phonemes, phoneme_ids ptr, num_phoneme_ids, alignments ptr, num_alignments. Total: 40 bytes.
- **piper_default_synthesize_options**: Returns struct by value — cannot use `ccall` for this. Must manually write option values to WASM heap (speaker_id as i32 at offset 0, length_scale/f32 at offset 4, noise_scale/f32 at offset 8, noise_w/f32 at offset 12).
- **ort.js tensor vs Emscripten heap**: ort.js uses a separate WASM memory. Audio data must be copied to Emscripten heap via ort_shim (double-buffered with flip). `GetTensorData()` must return ort_shim's heap pointer, not the ort.js tensor pointer — `OrtRelease` on the ort.js tensor corrupts it.
- **Extract before access**: `HEAPU8.buffer !== ort.js tensor.buffer` — direct typed array views across WASM memories fail. Must extract all values to a plain JS array first, then write to Emscripten heap via `ArrayBuffer` + `Uint8Array.set()`.
- **EM_ASYNC_JS parameter limit**: 8th+ parameters silently drop. Use separate EM_JS getters (e.g. `ort_shim_get_audio_ptr`) for output values. State written inside EM_ASYNC_JS is accessible from EM_JS immediately after return.
- **ort_shim internal orchestration**: Synthesis scripts (synthesize.js) must ONLY use the piper C API (`piper_create`, `piper_synthesize_start`, `piper_synthesize_next`, `piper_free`). All ONNX Runtime setup, input batching, inference triggering, and audio copying are internal to ort_shim.js. `ortShimModule` is never called directly from synthesis scripts.
- **Value for heap pointers**: When returning audio from `Session::Run()`, set `Value.data_ = (void*)audioPtrC` (heap pointer from ort_shim). `Value::GetTensorData()` must check `ort_shim_get_audio_ptr()` and return the heap pointer.
