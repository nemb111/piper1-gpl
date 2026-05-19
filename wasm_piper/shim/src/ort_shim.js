/**
 * ort_shim.js -- ONNX Runtime C++ API shim for Emscripten/WASM.
 *
 * Bridges ONNX Runtime C++ API calls (Ort::Session, Ort::Value) to
 * onnxruntime-web via EM_JS interop defined in onnxruntime_cxx_api.h.
 *
 * Key design: ort.js uses a SEPARATE WASM memory from Emscripten.
 * Audio data is written directly into the piper chunk struct by
 * ort_shim during inference, bypassing the Value mechanism entirely.
 *
 * Session initialization is lazy -- happens on first Run() call.
 * The Emscripten Module is registered via setModule() called from
 * ort_shim_set_module EM_JS.
 */
var ortShimModule = (function() {
    /* -- Lazy-loaded onnxruntime-web -- */
    var ort = null;
    function getOrt() {
        if (!ort) ort = require('onnxruntime-web');
        return ort;
    }

    /* -- Emscripten Module reference -- */
    var emModule = null;
    function getModule() { return emModule; }

    /* -- Session init tracking -- */
    var sessionInitialized = false;
    var storedModelPath = null;

    /* -- ONNX session state -- */
    var sessionHandle = null;
    var outputNamesArr = [];

    /* -- Input tensor batching (synchronous, called from C++) -- */
    var pendingInputs = null;
    var inferenceRunning = false;
    var inferenceDone = false;
    var inferencePromise = null;

    /* -- Audio output buffers in Emscripten heap (double-buffered).
     * Two alternating buffers prevent ort_shim from overwriting
     * audio data that piper.cpp has already returned via the chunk. */
    var audioHeapPtrA = 0;
    var audioHeapSizeA = 0;
    var audioHeapPtrB = 0;
    var audioHeapSizeB = 0;
    var audioBufferFlip = 0; // 0=A, 1=B

    var api = {
        _audioPtr: 0,
        _audioSize: 0
    };

    /* Called by ort_shim_set_module EM_JS */
    api.setModule = function(m) {
        emModule = m;
        if (m) m.ortShimModule = api;
        globalThis.ortShimModule = api;
    };

    /* Legacy init() -- for backward compat, forwards to setModule */
    api.init = function(init_em) {
        if (init_em) api.setModule(init_em);
    };

    /* Called from C++ to store the model path for lazy session init */
    api.setModelPath = function(pathPtr) {
        var m = getModule();
        if (pathPtr && pathPtr !== 0 && !storedModelPath) {
            storedModelPath = m.UTF8ToString(pathPtr);
        }
    };

    /* Lazy session init -- called on first Run() if not already done */
    api.lazyInitSession = async function(modelPath) {
        if (sessionInitialized) return;

        var m = getModule();
        if (!m) return;

        sessionHandle = await getOrt().InferenceSession.create(modelPath, {
            executionProviders: ['wasm'],
            wasmPaths: require('path').dirname(require.resolve('onnxruntime-web')) + '/dist/',
        });
        sessionInitialized = true;
        outputNamesArr = sessionHandle.output_names;
    };

    /* Called by Ort::Session::Run() for each input tensor */
    api.ort_shim_set_input_data = function(handle, name, data, count, tensorType) {
        if (!handle) handle = _getSessionHandle();
        var m = getModule();
        if (!pendingInputs) pendingInputs = {};
        var nameStr = m.UTF8ToString(name);
        var wasmBuffer = m.HEAPU8.buffer;

        if (nameStr === 'scales') {
            var fSrc = new Float32Array(wasmBuffer, data, count);
            var fArr = new Float32Array(count);
            for (var i = 0; i < count; i++) fArr[i] = fSrc[i];
            pendingInputs[nameStr] = { floatData: fArr, count: count };
        } else {
            var bigSrc = new BigInt64Array(wasmBuffer, data, count);
            var bigData = new BigInt64Array(count);
            for (var i = 0; i < count; i++) bigData[i] = bigSrc[i];
            pendingInputs[nameStr] = { intData: Array.from(bigData).map(Number), count: count };
        }
    };

    /**
     * ort_shim_run -- triggers inference with batched inputs.
     * On first call, lazily initializes the ONNX session if needed.
     * Copies audio from ort.js's separate WASM memory to Emscripten heap.
     *
     * @param {number} chunkPtr - piper chunk pointer (unused here)
     * @param {number|null} outputSizes - C pointer to output sizes array
     * @param {number|null} maxSizes - max sizes for output
     * @param {number|null} audioPtrOut - C pointer to store audio heap ptr
     * @param {number|null} audioSizeOut - C pointer to store audio sample count
     */
    api.ort_shim_run = async function(chunkPtr, outputSizes, maxSizes, audioPtrOut) {
        var m = getModule();
        var ort = getOrt();

        /* Wait for any still-running inference before starting next */
        if (inferenceRunning) {
            await inferencePromise;
        }

        /* Lazy session init on first Run() call */
        if (!sessionInitialized && storedModelPath) {
            await api.lazyInitSession(storedModelPath);
        }

        /* Only trigger inference if there are pending inputs. */
        if (pendingInputs && sessionHandle) {
            inferenceRunning = true;

            var feeds = {};
            for (var k in pendingInputs) {
                var inp = pendingInputs[k];
                if (inp.floatData) {
                    feeds[k] = new ort.Tensor('float32', inp.floatData, [inp.count]);
                } else {
                    if (k === 'input') {
                        feeds[k] = new ort.Tensor('int64', inp.intData, [1, inp.count]);
                    } else {
                        feeds[k] = new ort.Tensor('int64', inp.intData, [1]);
                    }
                }
            }
            pendingInputs = null;

            inferencePromise = sessionHandle.run(feeds);
            try {
                var results = await inferencePromise;

                if (results['output']) {
                    var srcData = results['output'].data;
                    var numSamples = srcData.length;

                    /* Prevent ort.js from cleaning up this buffer */
                    ort._currentTensorData = srcData;

                    /* Allocate persistent Emscripten heap buffer (alternating buffers) */
                    var activePtr = audioBufferFlip ? audioHeapPtrB : audioHeapPtrA;
                    var activeSize = audioBufferFlip ? audioHeapSizeB : audioHeapSizeA;
                    if (numSamples > activeSize) {
                        if (activePtr) m._free(activePtr);
                        activePtr = m._malloc(numSamples * 4);
                        if (audioBufferFlip) {
                            audioHeapPtrB = activePtr;
                            audioHeapSizeB = numSamples;
                        } else {
                            audioHeapPtrA = activePtr;
                            audioHeapSizeA = numSamples;
                        }
                    }

                    /* ort.js uses a SEPARATE WASM memory from Emscripten.
                     * Extract ALL values into a plain JS array IMMEDIATELY. */
                    var values = new Array(numSamples);
                    for (var i = 0; i < numSamples; i++) {
                        values[i] = srcData[i];
                    }

                    /* Free ort.js tensor NOW, before writing to Emscripten heap */
                    ort._currentTensorData = null;

                    /* Copy all values to Emscripten heap via temporary ArrayBuffer */
                    if (activePtr && numSamples > 0) {
                        var floatBuf = new ArrayBuffer(numSamples * 4);
                        var floatView = new Float32Array(floatBuf);
                        for (var i = 0; i < numSamples; i++) {
                            floatView[i] = values[i];
                        }
                        var heapU8 = new Uint8Array(m.HEAPU8.buffer, activePtr, numSamples * 4);
                        heapU8.set(new Uint8Array(floatBuf));

                        /* Write back audio pointer and size */
                        ortShimModule._audioHeapPtr = activePtr;
                        globalThis.ortShimModule._audioPtr = activePtr;
                        globalThis.ortShimModule._audioSize = numSamples;
                    }

                    /* Flip buffer for next inference */
                    audioBufferFlip = 1 - audioBufferFlip;
                }
                inferenceDone = true;
            } catch (e) {
                inferenceDone = true;
            }
            inferenceRunning = false;
        } else {
            inferenceDone = true;
            inferenceRunning = false;
        }

        /* Write output size */
        if (outputSizes) {
            m.setValue(outputSizes, globalThis.ortShimModule._audioSize || 0, 'i32');
        }
        return 1;
    };

    api.ort_shim_get_output_names = function(handle, outBuf, maxBuf) {
        var m = getModule();
        var count = outputNamesArr.length;
        var offset = 0;
        for (var i = 0; i < count && offset < maxBuf; i++) {
            var name = outputNamesArr[i];
            for (var j = 0; j < name.length && offset < maxBuf; j++) {
                m.setValue(outBuf + offset++, name.charCodeAt(j), 'i8');
            }
            m.setValue(outBuf + offset++, 0, 'i8');
        }
        m.setValue(outBuf + offset, 0, 'i8');
        return count;
    };

    api.waitForInferenceDone = async function() {
        if (inferenceDone) return;
        if (inferenceRunning) {
            await inferencePromise;
        }
    };

    api.cleanup = function() {
        if (audioHeapPtrA) { var m = getModule(); m._free(audioHeapPtrA); audioHeapPtrA = 0; audioHeapSizeA = 0; }
        if (audioHeapPtrB) { var m = getModule(); m._free(audioHeapPtrB); audioHeapPtrB = 0; audioHeapSizeB = 0; }
        sessionHandle = null;
        pendingInputs = null;
        inferenceRunning = false;
        inferenceDone = false;
        sessionInitialized = false;
    };

    function _getSessionHandle() {
        return (emModule && emModule._ortShimSessionHandle) || 0;
    }

    Object.defineProperty(api, '_sessionHandle', {
        get: function() { return api._sessionHandleInt || 0; },
        configurable: true
    });
    Object.defineProperty(api, '_inferenceDone', {
        get: function() { return inferenceDone; },
        configurable: true
    });
    Object.defineProperty(api, '_inferenceRunning', {
        get: function() { return inferenceRunning; },
        configurable: true
    });

    return api;
})();

/* Always available on globalThis for EM_JS stubs */
globalThis.ortShimModule = ortShimModule;
