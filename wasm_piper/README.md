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
cmake -B wasm_piper/build -S wasm_piper  # auto-runs npm install if onnxruntime-web not present
cmake --build wasm_piper/build --target piper_wasm_mock_integration_test
```

This builds:
- `piper_wasm_mock_integration_test.js/.wasm` -- mock ONNX integration test

### 2. Generate Audio from WASM Build

The compiled WASM module (`piper_wasm`) can synthesize speech using the C++ path for phonemization (via the `piper_create` / `piper_synthesize_start` APIs) and onnxruntime-web for inference.

**Step 1 — Build:**
```sh
cmake -B wasm_piper/build -S wasm_piper
cmake --build wasm_piper/build --target piper_wasm  # auto-runs npm install if onnxruntime-web not present
```
This produces `wasm_piper/build/piper_wasm.{js,wasm,data}`.

**Step 2 — Synthesize:**
```sh
cd wasm_piper
node synthesize.js tests/data/en_US-amy-low.onnx tests/data/en_US-amy-low.onnx.json "Hello from the WASM build" /tmp/output.wav
```

## Synthesizing Audio

The unified `synthesize.js` script produces 16-bit PCM WAV files using `onnxruntime-web` (WASM) for inference and the compiled `espeak-ng` for phonemization.

```sh
cd wasm_piper

# CMake auto-installs onnxruntime-web into external/node_modules/ on first build.
# Synthesize "The quick brown fox jumps over the lazy dog"
node synthesize.js \
  tests/data/en_US-amy-low.onnx \
  tests/data/en_US-amy-low.onnx.json \
  "The quick brown fox jumps over the lazy dog" \
  output_fox.wav
```

**Defaults:** Unset arguments default to `model.onnx`, `model.onnx.json`, `"hello world"`, and `synthesize.wav`.

The espeak-ng binary and data path are resolved automatically. Override with environment variables:

```sh
ESPEAK_BIN=/path/to/espeak-ng ESPEAK_DATA=/path/to/espeak-ng-data \
  node synthesize.js model.onnx model.onnx.json "text" output.wav
```

The script also exports a `synthesize()` function for programmatic use:

```js
const { synthesize } = require('./synthesize');
await synthesize('tests/data/en_US-amy-low.onnx', 'tests/data/en_US-amy-low.onnx.json', 'hello world', 'output.wav');
```

## Understanding Test Modes

| Mode | ONNX | Use Case | Speed |
|---|---|---|---|
| **Mock** | `mock_onnxruntime.cpp` | Build pipeline verification, deterministic output | Fast (no actual inference) |

## Directory Layout

```
wasm_piper/
  CMakeLists.txt              # Main CMake config (emscripten + WASM targets)
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
    data/
      test_voice.onnx         # Mock voice model (empty file, mock ONNX)
      test_voice.onnx.json    # Mock config (all phonemes mapped)
      en_US-amy-low.onnx     # Real voice model (63 MB)
      en_US-amy-low.onnx.json # Real voice config
      espeak-ng-data/         # Pre-built espeak data files
```
