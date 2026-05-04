/**
 * onnxruntime_cxx_api.h — ONNX Runtime C++ API shim for Emscripten/WASM.
 *
 * Implements the Ort namespace used by piper.cpp by forwarding calls
 * to onnxruntime-web via EM_JS functions defined in ort_shim.js.
 *
 * Session initialization is done externally by JS: call ort_shim_init()
 * before creating any Ort::Session. The Session constructor reads the
 * pre-created handle via EM_JS (ort_shim_get_session_handle).
 *
 * This file replaces the real onnxruntime_cxx_api.h so that
 * piper_impl.hpp's #include <onnxruntime_cxx_api.h> resolves to the shim
 * in WASM builds. Only the Ort namespace is defined here; piper_impl.hpp
 * provides the rest (typedefs, constants, macros).
 */
#ifndef ONNXRUNTIME_CXX_API_H
#define ONNXRUNTIME_CXX_API_H

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include <emscripten.h>

/* ── EM_JS declarations (implemented in ort_shim.js) ── */

/* malloc/free from Emscripten runtime */
#include <cstdlib>

/* EM_ASYNC_JS: initialize ONNX session (called from JS before piper_create) */
EM_ASYNC_JS(int, ort_shim_init, (const char* modelPathUTF8), {
    var modelPath = UTF8ToString(modelPathUTF8);
    await Module.ortShimModule.ort_shim_init(modelPath);
    return 0;
});

/* EM_JS: read session handle set by ort_shim_init */
EM_JS(int, ort_shim_get_session_handle, (), {
    return Module._ortShimSessionHandle || 0;
});

/* EM_JS: write output names (null-separated) to buffer */
EM_JS(int, ort_shim_get_output_names, (int handle, char* outBuf, int maxBuf), {
    return Module.ortShimModule.ort_shim_get_output_names(handle, outBuf, maxBuf);
});

/* EM_JS: register input tensor data (JS reads from WASM heap) */
EM_JS(void, ort_shim_set_input_data,
      (int handle, const char* name, void* data, int count, int tensorType), {
    return Module.ortShimModule.ort_shim_set_input_data(handle, name, data, count, tensorType);
});

/* ort_shim_run - synchronous. Reads inference results if ready, returns count.
 * If inference not ready, returns 0. JS wrapper handles async inference flow. */
EM_JS(int, ort_shim_run,
      (int handle, void* outputPtrs, int* outputCounts, int maxOutputs,
       int* outputSizes, int maxSizes), {
    if (Module.ortShimModule._inferenceReady) {
        return Module.ortShimModule.pollRun(
            outputPtrs, outputCounts, maxOutputs, outputSizes, maxSizes);
    }
    return 0;
});

/* ort_shim_run_async - async version for when inference is not yet ready.
 * Waits for inference to complete, writes results, returns count.
 * All async logic is inline (inside EM_ASYNC_JS) for correct Asyncify behavior. */
EM_ASYNC_JS(int, ort_shim_run_async,
            (int handle, void* outputPtrs, int* outputCounts, int maxOutputs,
             int* outputSizes, int maxSizes), {
    /* Wait for inference to complete */
    if (Module.ortShimModule._inferenceRunning) {
        await Module.ortShimModule._inferencePromise;
    }
    /* Write results to heap */
    if (Module.ortShimModule._inferenceReady) {
        return Module.ortShimModule.pollRun(
            outputPtrs, outputCounts, maxOutputs, outputSizes, maxSizes);
    }
    return 0;
});

/* ── Ort namespace — matches ONNX Runtime C++ API surface used by piper.cpp ── */

/* Global enums (piper_impl.hpp uses these unqualified) */
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

/* ── Value — wraps WASM heap pointer to tensor data ── */

struct Value {
    void* data_;
    int   element_count_;  /* number of elements for ort_shim_set_input_data */

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
        return static_cast<T*>(data_);
    }

    TensorTypeAndShapeInfo GetTensorTypeAndShapeInfo() const {
        if (!data_) return TensorTypeAndShapeInfo();
        return TensorTypeAndShapeInfo();
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

/* ── Session — wraps ONNX inference session handle ── */

class Session {
    int                  handle_;
    int                  output_count_;
    int                  output_size_arr_[16];
    char*                output_names_buf_;
    void*                output_ptr_arr_[16];
    int                  output_count_arr_[16];
    std::vector<std::string> output_names_;

public:
    Session(Env, const char*, SessionOptions&)
        : handle_(ort_shim_get_session_handle()),
          output_count_(0) {
        const size_t kOutputSize = 32ULL * 1024 * 1024;
        output_names_buf_ = new char[1024];
        for (int i = 0; i < 16; i++) {
            output_ptr_arr_[i] = ::malloc(kOutputSize);
            output_count_arr_[i] = 0;
            output_size_arr_[i] = 0;
        }
    }

    ~Session() {
        const size_t kOutputSize = 32ULL * 1024 * 1024;
        for (int i = 0; i < output_count_ && i < 16; i++) {
            ::free(output_ptr_arr_[i]);
        }
        if (output_names_buf_) delete[] output_names_buf_;
    }

    std::vector<std::string> GetOutputNames() {
        if (output_names_.empty()) {
            int count = ort_shim_get_output_names(handle_, output_names_buf_, 1024);
            char* p = output_names_buf_;
            for (int i = 0; i < count && *p; i++) {
                output_names_.push_back(std::string(p));
                p += static_cast<int>(output_names_.back().size() + 1);
            }
            output_count_ = count;
        }
        return output_names_;
    }

    std::vector<Value> Run(
        const RunOptions&,
        const char* const* input_names,
        const Value* input_tensors,
        size_t num_inputs,
        const char* const*,
        size_t)
    {
        fprintf(stderr, "[Session::Run] handle=%d num_inputs=%zu\n", handle_, num_inputs);
        for (size_t i = 0; i < num_inputs; i++) {
            ort_shim_set_input_data(handle_, input_names[i],
                                    input_tensors[i].data_,
                                    input_tensors[i].element_count_,
                                    0);
        }

        int actual_count = ort_shim_run(handle_,
                                        reinterpret_cast<char*>(output_ptr_arr_),
                                        output_count_arr_,
                                        16,
                                        output_size_arr_,
                                        16);
        output_count_ = actual_count;
        fprintf(stderr, "[Session::Run] actual_count=%d\n", actual_count);

        std::vector<Value> results;
        for (int i = 0; i < actual_count; i++) {
            Value v;
            v.data_ = output_ptr_arr_[i];
            v.element_count_ = output_size_arr_[i];
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
