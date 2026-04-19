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
- **Shared CMake module**: `cmake/espeak_ng_external.cmake` — `configure_espeak_ng_external([PREBUILT_DATA_DIR])` requires toolchain vars set by caller. Used by `libpiper/CMakeLists.txt` (native) and `wasm_piper/CMakeLists.txt` (WASM).
- **WASM build**: `cmake -B wasm_piper/build -S wasm_piper` (uses `find_emscripten.cmake` before `project()` for auto-download + compiler detection).
- **Wheels**: `python3 -m build` or `script/package`

### CMake ExternalProject Gotchas

- `if()/endif()` blocks do NOT work inside `ExternalProject_Add()` — use variable substitution.
- `@`-prefixed CMake variable expansion does NOT work for `PATCH_COMMAND` — use a shell script that no-ops on empty args.
- `CMAKE_CURRENT_SOURCE_DIR` resolves inside the ExternalProject context, not the caller. Use `get_filename_component(_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)` to reach the repo root.
- `configure_espeak_ng_external()` requires mandatory toolchain vars (`PIPER_ESPEAKNG_UPDATE_DISCONNECTED`, `PIPER_ESPEAKNG_PATCH_SCRIPT`, `PIPER_ESPEAKNG_CMAKE_ARGS`). Set before calling; the function validates and errors if missing.
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
