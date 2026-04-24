/**
 * JavaScript wrapper for the piper WASM module.
 *
 * Exposes an API that mirrors libpiper/src/piper.cpp:
 *   create(model, config, espeakData) -> Piper
 *   piper_free(synth)   // via Piper destructor
 *   defaultSynthesizeOptions(synth) -> { speaker_id, length_scale, noise_scale, noise_w_scale }
 *   synthesizeStart(text, options?) -> PIPER_OK / error
 *   synthesizeNext(chunk) -> PIPER_OK | PIPER_DONE | error
 *
 * Memory management: the Piper class allocates and frees all WASM memory
 * (string buffers, option structs, audio chunk buffers) via RAII-style
 * wrappers. Users interact with plain JS objects / Uint8Arrays.
 */

const fs = require('fs');
const path = require('path');

// ── Constants ──

const PIPER_OK     = 0;
const PIPER_DONE   = 1;
const PIPER_ERR    = -1;

// piper_synthesize_options layout: 16 bytes, packed, 64-bit platform
const OPT_SPEAKER_ID   = 0;  // int32
const OPT_LENGTH_SCALE = 4;  // float32
const OPT_NOISE_SCALE  = 8;  // float32
const OPT_NOISE_W      = 12; // float32

// piper_audio_chunk layout: 80 bytes, packed, 64-bit platform
const CHUNK_SAMPLES         = 0;
const CHUNK_NUM_SAMPLES     = 8;
const CHUNK_SAMPLE_RATE     = 16;
const CHUNK_IS_LAST         = 20;
const CHUNK_PHONEMES        = 24;
const CHUNK_NUM_PHONEMES    = 32;
const CHUNK_PHONEME_IDS     = 40;
const CHUNK_NUM_PHONEME_IDS = 48;
const CHUNK_ALIGNMENTS      = 56;
const CHUNK_NUM_ALIGNMENTS  = 64;

const CHUNK_BUF_SIZE = 80;

// ── Helpers ──

/**
 * Allocate a UTF-8 string in WASM heap, call fn(ptr), then free.
 */
function usingStr(module, str, fn) {
    const len = Buffer.byteLength(str, 'utf8');
    const ptr = module._malloc(len + 1);
    module.stringToUTF8(str, ptr, len + 1);
    try { return fn(ptr); }
    finally { module._free(ptr); }
}

/**
 * Allocate WASM memory, call fn(ptr), then free.
 */
function usingMem(module, size, fn) {
    const ptr = module._malloc(size);
    try { return fn(ptr); }
    finally { module._free(ptr); }
}

function readU8(buf, off)     { return buf[off]; }
function readS32(buf, off)    { return buf.getInt32(off, true); }
function readU32(buf, off)    { return buf.getUint32(off, true); }
function readF32(buf, off)    { return buf.getFloat32(off, true); }
function readI64(buf, off)    { return buf.getBigInt64(off, true); }
function readU64(buf, off)    { return buf.getBigUint64(off, true); }

/**
 * Get module reference (handles fat-arrow / bound-method issues).
 */
function getMod(self) { return self._mod; }

// ── Factory ──

/**
 * Load the WASM module from a .js file path.
 *
 * @param {string} jsPath  - Path to the piper_wasm_capi_test.js (or _real)
 * @param {object} [opts]  - Additional Module constructor options
 * @returns {Promise<Module>}
 */
async function loadModule(jsPath, opts = {}) {
    const wasmBinary = fs.readFileSync(jsPath.replace(/\.js$/, '.wasm'));
    const wasmDir = path.dirname(jsPath);

    return new (require(jsPath))({
        wasmBinary,
        locateFile: (name) => path.join(wasmDir, name),
        ...opts,
    });
}

// ── Piper class ──

/**
 * A Piper synthesizer instance wrapping a WASM piper_synthesizer*.
 *
 * Usage:
 *   const piper = await Piper.create(module, modelPath, configPath, espeakPath);
 *   const ok = piper.synthesizeStart('hello world');
 *   while (true) {
 *     const chunk = piper.synthesizeNext();
 *     if (chunk.done) break;
 *     console.log(chunk.samples.length, chunk.sampleRate, chunk.isLast);
 *   }
 *   piper.dispose();
 */
class Piper {
    /**
     * @param {Module} mod  - The EMSCRIPTEN Module instance
     * @param {number} handle - WASM pointer to piper_synthesizer
     */
    constructor(mod, handle) {
        this._mod = mod;
        this._handle = handle;
    }

    /**
     * Load WASM module and create a synthesizer.
     *
     * @param {Module} mod
     * @param {string} modelPath   - WASM FS path to .onnx model
     * @param {string} configPath  - WASM FS path to .json config (or null)
     * @param {string} espeakPath  - WASM FS path to espeak-ng-data
     * @returns {Promise<Piper>}
     */
    static async create(mod, modelPath, configPath, espeakPath) {
        const handle = await new Promise((resolve, reject) => {
            usingStr(mod, modelPath, (modelPtr) => {
                usingStr(mod, configPath || '', (configPtr) => {
                    usingStr(mod, espeakPath || '', (espeakPtr) => {
                        const handle = mod.ccall(
                            'piper_wasm_create', 'number',
                            ['i8', 'i8', 'i8'],
                            [modelPtr, configPtr, espeakPtr]
                        );
                        resolve(handle);
                    });
                });
            });
        });

        if (!handle) {
            throw new Error('piper_create returned NULL — check paths and espeak-ng-data');
        }

        return new Piper(mod, handle);
    }

    /** WASM synthesizer handle (for advanced use). */
    get handle() { return this._handle; }

    /** Release WASM resources. */
    dispose() {
        if (this._handle) {
            this._mod.ccall('piper_wasm_free', null, ['number'], [this._handle]);
            this._handle = 0;
        }
    }

    // ── Options ──

    /**
     * Get default synthesis options from the model config.
     * @returns {{ speaker_id: number, length_scale: number, noise_scale: number, noise_w_scale: number }}
     */
    getDefaultOptions() {
        return usingMem(this._mod, 16, (optsPtr) => {
            this._mod.ccall(
                'piper_wasm_default_synthesize_options', null,
                ['number', 'number'],
                [this._handle, optsPtr]
            );
            const heap = new Uint8Array(this._mod.HEAPU8.buffer, optsPtr, 16);
            const view = new DataView(heap.buffer, heap.byteOffset);
            return {
                speaker_id:   view.getInt32(OPT_SPEAKER_ID,   true),
                length_scale: view.getFloat32(OPT_LENGTH_SCALE, true),
                noise_scale:  view.getFloat32(OPT_NOISE_SCALE,  true),
                noise_w_scale: view.getFloat32(OPT_NOISE_W,     true),
            };
        });
    }

    /**
     * Build an options struct in WASM memory.
     * @param {object} opts - { speaker_id?, length_scale?, noise_scale?, noise_w_scale? }
     * @returns {{ ptr: number, release: () => void }}
     */
    allocOptions(opts = {}) {
        const ptr = this._mod._malloc(16);
        const heap = new Uint8Array(this._mod.HEAPU8.buffer, ptr, 16);
        const view = new DataView(heap.buffer, heap.byteOffset);

        view.setInt32(OPT_SPEAKER_ID,     opts.speaker_id   ?? 0,    true);
        view.setFloat32(OPT_LENGTH_SCALE,  opts.length_scale  ?? 1.0, true);
        view.setFloat32(OPT_NOISE_SCALE,   opts.noise_scale   ?? 0.667, true);
        view.setFloat32(OPT_NOISE_W,       opts.noise_w_scale ?? 0.8, true);

        return {
            ptr,
            release: () => this._mod._free(ptr),
        };
    }

    // ── Synthesis ──

    /**
     * Start synthesis for a text string.
     * @param {string} text
     * @param {object} [options] - Options struct or plain object
     * @returns {number} PIPER_OK or error code
     */
    synthesizeStart(text, options) {
        if (!this._handle) throw new Error('Piper disposed');

        // Allocate options struct if plain object provided
        let optResult = null;
        let optPtr = 0;
        if (options) {
            if (options.ptr !== undefined) {
                optPtr = options.ptr;
            } else {
                optResult = this.allocOptions(options);
                optPtr = optResult.ptr;
            }
        }

        let rc;
        try {
            rc = usingStr(this._mod, text, (textPtr) => {
                return this._mod.ccall(
                    'piper_wasm_synthesize_start', 'number',
                    ['number', 'i8', 'number'],
                    [this._handle, textPtr, optPtr]
                );
            });
        } finally {
            if (optResult) optResult.release();
        }

        return rc;
    }

    /**
     * Read next audio chunk. Returns a plain JS object with copied data.
     *
     * @returns {{
     *   samples: Float32Array, numSamples: number, sampleRate: number,
     *   isLast: boolean, phonemes: Uint32Array, phonemeIds: Int32Array,
     *   alignments: Int32Array, done: boolean, error: number
     * }}
     */
    synthesizeNext() {
        const mod = this._mod;
        const chunkPtr = mod._malloc(CHUNK_BUF_SIZE);

        const rc = mod.ccall(
            'piper_wasm_synthesize_next', 'number',
            ['number', 'number'],
            [this._handle, chunkPtr]
        );

        // Read chunk struct
        const heap = new Uint8Array(mod.HEAPU8.buffer, chunkPtr, CHUNK_BUF_SIZE);
        const view = new DataView(heap.buffer, heap.byteOffset);

        const numSamples = view.getUint32(CHUNK_NUM_SAMPLES, true);
        const sampleRate = view.getInt32(CHUNK_SAMPLE_RATE, true);
        const isLast = !!view.getUint8(CHUNK_IS_LAST);

        const samplesPtr = Number(view.getBigUint64(CHUNK_SAMPLES, true));
        const phonemesPtr = Number(view.getBigUint64(CHUNK_PHONEMES, true));
        const numPhonemes = view.getUint32(CHUNK_NUM_PHONEMES, true);
        const phonemeIdsPtr = Number(view.getBigUint64(CHUNK_PHONEME_IDS, true));
        const numPhonemeIds = view.getUint32(CHUNK_NUM_PHONEME_IDS, true);
        const alignmentsPtr = Number(view.getBigUint64(CHUNK_ALIGNMENTS, true));
        const numAlignments = view.getUint32(CHUNK_NUM_ALIGNMENTS, true);

        // Copy sample data (must copy — invalidated on next synthesizeNext call)
        const samples = samplesPtr
            ? new Float32Array(mod.HEAPU8.buffer.slice(samplesPtr, samplesPtr + numSamples * 4))
            : new Float32Array(0);

        const phonemes = phonemesPtr && numPhonemes
            ? new Uint32Array(mod.HEAPU8.buffer.slice(phonemesPtr, phonemesPtr + numPhonemes * 4))
            : new Uint32Array(0);

        const phonemeIds = phonemeIdsPtr && numPhonemeIds
            ? new Int32Array(mod.HEAPU8.buffer.slice(phonemeIdsPtr, phonemeIdsPtr + numPhonemeIds * 4))
            : new Int32Array(0);

        const alignments = alignmentsPtr && numAlignments
            ? new Int32Array(mod.HEAPU8.buffer.slice(alignmentsPtr, alignmentsPtr + numAlignments * 4))
            : new Int32Array(0);

        mod._free(chunkPtr);

        return {
            samples,
            numSamples,
            sampleRate,
            isLast,
            phonemes,
            numPhonemes,
            phonemeIds,
            numPhonemeIds,
            alignments,
            numAlignments,
            done: rc === PIPER_DONE,
            error: rc < 0 ? rc : undefined,
        };
    }

    /**
     * Full synthesis: start -> next* -> collect all samples.
     *
     * @param {string} text
     * @param {object} [options]
     * @returns {{ samples: Float32Array, sampleRate: number, chunks: number }}
     */
    synthesizeFull(text, options) {
        const startRc = this.synthesizeStart(text, options);
        if (startRc !== PIPER_OK) {
            throw new Error(`piper_synthesize_start failed: ${startRc}`);
        }

        const allSamples = [];
        let chunks = 0;
        let sampleRate = 0;

        while (true) {
            const chunk = this.synthesizeNext();
            if (chunk.error) throw new Error(`synthesis error: ${chunk.error}`);
            if (chunk.done) break;

            sampleRate = chunk.sampleRate;
            allSamples.push(chunk.samples);
            chunks++;
        }

        // Concatenate all sample chunks
        const totalLen = allSamples.reduce((s, a) => s + a.length, 0);
        const result = new Float32Array(totalLen);
        let offset = 0;
        for (const buf of allSamples) {
            result.set(buf, offset);
            offset += buf.length;
        }

        return { samples: result, sampleRate, chunks };
    }

    /**
     * Async generator: yields audio chunks one at a time.
     *
     * @param {string} text
     * @param {object} [options]
     * @yields {{ samples: Float32Array, sampleRate: number, isLast: boolean, ... }}
     */
    async* synthesizeStream(text, options) {
        const startRc = this.synthesizeStart(text, options);
        if (startRc !== PIPER_OK) {
            throw new Error(`piper_synthesize_start failed: ${startRc}`);
        }

        while (true) {
            const chunk = this.synthesizeNext();
            if (chunk.error) throw new Error(`synthesis error: ${chunk.error}`);
            yield chunk;
            if (chunk.done) break;
        }
    }
}

// ── Exports ──

module.exports = {
    PIPER_OK,
    PIPER_DONE,
    PIPER_ERR,
    loadModule,
    Piper,
};
