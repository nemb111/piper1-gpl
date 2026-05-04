var ortShimModule = (function() {
    var ort = null;
    var Module = null;
    var sessionHandle = null;
    var pendingInputs = null;
    var inferenceRunning = false;
    var inferenceDone = false;
    var inferencePromise = null;
    var inferenceResults = null;
    var inferenceReady = false;
    var outputNamesArr = [];

    function init(onnxruntimeModule, emModule) {
        ort = onnxruntimeModule;
        Module = emModule;
        if (Module) Module.ortShimModule = ortShimModule;
        globalThis.ortShimModule = ortShimModule;
    }

    async function ort_shim_init(modelPathUTF8) {
        var modelPath = Module.UTF8ToString(modelPathUTF8);
        sessionHandle = await ort.InferenceSession.create(modelPath, {
            executionProviders: ['wasm']
        });
        Module._ortShimSessionHandle = sessionHandle;
        outputNamesArr = sessionHandle.outputNames;
        return 0;
    }

    function ort_shim_get_output_names(handle, outBuf, maxBuf) {
        var count = outputNamesArr.length;
        var offset = 0;
        for (var i = 0; i < count && offset < maxBuf; i++) {
            var name = outputNamesArr[i];
            for (var j = 0; j < name.length && offset < maxBuf; j++) {
                Module.setValue(outBuf + offset++, name.charCodeAt(j), 'i8');
            }
            Module.setValue(outBuf + offset++, 0, 'i8');
        }
        Module.setValue(outBuf + offset, 0, 'i8');
        return count;
    }

    function ort_shim_set_input_data(handle, name, data, count, tensorType) {
        if (!handle) handle = Module._ortShimSessionHandle;
        if (!pendingInputs) pendingInputs = {};
        var nameStr = Module.UTF8ToString(name);
        var buffer = Module.HEAPU8.buffer;

        if (nameStr === 'input') {
            pendingInputs[nameStr] = new ort.Tensor('int64',
                Array.from(new BigInt64Array(buffer, data, count)).map(BigInt), [1, count]);
        } else if (nameStr === 'input_lengths') {
            pendingInputs[nameStr] = new ort.Tensor('int64',
                Array.from(new BigInt64Array(buffer, data, count)).map(BigInt), [1]);
        } else if (nameStr === 'scales') {
            pendingInputs[nameStr] = new ort.Tensor('float32',
                new Float32Array(buffer, data, count), [3]);
        } else if (nameStr === 'sid') {
            pendingInputs[nameStr] = new ort.Tensor('int64',
                Array.from(new BigInt64Array(buffer, data, count)).map(BigInt), [1]);
        }
        /* NOTE: inference is NOT triggered here. It's triggered explicitly by startNextInference() */
    }

    /* startNextInference - trigger ONNX inference with pending inputs.
     * This is called from JS, not from C++. The C++ path just stores inputs. */
    async function startNextInference() {
        if (!pendingInputs || !sessionHandle) return;
        if (inferenceRunning) {
            /* Previous inference still running — wait for it, but discard results
             * since new inputs are available. */
            await inferencePromise;
        }

        inferenceRunning = true;
        inferenceDone = false;
        inferenceReady = false;

        var feeds = {};
        for (var k in pendingInputs) feeds[k] = pendingInputs[k];
        pendingInputs = null;

        console.log('[ort_shim] Starting inference with inputs:', Object.keys(feeds));
        inferencePromise = sessionHandle.run(feeds);
        try {
            inferenceResults = await inferencePromise;
            console.log('[ort_shim] Inference done, outputs:', Object.keys(inferenceResults));
            inferenceDone = true;
            inferenceReady = true;
        } catch (e) {
            console.error('[ort_shim] Inference error:', e);
            inferenceResults = null;
            inferenceDone = true;
        }
        inferenceRunning = false;
    }

    /* waitForInferenceDone - wait for current inference to complete (called from JS) */
    async function waitForInferenceDone() {
        if (inferenceDone) return;
        if (inferenceRunning) {
            await inferencePromise;
        }
    }

    /* runInferenceInternal - used by ort_shim_run EM_JS for synchronous read */
    function runInferenceInternal(outputPtrs, outputCounts, maxOutputs, outputSizes, maxSizes) {
        if (!inferenceReady || !inferenceResults) {
            return 0;
        }

        var buffer = Module.HEAPU8.buffer;
        var keys = Object.keys(inferenceResults);
        var count = Math.min(keys.length, 16);

        for (var i = 0; i < count; i++) {
            var tensor = inferenceResults[keys[i]];
            var data = tensor.data;
            var size = data.length;

            var ptr = Module.getValue(outputPtrs + i * 4, 'i32');

            if (outputSizes) {
                Module.setValue(outputSizes + i * 4, size, 'i32');
            }

            if (ptr > 0 && size > 0 && ptr + size * 4 <= buffer.byteLength) {
                new Float32Array(buffer, ptr, size).set(data);
            }
        }

        return count;
    }

    /* pollRun - synchronous, for manual polling from JS loader. */
    function pollRun(outputPtrs, outputCounts, maxOutputs, outputSizes, maxSizes) {
        if (!inferenceReady) return 0;
        return runInferenceInternal(outputPtrs, outputCounts, maxOutputs, outputSizes, maxSizes);
    }

    return {
        init: init,
        ort_shim_init: ort_shim_init,
        ort_shim_get_output_names: ort_shim_get_output_names,
        ort_shim_set_input_data: ort_shim_set_input_data,
        startNextInference: startNextInference,
        waitForInferenceDone: waitForInferenceDone,
        pollRun: pollRun,
        get _inferenceReady() { return inferenceReady; },
        get _inferenceDone() { return inferenceDone; },
        get _inferenceRunning() { return inferenceRunning; }
    };
})();

if (typeof module !== 'undefined' && module.exports) {
    module.exports = ortShimModule;
}
