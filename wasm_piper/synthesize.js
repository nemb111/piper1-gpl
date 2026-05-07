#!/usr/bin/env node
/**
 * WASM-side piper audio synthesis via the piper C API.
 *
 * Calls the compiled piper_wasm module (libpiper + espeak-ng + ONNX Runtime WASM)
 * through its C API: piper_create -> piper_synthesize_start -> piper_synthesize_next.
 *
 * ONNX Runtime WASM initialization is handled internally by the shim layer.
 * synthesize.js only uses the piper C API — all ort_shim orchestration is opaque.
 *
 * Usage: node synthesize.js <model.onnx> <model.onnx.json> <text> [output.wav]
 *
 * Environment variables:
 *   ESPEAK_DATA   - Path to espeak-ng data directory within WASM FS
 *                   (default: /espeak-ng-data from preloaded tests/data)
 *   MODEL_PATH    - Override model path in WASM FS
 *                   (default: /test_voice.onnx from preloaded tests/data)
 *   CONFIG_PATH   - Override config path in WASM FS
 *                   (default: /test_voice.onnx.json from preloaded tests/data)
 */

const { readFileSync, writeFileSync, mkdtempSync, rmSync } = require('fs');
const path = require('path');
const os = require('os');

// ── Paths ──────────────────────────────────────────────────────

const __DIR__ = __dirname;                          // wasm_piper/
const BASE_DIR = path.resolve(__DIR__);
const WASM_JS = path.join(BASE_DIR, 'build', 'piper_wasm.js');
const WASM_WASM = path.join(BASE_DIR, 'build', 'piper_wasm.wasm');

// WASM FS paths (files preloaded via --preload-file tests/data@/)
const DEFAULT_MODEL_WASM   = '/en_US-amy-low.onnx';
const DEFAULT_CONFIG_WASM  = '/en_US-amy-low.onnx.json';
const DEFAULT_ESPEAK       = '/espeak-ng-data';

// Temp directory for host-accessible copies of preloaded WASM FS files.
let TEMP_DIR;
function copyModelToHost(mod) {
    const modelData = mod.FS.readFile(DEFAULT_MODEL_WASM);
    const tmpDir = mkdtempSync(os.tmpdir() + '/piper-wasm-');
    TEMP_DIR = tmpDir;
    const hostPath = path.join(tmpDir, path.basename(DEFAULT_MODEL_WASM));
    writeFileSync(hostPath, modelData);
    return hostPath;
}

// ── piper_audio_chunk struct field offsets (32-bit WASM) ──

const CHUNK_SAMPLES         = 0;  // const float* (4 bytes)
const CHUNK_NUM_SAMPLES     = 4;  // size_t (4 bytes)
const CHUNK_SAMPLE_RATE     = 8;  // int (4 bytes)
const CHUNK_IS_LAST         = 12; // bool (1 byte + 3 padding)
const CHUNK_PHONEMES        = 16; // const char32_t* (4 bytes)
const CHUNK_NUM_PHONEMES    = 20; // size_t (4 bytes)
const CHUNK_PHONEME_IDS     = 24; // const int* (4 bytes)
const CHUNK_NUM_PHONEME_IDS = 28; // size_t (4 bytes)
const CHUNK_ALIGNMENTS      = 32; // const int* (4 bytes)
const CHUNK_NUM_ALIGNMENTS  = 36; // size_t (4 bytes)
const CHUNK_SIZE            = 40;

// ── Options offsets (piper_synthesize_options = 16 bytes) ──

const OPT_SPEAKER_ID  = 0;  // int32
const OPT_LENGTH_SCALE = 4; // float32
const OPT_NOISE_SCALE  = 8; // float32
const OPT_NOISE_W      = 12;// float32

// ── WASM helpers ─────────────────────────────────────────────────────

/** Allocate a null-terminated C string in WASM memory. */
function allocStr(Module, str) {
    const ptr = Module._malloc(str.length + 1);
    Module.stringToUTF8(str, ptr, str.length + 1);
    return ptr;
}

/** Copy a file from host fs into WASM FS (always overwrites, creating dirs as needed). */
function copyToWasm(mod, hostPath, wasmPath) {
    const dir = wasmPath.split('/').slice(0, -1).join('/');
    if (dir && !mod.FS.analyzePath(dir).exists) {
        mod.FS.mkdirTree(dir);
    }
    const data = readFileSync(hostPath);
    mod.FS.writeFile(wasmPath, data);
}

// ── WAV writer (int16 PCM) ──────────────────────────────────────────

function writeWav(filename, samples, sampleRate) {
    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * (bitsPerSample / 8);
    const blockAlign = numChannels * (bitsPerSample / 8);
    const dataSize = samples.length * (bitsPerSample / 8);
    const fileSize = 44 + dataSize;

    const buf = Buffer.alloc(fileSize);
    let off = 0;

    buf.write('RIFF', off); off += 4;
    buf.writeUInt32LE(fileSize - 8, off); off += 4;
    buf.write('WAVE', off); off += 4;

    buf.write('fmt ', off); off += 4;
    buf.writeUInt32LE(16, off); off += 4;
    buf.writeUInt16LE(1, off); off += 2; // PCM
    buf.writeUInt16LE(numChannels, off); off += 2;
    buf.writeUInt32LE(sampleRate, off); off += 4;
    buf.writeUInt32LE(byteRate, off); off += 4;
    buf.writeUInt16LE(blockAlign, off); off += 2;
    buf.writeUInt16LE(bitsPerSample, off); off += 2;

    buf.write('data', off); off += 4;
    buf.writeUInt32LE(dataSize, off); off += 4;

    for (const s of samples) {
        buf.writeInt16LE(
            Math.max(-32768, Math.min(32767, Math.round(s * 32767))),
            off
        );
        off += 2;
    }

    writeFileSync(filename, buf);
}

// ── Main synthesis ──

async function synthesize(modelPath, configPath, text, outputPath) {
    const wasmBinary = readFileSync(WASM_WASM);
    const Module = require(WASM_JS);

    const mod = await Module({
        wasmBinary,
        locateFile: (name) => path.join(path.dirname(WASM_WASM), name),
    });

    // ortShimModule is globally available from merged piper_wasm.js.
    // Session initialization is handled internally by the shim layer
    // on first piper_synthesize_next call (lazy init via ort_shim_run).

    const chunkPtr = mod._malloc(CHUNK_SIZE);

    try {
        // Resolve paths:
        // - Model: must be on host fs (ort.InferenceSession.create uses Node fs)
        // - Config: must use WASM FS path (piper.cpp's std::ifstream uses WASM FS)
        let model, configHost, configWasm, espeak;
        if (modelPath) {
            model = modelPath;
            configHost = configPath || (modelPath.endsWith('.onnx')
                ? modelPath.replace(/\.onnx$/, '.json')
                : modelPath + '.json');
            configWasm = '/piper-user-config.json';  // Dedicated temp path for user configs
            espeak = process.env.ESPEAK_DATA || DEFAULT_ESPEAK;
            // Copy config into WASM FS for piper.cpp's std::ifstream
            copyToWasm(mod, configHost, configWasm);
        } else {
            model = copyModelToHost(mod);
            configWasm = DEFAULT_CONFIG_WASM;  // Preloaded WASM FS path
            espeak = DEFAULT_ESPEAK;
        }

        // Allocate string pointers
        const modelPtr = allocStr(mod, model);
        const configPtr = allocStr(mod, configWasm);
        const dataPtr = allocStr(mod, espeak);

        // Create synthesizer (piper + espeak + Ort::Session)
        const synth = mod.ccall('piper_create', 'number',
            ['i8', 'i8', 'i8'],
            [modelPtr, configPtr, dataPtr]);

        mod._free(modelPtr);
        mod._free(configPtr);
        mod._free(dataPtr);

        if (!synth) {
            throw new Error('piper_create returned NULL');
        }

        // Start synthesis (NULL = use default options from voice config)
        const textPtr = allocStr(mod, text);
        const rc = mod.ccall('piper_synthesize_start', 'number',
            ['number', 'i8', 'number'],
            [synth, textPtr, 0 /* NULL - use defaults */]);
        mod._free(textPtr);

        if (rc !== 0) {
            throw new Error(`piper_synthesize_start returned ${rc}`);
        }

        // Collect audio chunks via piper_synthesize_next C API call
        const synthesizeNext = mod.cwrap('piper_synthesize_next', 'number',
            ['number', 'number'], { async: true });

        // Read sample rate from config JSON (WASM FS)
        const cfg = JSON.parse(mod.FS.readFile(configWasm, {encoding: 'utf8'}));
        let sampleRate = cfg.audio?.sample_rate || 22050;

        const allSamples = [];
        let chunkCount = 0;

        // 32-bit WASM: pointers and size_t are 4 bytes.
        const readU32 = (ptr) => mod.getValue(ptr, 'i32');

        while (true) {
            const rc = await synthesizeNext(synth, chunkPtr);
            if (rc === 1) break; // PIPER_DONE

            const numSamples = readU32(chunkPtr + CHUNK_NUM_SAMPLES);
            const samplesPtr = readU32(chunkPtr + CHUNK_SAMPLES);

            if (numSamples > 0 && samplesPtr > 0) {
                const samples = mod.HEAPU8.subarray(samplesPtr, samplesPtr + numSamples * 4);
                const sampleData = new Float32Array(samples.buffer, samples.byteOffset, numSamples);
                allSamples.push(...sampleData);
            }
        }

        // Normalize audio (-3dB peak)
        let peak = 0;
        for (let i = 0; i < allSamples.length; i++) {
            const a = Math.abs(allSamples[i]);
            if (a > peak) peak = a;
        }
        if (peak > 0) {
            const gain = 0.707 / peak;
            for (let i = 0; i < allSamples.length; i++) {
                allSamples[i] *= gain;
            }
        }

        // Write WAV
        writeWav(outputPath, allSamples, sampleRate);

        console.log(`Synthesized ${allSamples.length} samples (${(allSamples.length / sampleRate).toFixed(1)}s) -> ${outputPath}`);

        // Cleanup
        mod.ccall('piper_free', null, ['number'], [synth]);
    } finally {
        mod._free(chunkPtr);
        // Clean up temp files
        if (TEMP_DIR) {
            try { rmSync(TEMP_DIR, { recursive: true, force: true }); } catch {}
        }
    }
}

// ── CLI ──

if (require.main === module) {
    const modelPath = process.argv[2];
    const configPath = process.argv[3];
    const text = process.argv[4] || 'hello world';
    const outputPath = process.argv[5] || 'synthesize.wav';

    synthesize(modelPath, configPath, text, outputPath).catch(e => {
        console.error('Error:', e.message);
        process.exit(1);
    });
}

module.exports = { synthesize };
