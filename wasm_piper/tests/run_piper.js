const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const createModule = require('../build/piper_wasm');
const ort = require('onnxruntime-web');

function writeWav(filename, samples, sampleRate) {
    const numChannels = 1, bitsPerSample = 16;
    const dataSize = samples.length * (bitsPerSample / 8);
    const fileSize = 44 + dataSize;
    const buf = Buffer.alloc(fileSize);
    let off = 0;
    function writeStr(s) { buf.write(s, off); off += s.length; }
    function writeUInt32LE(v) { buf.writeUInt32LE(v, off); off += 4; }
    function writeUInt16LE(v) { buf.writeUInt16LE(v, off); off += 2; }
    writeStr('RIFF'); writeUInt32LE(fileSize - 8); writeStr('WAVE'); writeStr('fmt ');
    writeUInt32LE(16); writeUInt16LE(1); writeUInt16LE(numChannels);
    writeUInt32LE(sampleRate); writeUInt32LE(sampleRate * numChannels * (bitsPerSample / 8));
    writeUInt16LE(numChannels * (bitsPerSample / 8)); writeUInt16LE(bitsPerSample);
    writeStr('data'); writeUInt32LE(dataSize);
    for (const s of samples) {
        buf.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(s * 32767))), off);
        off += 2;
    }
    fs.writeFileSync(filename, buf);
}

(async () => {
    const text = process.argv[2] || "I'm using the prebuilt web version.";
    const out = process.argv[3] || path.join(__dirname, 'output.wav');
    const ROOT = path.resolve(__dirname, '..', '..');
    const DATA_DIR = path.join(__dirname, 'data');

    console.log('Loading WASM...');
    const buildDir = path.join(__dirname, '..', 'build');
    const wasmBuf = fs.readFileSync(path.join(buildDir, 'piper_wasm.wasm'));
    const M = await createModule({
        wasmBinary: wasmBuf,
        locateFile: n => path.join(buildDir, n),
    });
    console.log('Memory:', (M.HEAPU8.buffer.byteLength / 1024 / 1024).toFixed(0), 'MB');

    // Initialize ort_shim module
    const ortShim = require('../shim/src/ort_shim');
    ortShim.init(ort, M);

    // Create piper synthesizer for phonemization
    const mp = M._malloc(256); M.stringToUTF8('/en_US-amy-low.onnx', mp, 256);
    const cp = M._malloc(256); M.stringToUTF8('/en_US-amy-low.onnx.json', cp, 256);
    const dp = M._malloc(256); M.stringToUTF8('/espeak-ng-data', dp, 256);
    const synth = M.ccall('piper_create', 'number', ['i8', 'i8', 'i8'], [mp, cp, dp]);
    M._free(mp); M._free(cp); M._free(dp);
    if (!synth) { console.error('Create failed'); process.exit(1); }
    console.log('Piper synthesizer created.');

    // Set options
    const optsPtr = M._malloc(16);
    M.setValue(optsPtr, 0, 'i32');
    M.HEAPF32[(optsPtr >> 2) + 1] = 1.0;
    M.HEAPF32[(optsPtr >> 2) + 2] = 0.667;
    M.HEAPF32[(optsPtr >> 2) + 3] = 0.8;

    const textPtr = M._malloc(text.length + 1);
    M.stringToUTF8(text, textPtr, text.length + 1);

    // Use piper_synthesize_start to set up phonemization
    const startRc = M.ccall('piper_synthesize_start', 'number',
                            ['number', 'i8', 'number'], [synth, textPtr, optsPtr]);
    console.log('piper_synthesize_start return:', startRc);

    // --- Now handle ONNX inference from JS, like synthesize_wasm.js ---

    // 1. Load config
    const configPath = path.resolve(__dirname, '..', 'tests', 'data', 'en_US-amy-low.onnx.json');
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

    // 2. Phonemize using espeak-ng CLI (same as synthesize_wasm.js)
    const ESPEAK_BIN = path.join(ROOT, 'wasm_piper', 'build', 'espeak_ng-install', 'bin', 'espeak-ng');
    const ESPEAK_DATA = path.join(DATA_DIR, 'espeak-ng-data');
    console.log('Phonemizing...');
    const result = spawnSync(ESPEAK_BIN, ['-v', 'en-us', '--ipa', '--stdout', text], {
        encoding: 'utf8',
        env: { ...process.env, ESPEAK_DATA },
        maxBuffer: 1024 * 1024,
    });
    const phonemes = result.stdout.split('\n')[0].trim();
    console.log('Phonemes:', phonemes.substring(0, 80));

    // 3. Convert phonemes to IDs
    const phonemeIdMap = {};
    for (const [sym, ids] of Object.entries(config.phoneme_id_map || {})) {
        for (const ch of sym) phonemeIdMap[ch] = ids;
    }
    const allIds = [];
    allIds.push(1); // BOS
    for (let i = 0; i < phonemes.length; i++) {
        const ch = phonemes[i];
        if (ch === ' ') { allIds.push(0); }
        else {
            allIds.push(0); // pad
            allIds.push(...(phonemeIdMap[ch] || [0]));
        }
    }
    allIds.push(2); // EOS
    console.log('Phoneme IDs:', allIds.length);

    // 4. Run ONNX inference
    console.log('Running ONNX inference...');
    const noiseScale = config.inference?.noise_scale || 0.667;
    const lengthScale = config.inference?.length_scale || 1.0;
    const noiseWScale = config.inference?.noise_w || 0.8;

    const feeds = {
        input: new ort.Tensor('int64', BigInt64Array.from(allIds.map(BigInt)), [1, allIds.length]),
        input_lengths: new ort.Tensor('int64', BigInt64Array.from([BigInt(allIds.length)]), [1]),
        scales: new ort.Tensor('float32', new Float32Array([noiseScale, lengthScale, noiseWScale]), [3]),
    };
    if (config.num_speakers > 1) {
        feeds.sid = new ort.Tensor('int64', BigInt64Array.from([BigInt(0)]), [1]);
    }

    // Initialize ONNX session
    const modelPath = path.resolve(__dirname, '..', 'tests', 'data', 'en_US-amy-low.onnx');
    const modelPathPtr = M._malloc(256);
    M.stringToUTF8(modelPath, modelPathPtr, 256);
    await ortShim.ort_shim_init(modelPathPtr);
    M._free(modelPathPtr);

    // Run inference - use ort_shim module directly
    const sessionHandle = await ort.InferenceSession.create(modelPath, {
        executionProviders: ['wasm'],
    });
    const results = await sessionHandle.run(feeds);
    const firstKey = Object.keys(results)[0];
    const audioData = results[firstKey].data;
    const samples = Array.from(audioData);

    console.log('Inference done. Samples:', samples.length);

    // 5. Write WAV
    const sr = config.audio.sample_rate;
    // Normalize
    let peak = 0;
    for (let i = 0; i < samples.length; i++) {
        const a = Math.abs(samples[i]);
        if (a > peak) peak = a;
    }
    if (peak > 0) {
        const gain = 0.707 / peak;
        for (let i = 0; i < samples.length; i++) samples[i] *= gain;
    }
    writeWav(out, samples, sr);
    const sizeKB = (Buffer.byteLength(fs.readFileSync(out)) / 1024).toFixed(1);
    const duration = (samples.length / sr).toFixed(2);
    console.log(`WAV saved to: ${out} (${sizeKB}KB, ${duration}s)`);

    M._free(textPtr);
    M.ccall('piper_free', null, ['number'], [synth]);
    console.log('Done.');
})().catch(e => { console.error(e); process.exit(1); });
