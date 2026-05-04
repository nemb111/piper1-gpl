#!/usr/bin/env node
/**
 * Synthesize audio using the WASM build + onnxruntime-web.
 *
 * Usage: node synthesize_wasm.js <model.onnx> <model.onnx.json> <text> [output.wav]
 */

const { spawnSync } = require('child_process');
const { writeFileSync, mkdirSync, existsSync } = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const DATA_DIR = path.join(__dirname, 'data');

const ESPEAK_BIN = process.env.ESPEAK_BIN || path.join(ROOT, 'wasm_piper', 'build', 'espeak_ng-install', 'bin', 'espeak-ng');
const ESPEAK_DATA = process.env.ESPEAK_DATA || path.join(DATA_DIR, 'espeak-ng-data');

// Load ONNX Runtime Web (npm package — replaces Emscripten ONNX compilation)
const ort = require('onnxruntime-web');
ort.env.wasm.numThreads = 1;

function phonemize(text) {
    const result = spawnSync(ESPEAK_BIN, ['-v', 'en-us', '--ipa', '--stdout', text], {
        encoding: 'utf8',
        env: { ...process.env, ESPEAK_DATA },
        maxBuffer: 1024 * 1024,
    });
    return result.stdout.split('\n')[0].trim();
}

function writeWav(filename, samples, sampleRate) {
    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * (bitsPerSample / 8);
    const blockAlign = numChannels * (bitsPerSample / 8);
    const dataSize = samples.length * (bitsPerSample / 8);
    const fileSize = 44 + dataSize;

    const buf = Buffer.alloc(fileSize);
    let off = 0;

    function writeStr(s) { buf.write(s, off); off += s.length; }
    function writeUInt32LE(v) { buf.writeUInt32LE(v, off); off += 4; }
    function writeUInt16LE(v) { buf.writeUInt16LE(v, off); off += 2; }

    writeStr('RIFF');
    writeUInt32LE(fileSize - 8);
    writeStr('WAVE');
    writeStr('fmt ');
    writeUInt32LE(16);
    writeUInt16LE(1);
    writeUInt16LE(numChannels);
    writeUInt32LE(sampleRate);
    writeUInt32LE(byteRate);
    writeUInt16LE(blockAlign);
    writeUInt16LE(bitsPerSample);
    writeStr('data');
    writeUInt32LE(dataSize);

    for (const s of samples) {
        buf.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(s * 32767))), off);
        off += 2;
    }

    writeFileSync(filename, buf);
}

async function main() {
    const modelPath = process.argv[2] || path.join(DATA_DIR, 'en_US-amy-low.onnx');
    const configPath = process.argv[3] || path.join(DATA_DIR, 'en_US-amy-low.onnx.json');
    const text = process.argv[4] || 'the quick brown fox jumps over the lazy dog';
    const outputPath = process.argv[5] || path.join(__dirname, 'output.wav');

    console.log(`Model: ${modelPath}`);
    console.log(`Config: ${configPath}`);
    console.log(`Text: "${text}"`);

    // 1. Load config
    const config = JSON.parse(require('fs').readFileSync(configPath, 'utf8'));

    // 2. Create ONNX session
    console.log('Creating ONNX session...');
    const session = await ort.InferenceSession.create(modelPath, {
        executionProviders: ['wasm'],
    });

    // 3. Phonemize
    const phonemes = phonemize(text);
    console.log(`Phonemes: ${phonemes.substring(0, 80)}`);

    // 4. Convert phonemes to IDs
    const phonemeIdMap = {};
    for (const [sym, ids] of Object.entries(config.phoneme_id_map || {})) {
        for (const ch of sym) phonemeIdMap[ch] = ids;
    }

    const allIds = [];
    allIds.push(1); // BOS
    for (let i = 0; i < phonemes.length; i++) {
        const ch = phonemes[i];
        if (ch === ' ') {
            allIds.push(0);
        } else {
            const pid = phonemeIdMap[ch] || [0];
            allIds.push(0); // pad
            allIds.push(...pid);
        }
    }
    allIds.push(2); // EOS

    console.log(`Phoneme IDs: ${allIds.length}`);

    // 5. Run ONNX inference
    console.log('Running ONNX inference...');
    const inputTensor = new ort.Tensor('int64', BigInt64Array.from(allIds.map(BigInt)), [1, allIds.length]);
    const lengthTensor = new ort.Tensor('int64', BigInt64Array.from([BigInt(allIds.length)]), [1]);
    const noiseScale = config.inference?.noise_scale || 0.667;
    const lengthScale = config.inference?.length_scale || 1.0;
    const noiseWScale = config.inference?.noise_w || 0.8;
    const scalesTensor = new ort.Tensor('float32', new Float32Array([noiseScale, lengthScale, noiseWScale]), [3]);

    const feeds = { input: inputTensor, input_lengths: lengthTensor, scales: scalesTensor };
    if (config.num_speakers > 1) {
        feeds.sid = new ort.Tensor('int64', BigInt64Array.from([BigInt(0)]), [1]);
    }

    const results = await session.run(feeds);
    const firstKey = Object.keys(results)[0];
    const audio = results[firstKey].data;
    const samples = Array.from(audio);

    // 6. Write WAV
    const sr = config.audio.sample_rate;
    writeWav(outputPath, samples, sr);

    const duration = (samples.length / sr).toFixed(1);
    console.log(`\nSynthesized ${samples.length} samples (${duration}s) @ ${sr}Hz`);
    console.log(`Output: ${outputPath}`);
}

main().catch(e => {
    console.error('Error:', e.message);
    console.error(e.stack);
    process.exit(1);
});
