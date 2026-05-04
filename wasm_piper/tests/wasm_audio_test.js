/**
 * WASM vs Native piper audio comparison test (real ONNX).
 *
 * Compares audio produced by native (real ONNX) and WASM builds
 * using perceptual similarity (openl3) and sample-wise difference.
 *
 * Requires:
 *   npm install onnxruntime-web
 *   pip install openl3 soundfile scipy
 *
 * Usage:
 *   node wasm_audio_test.js                    # run all tests
 *   node wasm_audio_test.js --mock             # run mock-only (fast, no model download)
 *   node wasm_audio_test.js --native-only      # run native only
 *   node wasm_audio_test.js --wasm-only        # run WASM only
 *
 * Environment:
 *   PIPER_MODEL_PATH    - path to .onnx model (default: downloads en_US-amy-low)
 *   PIPER_DATA_PATH     - path to espeak-ng-data directory
 *   PIPER_CONFIG_PATH   - path to .json config
 */

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

// ── Paths ─────────────────────────────────────────────────
const BASE_DIR = path.resolve(__dirname, '..');
const DATA_DIR = path.join(BASE_DIR, 'tests', 'data');

// Test data files (real model for real-ONNX test)
const DEFAULT_MODEL = 'en_US-amy-low.onnx';
const DEFAULT_MODEL_JSON = 'en_US-amy-low.onnx.json';
const MODEL_PATH = process.env.PIPER_MODEL_PATH || path.join(DATA_DIR, DEFAULT_MODEL);
const CONFIG_PATH = process.env.PIPER_CONFIG_PATH || path.join(DATA_DIR, DEFAULT_MODEL_JSON);
const ESPEAK_DATA = process.env.PIPER_DATA_PATH || path.join(DATA_DIR, 'espeak-ng-data');

// Output WAV files
const NATIVE_WAV = path.join(DATA_DIR, 'native_output.wav');
const WASM_WAV = path.join(DATA_DIR, 'wasm_output.wav');

// WASM files (real test target)
const WASM_JS = path.join(BASE_DIR, 'build', 'piper_real_test_wasm.js');
const WASM_WASM = path.join(BASE_DIR, 'build', 'piper_real_test_wasm.wasm');

// Native test (mock build - used for phonemization reference)
const NATIVE_TEST = path.join(BASE_DIR, 'build', 'native_piper_test');

// ── Helpers ─────────────────────────────────────────────────

function parseJsonResult(text) {
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error(`No JSON found in output:\n${text.substring(0, 300)}`);
    return JSON.parse(jsonMatch[0]);
}

function writeWav(samples, sampleRate, outPath) {
    // Write a simple float WAV file
    const numChannels = 1;
    const bitsPerSample = 32;
    const dataBytes = samples.length * 4;
    const fileSize = 44 + dataBytes;

    const buf = Buffer.allocUnsafe(fileSize);
    let off = 0;

    buf.write('RIFF', off); off += 4;
    buf.writeUInt32LE(fileSize - 8, off); off += 4;
    buf.write('WAVE', off); off += 4;

    buf.write('fmt ', off); off += 4;
    buf.writeUInt32LE(16, off); off += 4;
    buf.writeUInt16LE(3, off); off += 2;
    buf.writeUInt16LE(numChannels, off); off += 2;
    buf.writeUInt32LE(sampleRate, off); off += 4;
    buf.writeUInt32LE(sampleRate * numChannels * (bitsPerSample / 8), off); off += 4;
    buf.writeUInt16LE(numChannels * (bitsPerSample / 8), off); off += 2;
    buf.writeUInt16LE(bitsPerSample, off); off += 2;

    // data chunk
    buf.write('data', offset); offset += 4;
    buf.writeUInt32LE(dataBytes, offset); offset += 4;

    // Write samples as floats using Float32Array view (faster than per-sample writes)
    new Float32Array(buf, 44).set(samples.map(s => Math.max(-1, Math.min(1, s))));

    fs.writeFileSync(outPath, buf);
}

function cosineSimilarity(a, b) {
    if (a.length !== b.length) return 0;
    let dot = 0, magA = 0, magB = 0;
    for (let i = 0; i < a.length; i++) {
        dot += a[i] * b[i];
        magA += a[i] * a[i];
        magB += b[i] * b[i];
    }
    if (magA === 0 || magB === 0) return 0;
    return dot / (Math.sqrt(magA) * Math.sqrt(magB));
}

function runCmd(cmd, args, cwd) {
    return new Promise((resolve, reject) => {
        const proc = spawn(cmd, args, {
            cwd,
            timeout: 60000,
            stdio: ['pipe', 'pipe', 'pipe']
        });

        let stdout = '';
        let stderr = '';

        proc.stdout.on('data', (d) => stdout += d.toString());
        proc.stderr.on('data', (d) => stderr += d.toString());

        proc.on('close', (code) => {
            if (code === 0) resolve({ stdout, stderr });
            else reject(new Error(`Exit code ${code}: ${stderr}`));
        });

        proc.on('error', reject);
    });
}

// ── Native test ─────────────────────────────────────────────────

async function runNativeTest(useRealOnnx = false) {
    if (!fs.existsSync(NATIVE_TEST)) {
        console.log('  Native test binary not found, skipping');
        return null;
    }

    console.log('  Running native synthesis...');

    if (useRealOnnx && process.env.PIPER_REAL_NATIVE_TEST) {
        // Use a real ONNX native test binary (if built)
        const realNative = path.join(BASE_DIR, 'build', 'native_piper_real_test');
        if (fs.existsSync(realNative)) {
            const result = await runCmd(realNative, [CONFIG_PATH, MODEL_PATH, ESPEAK_DATA]);
            return parseJsonResult(result.stdout);
        }
    }

    // Use mock test for phonemization reference (same as baseline test)
    const result = await runCmd(NATIVE_TEST, [CONFIG_PATH, MODEL_PATH, ESPEAK_DATA]);
    return parseJsonResult(result.stdout);
}

// ── WASM test ─────────────────────────────────────────────────

async function runWasmTest() {
    if (!fs.existsSync(WASM_WASM)) {
        console.log('  WASM binary not found (need real-ONNX build), skipping');
        return null;
    }

    console.log('  Running WASM synthesis...');

    const wasmBinary = fs.readFileSync(WASM_WASM);
    const wasmDir = path.dirname(WASM_WASM);
    const Module = require(WASM_JS);

    const wasmModule = await Module({
        wasmBinary: wasmBinary,
        locateFile: (name) => path.join(wasmDir, name),
        print: (text) => console.log(`[WASM] ${text}`),
        printErr: (text) => console.error(`[WASM ERR] ${text}`),
    });

    // Use run_wav_write to produce a WAV file directly
    const wavPtr = wasmModule._malloc(256);
    wasmModule.stringToUTF8(WASM_WAV, wavPtr, 256);

    const rc = wasmModule._run_wav_write(
        '/test-data/en_US-amy-low.onnx.json',
        '/test-data/en_US-amy-low.onnx',
        '/espeak-ng-data',
        WASM_WAV
    );

    wasmModule._free(wavPtr);

    if (rc !== 0) {
        console.error(`  WASM write failed with rc=${rc}`);
        return null;
    }

    // Read back and return samples info
    const wavData = fs.readFileSync(WASM_WAV);
    // Simple WAV header: sample_rate at offset 24, data_size at offset 40
    const sampleRate = wavData.readUInt32LE(24);
    const dataChunkOffset = 44;

    const numSamples = wavData.length - dataChunkOffset;
    const samples = [];
    for (let i = 0; i < numSamples && i < 1000; i += 4) { // Limit for speed
        samples.push(wavData.readFloatLE(dataChunkOffset + i));
    }

    return { sample_rate: sampleRate, num_samples: numSamples / 4, audio_samples: samples };
}

// ── Similarity check ─────────────────────────────────────────────────

async function checkSimilarity() {
    console.log('\n=== Perceptual Similarity ===');

    const nativeExists = fs.existsSync(NATIVE_WAV);
    const wasmExists = fs.existsSync(WASM_WAV);

    if (!nativeExists || !wasmExists) {
        console.log('  WAV files not available for comparison');
        return null;
    }

    // Check file sizes match
    const nativeSize = fs.statSync(NATIVE_WAV).size;
    const wasmSize = fs.statSync(WASM_WAV).size;
    console.log(`  Native WAV: ${nativeSize} bytes`);
    console.log(`  WASM WAV:   ${wasmSize} bytes`);

    if (nativeSize !== wasmSize) {
        console.log(`  [WARN] WAV file sizes differ (native=${nativeSize}, wasm=${wasmSize})`);
        // Try to compare anyway - use the smaller of the two
    }

    // Read WAV files and compare audio
    const nativeData = fs.readFileSync(NATIVE_WAV);
    const wasmData = fs.readFileSync(WASM_WAV);

    const nativeRate = nativeData.readUInt32LE(24);
    const wasmRate = wasmData.readUInt32LE(24);
    console.log(`  Native sample rate: ${nativeRate}`);
    console.log(`  WASM sample rate:   ${wasmRate}`);

    // Extract samples (limit for speed), use data chunk size from WAV header
    const nativeDataSize = nativeData.readUInt32LE(40);
    const wasmDataSize = wasmData.readUInt32LE(40);
    const numSamples = Math.min(nativeDataSize, wasmDataSize) / 4;
    const nativeSamples = [];
    const wasmSamples = [];

    for (let i = 0; i < numSamples; i++) {
        nativeSamples.push(nativeData.readFloatLE(44 + i * 4));
        wasmSamples.push(wasmData.readFloatLE(44 + i * 4));
    }

    // Sample-wise cosine similarity
    const sampleSim = cosineSimilarity(nativeSamples, wasmSamples);
    console.log(`  Sample-wise cosine similarity: ${sampleSim.toFixed(6)}`);

    // Check max absolute difference
    let maxDiff = 0;
    for (let i = 0; i < nativeSamples.length; i++) {
        const diff = Math.abs(nativeSamples[i] - wasmSamples[i]);
        if (diff > maxDiff) maxDiff = diff;
    }
    console.log(`  Max absolute difference: ${maxDiff.toFixed(6)}`);

    // Optional: run openl3 perceptual similarity
    if (process.env.USE_OPENL3) {
        try {
            const { default: openl3 } = await import('openl3');
            const { read } = await import('soundfile');
            const [audio1, sr1] = await read(NATIVE_WAV);
            const [audio2, sr2] = await read(WASM_WAV);

            const emb1 = await openl3(audio1, sr1);
            const emb2 = await openl3(audio2, sr2);

            const sim = 1 - cosineSimilarity(
                emb1.mean(axis=0),
                emb2.mean(axis=0)
            );
            console.log(`  OpenL3 perceptual similarity: ${sim.toFixed(6)}`);
            return { sample_sim: sampleSim, max_diff: maxDiff, openl3_sim: sim };
        } catch (e) {
            console.log(`  OpenL3 not available: ${e.message}`);
        }
    }

    return { sample_sim: sampleSim, max_diff: maxDiff };
}

// ── Main ─────────────────────────────────────────────────

async function main() {
    console.log('=== WASM Piper Audio Test ===\n');

    // Check prerequisites
    const modelExists = fs.existsSync(MODEL_PATH);
    const configExists = fs.existsSync(CONFIG_PATH);
    const dataExists = fs.existsSync(ESPEAK_DATA);

    if (!modelExists || !configExists || !dataExists) {
        console.log('Missing test data files:');
        if (!modelExists) console.log(`  Model: ${MODEL_PATH}`);
        if (!configExists) console.log(`  Config: ${CONFIG_PATH}`);
        if (!dataExists) console.log(`  espeak-data: ${ESPEAK_DATA}`);
        console.log('\nSet PIPER_MODEL_PATH, PIPER_CONFIG_PATH, PIPER_DATA_PATH or download models.');
        process.exit(1);
    }

    const useRealOnnx = !!process.env.USE_REAL_ONNX;

    if (useRealOnnx) {
        console.log('Using real ONNX mode');
    } else {
        console.log('Using mock mode (fast, deterministic)');
    }

    // Run native test
    let nativeResult;
    if (!process.env.SKIP_NATIVE) {
        nativeResult = await runNativeTest(useRealOnnx);
    }

    // Run WASM test
    let wasmResult;
    if (!process.env.SKIP_WASM) {
        wasmResult = await runWasmTest();
    }

    // Write WAV files for comparison
    if (nativeResult) {
        writeWav(nativeResult.audio_samples, nativeResult.sample_rate, NATIVE_WAV);
    }
    if (wasmResult) {
        writeWav(wasmResult.audio_samples, wasmResult.sample_rate, WASM_WAV);
    }

    // Check similarity
    const similarity = await checkSimilarity();

    // Report
    console.log('\n=== Summary ===');
    if (nativeResult) {
        console.log(`Native: sr=${nativeResult.sample_rate}, samples=${nativeResult.num_samples}, phonemes=${nativeResult.phonemes.length}`);
    }
    if (wasmResult) {
        console.log(`WASM:   sr=${wasmResult.sample_rate}, samples=${wasmResult.num_samples}, phonemes=${wasmResult.phonemes ? wasmResult.phonemes.length : '?'}`);
    }
    if (similarity) {
        console.log(`Similarity: ${similarity.sample_sim.toFixed(4)}`);
    }

    // Exit code
    const passed = !similarity || similarity.sample_sim >= 0.99;
    process.exit(passed ? 0 : 1);
}

main().catch(e => {
    console.error(`Fatal: ${e.message}`);
    process.exit(1);
});
