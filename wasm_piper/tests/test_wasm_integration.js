/**
 * WASM vs Native piper integration test.
 *
 * Two modes:
 * 1. MOCK mode (default): Compares native vs WASM with mock ONNX
 *    - Both builds share identical mock output → verifies build pipeline parity
 * 2. REAL mode (USE_REAL_ONNX=1): Compares native vs WASM with real ONNX
 *    - Uses real voice model → verifies identical inference output
 *
 * In REAL mode, also writes WAV files and computes sample-wise similarity.
 */

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

// ── Paths ─────────────────────────────────────────────────────
const BASE_DIR = path.resolve(__dirname, '..');
const DATA_DIR = path.join(BASE_DIR, 'tests', 'data');
const ESPEAK_DATA = path.join(DATA_DIR, 'espeak-ng-data');

// Mock test data (baseline compatibility)
const MOCK_MODEL = path.join(DATA_DIR, 'test_voice.onnx');
const MOCK_CONFIG = path.join(DATA_DIR, 'test_voice.onnx.json');

// Real test data (actual voice model)
const REAL_MODEL = path.join(DATA_DIR, 'en_US-amy-low.onnx');
const REAL_CONFIG = path.join(DATA_DIR, 'en_US-amy-low.onnx.json');

// Determine which model to use
const useRealOnnx = process.env.USE_REAL_ONNX === '1';
const MODEL_PATH = useRealOnnx ? REAL_MODEL : MOCK_MODEL;
const CONFIG_PATH = useRealOnnx ? REAL_CONFIG : MOCK_CONFIG;
const MODE_NAME = useRealOnnx ? 'REAL' : 'MOCK';

// WASM files (target name depends on mode)
const WASM_TARGET = useRealOnnx
    ? 'piper_wasm_real_integration_test'
    : 'piper_wasm_mock_integration_test';
const WASM_JS = path.join(BASE_DIR, 'build', `${WASM_TARGET}.js`);
const WASM_WASM = path.join(BASE_DIR, 'build', `${WASM_TARGET}.wasm`);

// Native test executable
const NATIVE_TEST = path.join(BASE_DIR, 'build', 'native_piper_test');

// WAV output files for similarity comparison (real mode only)
const NATIVE_WAV = useRealOnnx ? path.join(DATA_DIR, 'native_output.wav') : null;
const WASM_WAV = useRealOnnx ? path.join(DATA_DIR, 'wasm_output.wav') : null;

// ── Helpers ────────────────────────────────────────────────────────

function parseJsonResult(text) {
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error(`No JSON found in output:\n${text.substring(0, 300)}`);
    return JSON.parse(jsonMatch[0]);
}

function writeWav(samples, sampleRate, outPath) {
    if (!outPath) return;
    const numChannels = 1;
    const bitsPerSample = 32;
    const dataBytes = samples.length * 4;
    const fileSize = 44 + dataBytes;

    const buf = Buffer.allocUnsafe(fileSize);
    let offset = 0;

    buf.write('RIFF', offset); offset += 4;
    buf.writeUInt32LE(fileSize - 8, offset); offset += 4;
    buf.write('WAVE', offset); offset += 4;

    buf.write('fmt ', offset); offset += 4;
    buf.writeUInt32LE(16, offset); offset += 4;
    buf.writeUInt16LE(3, offset); offset += 2;
    buf.writeUInt16LE(numChannels, offset); offset += 2;
    buf.writeUInt32LE(sampleRate, offset); offset += 4;
    buf.writeUInt32LE(sampleRate * numChannels * (bitsPerSample / 8), offset); offset += 4;
    buf.writeUInt16LE(numChannels * (bitsPerSample / 8), offset); offset += 2;
    buf.writeUInt16LE(bitsPerSample, offset); offset += 2;

    buf.write('data', offset); offset += 4;
    buf.writeUInt32LE(dataBytes, offset); offset += 4;

    for (const s of samples) {
        buf.writeFloatLE(Math.max(-1, Math.min(1, s)), offset);
        offset += 4;
    }

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

function runCmd(cmd, args, timeout = 30000) {
    return new Promise((resolve, reject) => {
        const proc = spawn(cmd, args, { timeout, cwd: BASE_DIR });

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

// ── Compare results ─────────────────────────────────────────────────

function compareResults(name, native, wasm) {
    let passed = true;

    if (native.sample_rate !== wasm.sample_rate) {
        console.error(`  ${name}: sample_rate mismatch (native=${native.sample_rate}, wasm=${wasm.sample_rate})`);
        passed = false;
    }
    if (native.phonemes !== wasm.phonemes) {
        console.error(`  ${name}: phonemes mismatch (native=${JSON.stringify(native.phonemes)}, wasm=${JSON.stringify(wasm.phonemes)})`);
        passed = false;
    }
    if (native.num_samples !== wasm.num_samples) {
        console.error(`  ${name}: num_samples mismatch (native=${native.num_samples}, wasm=${wasm.num_samples})`);
        passed = false;
    }
    if (native.rc !== wasm.rc) {
        console.error(`  ${name}: rc mismatch (native=${native.rc}, wasm=${wasm.rc})`);
        passed = false;
    }
    if (native.audio_samples.length !== wasm.audio_samples.length) {
        console.error(`  ${name}: audio_samples array length mismatch (native=${native.audio_samples.length}, wasm=${wasm.audio_samples.length})`);
        passed = false;
    } else {
        const n = native.audio_samples;
        const w = wasm.audio_samples;
        let maxDiff = 0;
        for (let i = 0; i < n.length; i++) {
            const a = parseFloat(n[i]);
            const b = parseFloat(w[i]);
            const diff = Math.abs(a - b);
            if (diff > maxDiff) maxDiff = diff;
            if (diff > 0.0001) {
                console.error(`  ${name}: audio[${i}] mismatch (native=${a}, wasm=${b})`);
                passed = false;
                if (i > 5) break;
            }
        }
        if (passed) {
            console.log(`  ${name}: audio samples match (max diff=${maxDiff.toFixed(6)})`);
        }
    }

    return passed;
}

// ── WASM test ─────────────────────────────────────────────────

async function runWasmTest() {
    const wasmBinary = fs.readFileSync(WASM_WASM);
    const wasmDir = path.dirname(WASM_WASM);
    const Module = require(WASM_JS);

    const wasmModule = await Module({
        wasmBinary: wasmBinary,
        locateFile: (name) => path.join(wasmDir, name),
        print: (text) => console.log(`[WASM] ${text}`),
        printErr: (text) => console.error(`[WASM ERR] ${text}`),
    });

    const dataPtr = wasmModule._malloc(18);
    wasmModule.stringToUTF8('/espeak-ng-data', dataPtr, 18);
    const modelPtr = wasmModule._malloc(256);
    // Files are preloaded at specific paths in the WASM FS
    const modelFsPath = useRealOnnx
        ? '/test-data/en_US-amy-low.onnx'
        : '/test-data/test_voice.onnx';
    const configFsPath = useRealOnnx
        ? '/test-data/en_US-amy-low.onnx.json'
        : '/test-data/test_voice.onnx.json';
    wasmModule.stringToUTF8(modelFsPath, modelPtr, 256);
    const configPtr = wasmModule._malloc(256);
    wasmModule.stringToUTF8(configFsPath, configPtr, 256);

    const rc = wasmModule._run_integration_test(configPtr, modelPtr, dataPtr);

    const resultPtr = wasmModule._get_result_string();
    const resultText = wasmModule.UTF8ToString(resultPtr);
    const result = parseJsonResult(resultText);
    result._rc = rc;

    wasmModule._free(configPtr);
    wasmModule._free(modelPtr);
    wasmModule._free(dataPtr);
    wasmModule._free_result_string();

    console.log(`WASM: sr=${result.sample_rate}, samples=${result.num_samples}, phonemes_len=${result.phonemes.length}, rc=${result.rc}`);
    return result;
}

// ── Native test ─────────────────────────────────────────────────

async function runNativeTest() {
    return new Promise((resolve, reject) => {
        const proc = spawn(NATIVE_TEST, [
            CONFIG_PATH, MODEL_PATH, ESPEAK_DATA
        ], { timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'] });

        let stdout = '';
        let stderr = '';

        proc.stdout.on('data', (data) => stdout += data.toString());
        proc.stderr.on('data', (data) => stderr += data.toString());

        proc.on('close', (code) => {
            if (code !== 0) {
                reject(new Error(`Native exited code ${code}: ${stderr}`));
                return;
            }
            try {
                const result = parseJsonResult(stdout);
                console.log(`Native: sr=${result.sample_rate}, samples=${result.num_samples}, phonemes_len=${result.phonemes.length}, rc=${result.rc}`);
                resolve(result);
            } catch (e) {
                reject(new Error(`Parse failed: ${e.message}\n--- stderr: ${stderr}\n--- stdout: ${stdout}`));
            }
        });

        proc.on('error', reject);
    });
}

// ── WAV similarity (real mode only) ─────────────────────────────────────────────────

async function checkWavSimilarity(nativeResult, wasmResult) {
    if (!useRealOnnx || !NATIVE_WAV || !WASM_WAV) return;

    // Write WAV files
    if (nativeResult) writeWav(nativeResult.audio_samples, nativeResult.sample_rate, NATIVE_WAV);
    if (wasmResult) writeWav(wasmResult.audio_samples, wasmResult.sample_rate, WASM_WAV);

    if (!fs.existsSync(NATIVE_WAV) || !fs.existsSync(WASM_WAV)) return;

    console.log('\n=== Audio Similarity (REAL MODE) ===');

    const nativeData = fs.readFileSync(NATIVE_WAV);
    const wasmData = fs.readFileSync(WASM_WAV);

    console.log(`  Native WAV: ${nativeData.length} bytes`);
    console.log(`  WASM WAV:   ${wasmData.length} bytes`);

    if (nativeData.length !== wasmData.length) {
        console.log('  [WARN] WAV file sizes differ');
        return;
    }

    // Extract samples (limit for speed)
    const numSamples = Math.min(nativeData.length - 44, wasmData.length - 44) / 4;
    const nativeSamples = [];
    const wasmSamples = [];

    for (let i = 0; i < numSamples; i++) {
        nativeSamples.push(nativeData.readFloatLE(44 + i * 4));
        wasmSamples.push(wasmData.readFloatLE(44 + i * 4));
    }

    // Sample-wise similarity
    const sim = cosineSimilarity(nativeSamples, wasmSamples);
    console.log(`  Sample-wise cosine similarity: ${sim.toFixed(6)}`);

    // Max absolute difference
    let maxDiff = 0;
    for (let i = 0; i < nativeSamples.length; i++) {
        const diff = Math.abs(nativeSamples[i] - wasmSamples[i]);
        if (diff > maxDiff) maxDiff = diff;
    }
    console.log(`  Max absolute difference: ${maxDiff.toFixed(6)}`);

    // Optional: openl3 perceptual similarity
    if (process.env.USE_OPENL3 && nativeSamples.length > 1000) {
        try {
            const soundfile = require('soundfile');
            const openl3 = require('openl3');
            const { cosine_similarity } = require('scipy');

            const [audio1] = await soundfile.read(NATIVE_WAV);
            const [audio2] = await soundfile.read(WASM_WAV);

            const [emb1] = await openl3.get_audio_embedding(audio1, nativeResult.sample_rate);
            const [emb2] = await openl3.get_audio_embedding(audio2, wasmResult.sample_rate);

            const sim = 1 - cosineSimilarity(
                Array.from(emb1.mean(axis=0)),
                Array.from(emb2.mean(axis=0))
            );
            console.log(`  OpenL3 perceptual similarity: ${sim.toFixed(6)}`);
        } catch (e) {
            console.log(`  OpenL3 not available: ${e.message}`);
        }
    }
}

// ── Main ─────────────────────────────────────────────────

async function main() {
    console.log(`=== WASM Piper ${MODE_NAME} Integration Test ===\n`);
    console.log(`Using: ${path.basename(MODEL_PATH)}`);

    // Check prerequisites
    for (const [name, p] of [
        ['WASM JS', WASM_JS], ['WASM file', WASM_WASM],
        ['Native test', NATIVE_TEST], ['Config', CONFIG_PATH],
        ['Model', MODEL_PATH], ['Espeak data', ESPEAK_DATA],
    ]) {
        if (!fs.existsSync(p)) {
            console.error(`Missing: ${name} (${p})`);
            process.exit(1);
        }
    }

    // Build native test
    console.log('Building native test...');
    const buildProc = spawn('cmake', ['--build', 'build_native'], {
        cwd: path.resolve(__dirname, '..'),
        stdio: ['pipe', 'pipe', 'pipe'],
    });
    await new Promise((resolve, reject) => {
        buildProc.on('close', (code) => code === 0 ? resolve() : reject(new Error(`Build failed (code ${code})`)));
        buildProc.stderr.on('data', (d) => process.stderr.write(d));
    });

    // Copy native test to expected location
    fs.copyFileSync(
        path.join(BASE_DIR, 'build_native', 'native_piper_test'),
        NATIVE_TEST
    );

    // Run native test
    console.log('\nRunning native test...');
    let nativeResult;
    try { nativeResult = await runNativeTest(); } catch (e) {
        console.error(`Native test failed: ${e.message}`);
        process.exit(1);
    }

    // Run WASM test
    console.log('\nRunning WASM test...');
    let wasmResult;
    try { wasmResult = await runWasmTest(); } catch (e) {
        console.error(`WASM test failed: ${e.message}`);
        process.exit(1);
    }

    // Compare results
    console.log('\n=== Comparing Results ===');
    const passed = compareResults('synthesis', nativeResult, wasmResult);

    // WAV similarity (real mode only)
    await checkWavSimilarity(nativeResult, wasmResult);

    // Final verdict
    if (passed) {
        console.log('\n[PASS] Native and WASM results match!');
        process.exit(0);
    } else {
        console.log('\n[FAIL] Results differ.');
        process.exit(1);
    }
}

main().catch(e => {
    console.error(`Fatal: ${e.message}`);
    process.exit(1);
});
