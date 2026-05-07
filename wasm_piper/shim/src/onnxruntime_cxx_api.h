/**
 * onnxruntime_cxx_api.h -- ONNX Runtime C++ API shim for Emscripten/WASM.
 *
 * Implements the Ort namespace used by piper.cpp by forwarding calls
 * to onnxruntime-web via EM_JS functions defined in ort_shim.js.
 *
 * Key design: ort.js uses a separate WASM memory from Emscripten.
 * Audio data is written directly into the piper chunk struct by
 * ort_shim during inference, bypassing the Value mechanism entirely.
 *
 * Session initialization is lazy -- done on first Run() call.
 * The Emscripten Module is registered once by ortShimModule.setModule().
 */
#ifndef ONNXRUNTIME_CXX_API_H
#define ONNXRUNTIME_CXX_API_H

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include <emscripten.h>

/* -- EM_JS declarations (implemented in ort_shim.js) -- */

EM_JS(void, ort_shim_set_input_data,
      (int handle, const char* name, void* data, int count, int tensorType), {
    return globalThis.ortShimModule.ort_shim_set_input_data(handle, name, data, count, tensorType);
});

EM_JS(int, ort_shim_get_output_names, (int handle, char* outBuf, int maxBuf), {
    return globalThis.ortShimModule.ort_shim_get_output_names(handle, outBuf, maxBuf);
});

EM_JS(size_t, ort_shim_get_audio_ptr, (), {
    return globalThis.ortShimModule._audioHeapPtr || 0;
});

EM_JS(int, ort_shim_get_audio_size, (), {
    return globalThis.ortShimModule._audioSize || 0;
});

/* ort_shim_run triggers inference, copies audio to Emscripten heap,
 * and writes output size to outputSizes. */
/* Store model path for lazy session init */
EM_JS(void, ort_shim_set_model_path, (const char* path), {
    if (globalThis.ortShimModule && globalThis.ortShimModule.setModelPath) {
        globalThis.ortShimModule.setModelPath(path);
    }
});

EM_ASYNC_JS(int, ort_shim_run,
      (int handle, void* outputPtrs, int* outputCounts, int maxOutputs,
       int* outputSizes, int maxSizes), {
    return globalThis.ortShimModule.ort_shim_run(outputSizes, maxSizes);
});

/* Register the Emscripten Module -- called once by ort_shim.js merge */
EM_JS(void, ort_shim_set_module, (), {
    if (globalThis.ortShimModule && globalThis.ortShimModule.setModule) {
        globalThis.ortShimModule.setModule(Module);
    }
});

/* -- Ort namespace -- matches ONNX Runtime C++ API surface used by piper.cpp -- */

enum OrtLoggingLevel {
    ORT_LOGGING_LEVEL_VERBOSE = 0,
    ORT_LOGGING_LEVEL_INFO    = 1,
    ORT_LOGGING_LEVEL_WARNING = 2,
    ORT_LOGGING_LEVEL_ERROR   = 3,
    ORT_LOGGING_LEVEL_FATAL   = 4,
};

enum OrtAllocatorType {
    OrtArenaAllocator        = 0,
    OrtPerArenaAllocator     = 1,
};

enum OrtMemType {
    OrtMemTypeDefault   = 0,
    OrtMemTypeCPUOutput = 1,
    OrtMemTypeCPU       = 2,
};

namespace Ort {

struct Env {
    Env() {}
    Env(int loggingLevel, const char*) {}
};

struct SessionOptions {
    void DisableCpuMemArena()  {}
    void DisableMemPattern()   {}
    void DisableProfiling()    {}
};

struct AllocatorWithDefaultOptions {};

class MemoryInfo {
public:
    static MemoryInfo CreateCpu(int allocatorType, int memType) {
        return MemoryInfo();
    }
};

class TensorTypeAndShapeInfo {
    std::vector<int64_t> shape_;
public:
    TensorTypeAndShapeInfo() : shape_() {}
    TensorTypeAndShapeInfo(const std::vector<int64_t>& shape) : shape_(shape) {}
    const std::vector<int64_t>& GetShape() const { return shape_; }
};

/* -- Value -- wraps input tensor data or ortShim audio buffer -- */

struct Value {
    void* data_;
    int   element_count_;
    std::vector<int64_t> shape_;

    Value() : data_(nullptr), element_count_(0) {}

    template<typename T>
    static Value CreateTensor(MemoryInfo, T* data,
    			 		  size_t count, int64_t* /*shape*/,
    			 		  size_t /*shapeDimCount*/) {
        Value v;
        v.data_ = ::malloc(count * sizeof(T));
        if (v.data_ && data && count > 0) {
            std::memcpy(v.data_, data, count * sizeof(T));
        }
        v.element_count_ = static_cast<int>(count);
        return v;
    }

    template<typename T>
    T* GetTensorData() const {
        /* After Session::Run(), audio data lives in the ortShim Emscripten
         * heap buffer. Return that pointer so piper.cpp reads accessible memory
         * and OrtRelease doesn't corrupt ort.js tensor data. */
        size_t heapPtr = ort_shim_get_audio_ptr();
        if (heapPtr > 0) {
            return reinterpret_cast<T*>(static_cast<uintptr_t>(heapPtr));
        }
        return static_cast<T*>(data_);
    }

    TensorTypeAndShapeInfo GetTensorTypeAndShapeInfo() const {
        return TensorTypeAndShapeInfo(shape_);
    }

    bool IsTensor() const { return data_ != nullptr; }

    void* release() {
        void* p = data_;
        data_ = nullptr;
        return p;
    }

    ~Value() {}
};

struct RunOptions {
    RunOptions() {}
    RunOptions(nullptr_t) {}
};

/* -- Session -- wraps ONNX inference session handle.
 *
 * Session construction is lazy -- no session init happens here.
 * Session initialization happens on first Run() call (lazy init).
 * The Emscripten Module is registered via ort_shim_set_module()
 * called from ort_shim.js during init().
 */

class Session {
    int                  output_count_;
    int                  output_size_arr_[16];
    std::string          model_path_;

public:
    Session(Env, const char* modelPath, SessionOptions&) {
        output_count_ = 0;
        model_path_ = modelPath ? modelPath : "";
        for (int i = 0; i < 16; i++) output_size_arr_[i] = 0;
        /* Register Emscripten Module with ort_shim (idempotent) */
        ort_shim_set_module();
    }

    ~Session() {}

    /* Stub -- real output names not needed by piper.cpp */
    std::vector<std::string> GetOutputNames() {
        return std::vector<std::string>();
    }

    std::vector<Value> Run(
        const RunOptions&,
        const char* const* input_names,
        const Value* input_tensors,
        size_t num_inputs,
        const char* const*,
        size_t)
    {
        /* Debug: log input details */
        /* Batch all input tensors for the next inference call. */
        for (size_t i = 0; i < num_inputs; i++) {
            ort_shim_set_input_data(1, input_names[i],
      	  	  	   input_tensors[i].data_,
      	  	  	   input_tensors[i].element_count_,
      	  	  	   0);
        }

        /* ort_shim_run triggers inference (EM_ASYNC_JS), copies audio
         * from ort.js's separate memory to Emscripten heap, and waits.
         * Session init happens lazily inside ort_shim_run on first call.
         * Audio data is read via EM_JS getters after the call returns. */
        ort_shim_set_model_path(model_path_.c_str());
        ort_shim_run(1, 0, 0, 0, output_size_arr_, 16);
        /* Note: ort_shim_run is EM_ASYNC_JS, C++ execution is suspended until inference completes */
        output_count_ = 1;

        /* Return a Value with audio data from ortShimModule's buffer.
         * This buffer is persistent (allocated once, reused across calls).
         * piper.cpp reads from this Value's GetTensorData<float>(). */
        std::vector<Value> results;
        size_t audioPtrC = ort_shim_get_audio_ptr();
        int audioSizeC = ort_shim_get_audio_size();
        if (audioPtrC && audioSizeC > 0) {
            Value v;
            v.data_ = (void*)audioPtrC;
            v.element_count_ = audioSizeC;
            v.shape_ = {1, (int64_t)audioSizeC};
            results.push_back(std::move(v));
        }
        return results;
    }
};

namespace detail {
    inline void OrtRelease(void*) {}
    inline void OrtRelease(Value) {}
}

} /* namespace Ort */

#endif /* ONNXRUNTIME_CXX_API_H */
