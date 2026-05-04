#!/usr/bin/env node
/**
 * WASM-side piper audio synthesis using onnxruntime-web + espeak-ng.
 * Produces a WAV file from text using the Piper voice model.
 *
 * Usage: node synthesize.js <model.onnx> <model.onnx.json> <text> [output.wav]
 *
 * Environment variables:
 *   ESPEAK_BIN    - Path to espeak-ng binary (default: build/espeak_ng-install/bin/espeak-ng)
 *   ESPEAK_DATA   - Path to espeak-ng data directory (default: tests/data/espeak-ng-data)
 */

const { spawnSync } = require('child_process');
const { writeFileSync } = require('fs');
const path = require('path');
const ort = require('onnxruntime-web');

// ── Paths ───────────────────────────────────────────────────────────
const __DIR__ = __dirname;                          // wasm_piper/
const ROOT = path.resolve(__DIR__, '..');           // repo root
const DATA_DIR = path.join(__DIR__, 'tests', 'data');

const ESPEAK_BIN = process.env.ESPEAK_BIN || path.join(
    __DIR__, 'build', 'espeak_ng-install', 'bin', 'espeak-ng'
);
const ESPEAK_DATA = process.env.ESPEAK_DATA || path.join(DATA_DIR, 'espeak-ng-data');

// ── Helpers ─────────────────────────────────────────────────────────

function phonemize(text) {
    const result = spawnSync(ESPEAK_BIN, ['-v', 'en-us', '--ipa', '--stdout', text], {
        encoding: 'utf8',
        env: { ...process.env, ESPEAK_DATA },
        maxBuffer: 1024 * 1024,
    });
    return result.stdout.split('\n')[0].trim();
}

function textToPhonemeIds(text, phonemeIdMap) {
    const phonemes = phonemize(text);
    const ids = [];
    ids.push(1); // BOS

    for (let i = 0; i < phonemes.length; i++) {
        const ch = phonemes[i];
        if (ch === ' ') {
            ids.push(0); // phoneme separator
        } else {
            const pid = phonemeIdMap[ch] || [0];
            ids.push(0); // pad
            ids.push(...pid);
        }
    }

    ids.push(2); // EOS
    return ids;
}

function normalizeAudio(samples) {
    let peak = 0;
    for (let i = 0; i < samples.length; i++) {
        const a = Math.abs(samples[i]);
        if (a > peak) peak = a;
    }
    if (peak > 0) {
        const gain = 0.707 / peak;
        for (let i = 0; i < samples.length; i++) samples[i] *= gain;
    }
    return samples;
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
        buf.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(s * 32767))), off);
        off += 2;
    }

    writeFileSync(filename, buf);
}

// ── Main ────────────────────────────────────────────────────────────

async function synthesize(modelPath, configPath, text, outputPath) {
    // 1. Load config
    const config = JSON.parse(require('fs').readFileSync(configPath, 'utf8'));

    // 2. Build phoneme ID map
    const phonemeIdMap = {};
    for (const [sym, ids] of Object.entries(config.phoneme_id_map || {})) {
        for (const ch of sym) phonemeIdMap[ch] = ids;
    }

    const numSpeakers = config.num_speakers || 1;
    const sr = config.audio.sample_rate;

    // 3. Phonemize + encode
    const allIds = textToPhonemeIds(text, phonemeIdMap);
    const phonemes = phonemize(text);

    // 4. ONNX inference
    const noiseScale = config.inference?.noise_scale || 0.667;
    const lengthScale = config.inference?.length_scale || 1.0;
    const noiseWScale = config.inference?.noise_w || 0.8;

    const session = await ort.InferenceSession.create(modelPath, {
        executionProviders: ['wasm'],
    });

    const inputTensor = new ort.Tensor('int64', BigInt64Array.from(allIds.map(BigInt)), [1, allIds.length]);
    const lengthTensor = new ort.Tensor('int64', BigInt64Array.from([BigInt(allIds.length)]), [1]);
    const scalesTensor = new ort.Tensor('float32', new Float32Array([noiseScale, lengthScale, noiseWScale]), [3]);

    const feeds = { input: inputTensor, input_lengths: lengthTensor, scales: scalesTensor };
    if (numSpeakers > 1) {
        feeds.sid = new ort.Tensor('int64', BigInt64Array.from([BigInt(0)]), [1]);
    }

    const results = await session.run(feeds);
    const audio = results[Object.keys(results)[0]].data;
    let samples = Array.from(audio);

    // 5. Normalize audio (-3dB peak)
    normalizeAudio(samples);

    // 6. Write WAV
    writeWav(outputPath, samples, sr);

    console.log(`Synthesized ${samples.length} samples (${(samples.length / sr).toFixed(1)}s) -> ${outputPath}`);
    console.log(`  Phonemes: ${phonemes.substring(0, 60)}`);
    console.log(`  Phoneme IDs: ${allIds.length}`);
}

// ── CLI ─────────────────────────────────────────────────────────────

if (require.main === module) {
    const modelPath = process.argv[2] || 'model.onnx';
    const configPath = process.argv[3] || 'model.onnx.json';
    const text = process.argv[4] || 'hello world';
    const outputPath = process.argv[5] || 'synthesize.wav';

    synthesize(modelPath, configPath, text, outputPath).catch(e => {
        console.error('Error:', e.message);
        process.exit(1);
    });
}

module.exports = { synthesize };
