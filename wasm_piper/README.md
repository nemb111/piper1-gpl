# WASM Piper

WebAssembly build of [Piper](https://github.com/rhasspy/piper) -- a fast, local neural text-to-speech engine. The WASM build compiles Piper's C++ library (espeak-ng phonemizer + ONNX Runtime inference) into `.wasm` files that run in Node.js or the browser.

## Prerequisites

- CMake >= 3.26
- Python 3 with virtual environment
- Node.js 18+ (for test runners)
- Git

Emscripten will be **auto-detected** or **auto-downloaded** by the CMake build. No manual setup needed.

## Quick Start

### 1. Build (Mock Mode)

```sh
python3 wasm_piper/build.py                    # downloads tools, onnxruntime-web, builds WASM, downloads default voice
cmake --build wasm_piper/build --target piper_wasm_mock_integration_test
```

This builds:
- `piper_wasm_mock_integration_test.js/.wasm` -- mock ONNX integration test

### 2. Generate Audio from WASM Build

The compiled WASM module (`piper_wasm`) can synthesize speech using the C++ path for phonemization (via the `piper_create` / `piper_synthesize_start` APIs) and onnxruntime-web for inference.

**Step 1 — Build (via build.py):**
```sh
python3 wasm_piper/build.py
```
This produces `wasm_piper/build/piper_wasm.{js,wasm}` and downloads the default voice (`en_US-lessac-medium`) to `external/piper_voices/`.

**Step 2 — Synthesize:**
```sh
cd wasm_piper
node synthesize.js ../external/piper_voices/en_US-lessac-medium.onnx ../external/piper_voices/en_US-lessac-medium.onnx.json "Hello from the WASM build" /tmp/output.wav
```

## Synthesizing Audio

The unified `synthesize.js` script produces 16-bit PCM WAV files using `onnxruntime-web` (WASM) for inference and the compiled `espeak-ng` for phonemization.

```sh
cd wasm_piper

# CMake auto-installs onnxruntime-web into external/node_modules/ on first build.
# Synthesize "The quick brown fox jumps over the lazy dog"
node synthesize.js \
  ../external/piper_voices/en_US-lessac-medium.onnx \
  ../external/piper_voices/en_US-lessac-medium.onnx.json \
  "The quick brown fox jumps over the lazy dog" \
  output.wav
```

**Usage:** `node synthesize.js <model.onnx> <model.onnx.json> <text> [output.wav]`

The model and config paths are required. `output.wav` defaults to `synthesize.wav` if omitted.

The espeak-ng binary and data path are resolved automatically. Override with environment variables:

```sh
ESPEAK_BIN=/path/to/espeak-ng ESPEAK_DATA=/path/to/espeak-ng-data \
  node synthesize.js model.onnx model.onnx.json "text" output.wav
```

The script also exports a `synthesize()` function for programmatic use:

```js
const { synthesize } = require('./synthesize');
await synthesize('../external/en_US-lessac-medium.onnx', '../external/en_US-lessac-medium.onnx.json', 'hello world', 'output.wav');
```

## Understanding Test Modes

| Mode | ONNX | Use Case | Speed |
|---|---|---|---|
| **Mock** | `mock_onnxruntime.cpp` | Build pipeline verification, deterministic output | Fast (no actual inference) |
| **Real** | `onnxruntime-web` | Production synthesis, audio quality verification | Slow (actual inference) |

Mock test source files are in `wasm_piper/tests_old/`. The current test target (`piper_wasm_mock_integration_test` in `wasm_piper/tests/CMakeLists.txt`) uses `wasm_integration_main.cpp` with mock ONNX.

## ort_shim Build Integration

The compiled `piper_wasm.js` has `ort_shim.js` merged into it at build time (via a CMake post-build step). This means `ortShimModule` is globally available within the module scope, and `piperWasm` remains the correct `module.exports`. You never need to import ort_shim.js separately.

## Directory Layout

```
wasm_piper/
  CMakeLists.txt              # Main CMake config (emscripten + WASM targets)
  build.py                    # Build script: downloads tools, ort_shim, builds WASM, downloads voices
  synthesize.js               # Unified synthesis script (onnxruntime-web + espeak-ng) -> WAV
  shim/
    src/
      onnxruntime_cxx_api.h   # ONNX Runtime C++ API shim (all header-only, replaces real ONNX header)
      ort_shim.js             # JS bridge: ort_shim_* EM_JS → onnxruntime-web
      ort_shim_external.cmake # CMake: provides onnxruntime_iface_lib INTERFACE target
  build/                      # CMake build output (created by cmake -B)
  tests/
    CMakeLists.txt            # Native test binary for WASM parity comparison
    test_wasm_c_api.js        # WASM C API boundary test (symbol exports, struct layout)
    test_wasm_integration.js  # JS test runner (mock ONNX mode)
    wasm_integration_main.cpp # C++ entry point (native + WASM)
  external/                   # Node.js, Emscripten, voices (real path resolved at build time)
    node_modules/             # onnxruntime-web (auto-installed on first build)
    emsdk-*/                  # Emscripten SDK (downloaded by build.py)
    node-v*/                  # Node.js binary distribution (downloaded by build.py)
    piper_voices/             # Voice models downloaded by build.py
      en_US-lessac-medium.onnx       # Default voice model
      en_US-lessac-medium.onnx.json  # Default voice config
```
