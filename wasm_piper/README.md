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
cmake -B wasm_piper/build -S wasm_piper
cmake --build wasm_piper/build --target piper_wasm_compile_test_wasm --target piper_wasm_mock_integration_test
```

This builds:
- `piper_wasm_compile_test_wasm.wasm` -- compilation smoke test
- `piper_wasm_mock_integration_test.js/.wasm` -- mock ONNX integration test

### 2. Run Tests

```sh
# Mock mode: deterministic output (both sides use mock ONNX)
cd wasm_piper/tests && USE_REAL_ONNX=0 node test_wasm_integration.js

# Real mode: actual voice model (requires pre-built WASM ONNX Runtime)
# cd wasm_piper/tests && USE_REAL_ONNX=1 node test_wasm_integration.js
```

## Generating WAV Output Files

### Using the native Python script (real ONNX Runtime, CPU)

This approach runs on the host machine with the real ONNX Runtime. It produces 16-bit PCM WAV files.

```sh
cd wasm_piper/tests

# Synthesize "The quick brown fox jumps over the lazy dog"
python3 synthesize.py \
  data/en_US-amy-low.onnx \
  data/en_US-amy-low.onnx.json \
  "The quick brown fox jumps over the lazy dog" \
  output_fox.wav
```

**Requirements:** `onnxruntime`, `numpy`

**Defaults:** If no arguments are given, `synthesize.py` uses `model.onnx`, `model.onnx.json`, text `"hello world"`, and output `native_output.wav`.

The espeak-ng binary and data path are resolved automatically (via the repo build directory). Override with environment variables:

```sh
ESPEAK_BIN=/path/to/espeak-ng ESPEAK_DATA=/path/to/espeak-ng-data \
  python3 synthesize.py model.onnx model.onnx.json "text" output.wav
```

### Using the Node.js script (onnxruntime-web, WASM in Node)

This approach runs inference in Node.js using `onnxruntime-web`. It also produces 16-bit PCM WAV files.

```sh
cd wasm_piper/tests

# Install the Node.js dependency (once)
npm install onnxruntime-web

# Synthesize the same text
node synthesize_node.js \
  data/en_US-amy-low.onnx \
  data/en_US-amy-low.onnx.json \
  "The quick brown fox jumps over the lazy dog" \
  output_fox.wav
```

**Defaults:** Same argument pattern as `synthesize.py`. Unset args default to `model.onnx`, `model.onnx.json`, `"hello world"`, and `wasm_output.wav`.

### Using the WASM integration test binary (built WASM, any ONNX mode)

The `piper_wasm_mock_integration_test` target can also write WAV files directly. After building, use Node.js to load the WASM module and call `run_wav_write`:

```js
// In a Node.js script after loading the WASM Module:
const wasmModule = await Module({ wasmBinary: wasmBinary });
const wavPtr = wasmModule._malloc(256);
wasmModule.stringToUTF8("output_fox.wav", wavPtr, 256);
const rc = wasmModule._run_wav_write(
  "/test-data/en_US-amy-low.onnx.json",
  "/test-data/en_US-amy-low.onnx",
  "/espeak-ng-data",
  "output_fox.wav"
);
wasmModule._free(wavPtr);
```

## Understanding Test Modes

| Mode | ONNX | Use Case | Speed |
|---|---|---|---|
| **Mock** | `mock_onnxruntime.cpp` | Build pipeline verification, deterministic output | Fast (no actual inference) |
| **Real** | Real ONNX Runtime Web | Audio quality verification, cross-platform audio parity | Slow (actual neural inference) |

## Real ONNX WASM Build

For real inference in WASM, build ONNX Runtime Web as a static library first (this takes ~30-60 minutes and downloads ~2GB):

```sh
cmake -P cmake/build_ort_web.cmake
```

Then rebuild the WASM target without `MOCK_BUILD` to use the real ONNX:

```sh
cmake -B wasm_piper/build_real -S wasm_piper
cmake --build wasm_piper/build_real --target piper_wasm_real_integration_test
```

## Directory Layout

```
wasm_piper/
  CMakeLists.txt              # Main CMake config (emscripten + WASM targets)
  wasm_main.cpp               # Entry point for compilation smoke test
  build/                      # CMake build output (created by cmake -B)
  tests/
    CMakeLists.txt            # Native test binary for WASM parity comparison
    synthesize.py             # Native Python synthesis (real ONNX) -> WAV
    synthesize_node.js        # Node.js synthesis (onnxruntime-web) -> WAV
    test_wasm_integration.js  # JS test runner (mock + real modes)
    wasm_audio_test.js        # Audio similarity comparison (openl3 optional)
    wasm_integration_main.cpp # C++ entry point (native + WASM)
    data/
      test_voice.onnx         # Mock voice model (empty file, mock ONNX)
      test_voice.onnx.json    # Mock config (all phonemes mapped)
      en_US-amy-low.onnx     # Real voice model (63 MB)
      en_US-amy-low.onnx.json # Real voice config
      espeak-ng-data/         # Pre-built espeak data files
```
