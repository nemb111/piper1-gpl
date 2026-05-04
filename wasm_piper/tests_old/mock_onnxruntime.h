/**
 * Mock ONNX Runtime C++ API for testing
 *
 * Provides minimal mock implementations of ONNX Runtime classes
 * that match the real API surface used by piper.cpp.
 */

#ifndef MOCK_ONNXRUNTIME_H_
#define MOCK_ONNXRUNTIME_H_

#include <memory>
#include <vector>
#include <string>
#include <map>
#include <cstdint>
#include <cstddef>
#include <type_traits>

// ONNX constants matching real API
#define ORT_API_NAMESPACE
#define ORT_CXX_API_NAMESPACE Ort
#define ORT_LOGGING_LEVEL_WARNING 3
#define ORT_USE_STATIC_LOGGER 0

namespace Ort {

enum ONNXTensorElementDataType {
    ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT = 1,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64 = 7,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32 = 6,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8 = 0,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL = 11
};

enum class LoggingLevel {
    Level0 = 0, Level1 = 1, Level2 = 2, Level3 = 3, Level4 = 4,
    LevelWarning = 3, LevelError = 4
};

enum class OrtAllocatorType {
    OrtArenaAllocator,
    OrtCpuMemoryAllocator,
    OrtDeviceMemAllocator
};

enum class OrtMemType {
    OrtMemTypeDefault = 0,
    OrtMemTypePreallocated = 1,
    OrtMemTypeArena = 2
};

/* Env */
class Env {
public:
    Env(LoggingLevel level, const std::string& session_name);
    Env(int level, const std::string& session_name);
    Env();
    Env(const Env&) = delete;
    Env& operator=(const Env&) = delete;
    static Env& GetInstance();
    LoggingLevel GetLevel() const { return level_; }
    const std::string& GetSessionName() const { return session_name_; }
private:
    LoggingLevel level_;
    std::string session_name_;
};

/* SessionOptions */
class SessionOptions {
public:
    SessionOptions();
    SessionOptions(const SessionOptions&) = default;
    SessionOptions& operator=(const SessionOptions&) = default;
    void DisableCpuMemArena();
    void DisableMemPattern();
    void DisableProfiling();
    void SetIntraOpNumThreads(int num_threads);
    void SetGraphOptimizationLevel(int level);
    bool cpu_mem_arena_disabled = false;
    bool mem_pattern_disabled = false;
    bool profiling_disabled = false;
    int intra_op_num_threads = 1;
    int graph_optimization_level = 1;
};

/* MemoryInfo */
class MemoryInfo {
public:
    static MemoryInfo CreateCpu(int allocator_type, int mem_type);
    static MemoryInfo CreateCpu(OrtAllocatorType allocator_type, OrtMemType mem_type);
    static MemoryInfo CreateCpu(OrtMemType mem_type);
    MemoryInfo() = default;
    MemoryInfo(OrtAllocatorType allocator_type, OrtMemType mem_type);
    MemoryInfo(const MemoryInfo&) = default;
    MemoryInfo(MemoryInfo&&) = default;
    MemoryInfo& operator=(const MemoryInfo&) = default;
    MemoryInfo& operator=(MemoryInfo&&) = default;
    OrtAllocatorType GetAllocatorType() const { return allocator_type_; }
    OrtMemType GetMemoryType() const { return mem_type_; }
    static MemoryInfo& GetLastCreated() { return last_created_; }
private:
public:
    OrtAllocatorType allocator_type_{};
    OrtMemType mem_type_{};
    static MemoryInfo last_created_;
};

/* TensorTypeAndShapeInfo */
class TensorTypeAndShapeInfo {
public:
    TensorTypeAndShapeInfo(int64_t* shape, size_t shape_size, int type);
    TensorTypeAndShapeInfo(const TensorTypeAndShapeInfo&) = delete;
    std::vector<int64_t> GetShape() const;
    size_t GetShapeElementCount() const;
    ONNXTensorElementDataType GetElementType() const;
    mutable bool shape_accessed = false;
    mutable bool element_count_accessed = false;
    mutable bool element_type_accessed = false;
    static TensorTypeAndShapeInfo* GetLastAccessed() { return last_accessed_; }
private:
public:
    std::vector<int64_t> shape_;
    size_t element_count_ = 1;
    ONNXTensorElementDataType element_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
    static TensorTypeAndShapeInfo* last_accessed_;
};

/* Value */
class Value {
public:
    Value() = default;
    friend class Session;

    template <typename T>
    static Value CreateTensor(const MemoryInfo& /*memory_info*/, const T* data,
                              size_t count, const int64_t* shape, size_t shape_size,
                              ONNXTensorElementDataType type = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
        Value val;
        val.tensor_type_ = (type != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) ? type : ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
        val.tensor_data_count_ = count;
        val.tensor_shape_.assign(shape, shape + shape_size);
        fill_tensor_data(val, data, count, std::is_same<T, int64_t>{});
        GetLastCreatedTensors().push_back(val);
        return val;
    }
    bool IsTensor() const;
    const TensorTypeAndShapeInfo& GetTensorTypeAndShapeInfo() const;
    template <typename T>
    const T* GetTensorData() const;
    const int64_t* GetTensorData_int64_t() const { return tensor_data_int64_.data(); }
    const float* GetTensorData_float() const { return tensor_data_float_.data(); }

    static Value CreateTensor_int64_t(const MemoryInfo& mi, const int64_t* data,
        size_t count, const int64_t* shape, size_t shape_size,
        ONNXTensorElementDataType type = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64) {
        return CreateTensor(mi, data, count, shape, shape_size, type);
    }
    static Value CreateTensor_float(const MemoryInfo& mi, const float* data,
        size_t count, const int64_t* shape, size_t shape_size,
        ONNXTensorElementDataType type = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
        return CreateTensor(mi, data, count, shape, shape_size, type);
    }
    void* release() { return nullptr; }

    static std::vector<Value>& GetLastCreatedTensors() {
        static std::vector<Value> last_created;
        return last_created;
    }

    int64_t tensor_data_count_ = 0;
    ONNXTensorElementDataType tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
    std::vector<int64_t> tensor_shape_;
    std::vector<int64_t> tensor_data_int64_;
    std::vector<float> tensor_data_float_;
private:
    template <typename T>
    static typename std::enable_if<std::is_same<T, int64_t>::value, void>::type
    fill_tensor_data(Value& val, const T* data, size_t count, std::true_type) {
        val.tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64;
        std::vector<int64_t> temp(count);
        for (size_t i = 0; i < count; i++) temp[i] = data[i];
        val.tensor_data_int64_ = temp;
    }
    template <typename T>
    static typename std::enable_if<!std::is_same<T, int64_t>::value, void>::type
    fill_tensor_data(Value& val, const T* data, size_t count, std::false_type) {
        val.tensor_data_float_.assign(reinterpret_cast<const float*>(data),
                                      reinterpret_cast<const float*>(data) + count);
    }
};

/* RunOptions */
class RunOptions {
public:
    RunOptions();
    RunOptions(const SessionOptions* parent);
    RunOptions(const RunOptions&) = delete;
    static RunOptions& GetInstance();
    bool IsFlagEnabled(const std::string& flag) const;
    void SetConfigEntry(const std::string& key, const std::string& value);
    std::map<std::string, std::string> config_entries_;
};

/* Session */
class Session {
public:
    Session(const Env& env, const std::string& model_path, const SessionOptions& options);
    Session(const Session& other);
    Session& operator=(const Session&) = default;
    std::vector<std::string> GetOutputNames() const;
    std::vector<const char*> GetOutputNamesCStr() const;
    std::vector<Value> Run(const RunOptions& run_options, const char* const* input_names,
                           const Value* input_tensors, size_t num_inputs,
                           const char* const* output_names, size_t num_outputs);
    std::string model_path_;
    SessionOptions options_;
    std::vector<std::string> output_names_;
    bool run_called = false;
    static Session* last_session_;
    static std::vector<Value> last_run_outputs_;
    std::vector<std::vector<int64_t>> mock_output_shapes_;
    std::vector<std::vector<float>> mock_output_data_;
    static Session* GetLastSession() { return last_session_; }
    static std::vector<Value> GetLastRunOutputs();
    mutable int get_output_names_call_count_ = 0;
    mutable int get_output_names_cstr_call_count_ = 0;
};

/* AllocatorWithDefaultOptions */
class AllocatorWithDefaultOptions {};

namespace detail {
    inline void OrtRelease(void*) {}
}

/* Helper functions */
std::vector<int64_t> create_mock_tensor_data(const std::vector<int>& data);
std::vector<float> create_mock_audio_data(size_t sample_count);
std::vector<float> create_mock_alignments_data(size_t alignment_count);
void reset_mock_state();
int get_tensor_create_call_count();
int get_run_call_count();
int get_get_output_names_call_count();
int get_get_output_names_cstr_call_count();
const Value* get_last_created_tensor();
const std::vector<Value>* get_last_run_outputs();
void mock_session_set_output_shapes(const std::vector<std::vector<int64_t>>& shapes);
void mock_session_set_output_data(const std::vector<std::vector<float>>& data);
void mock_session_set_single_output(int64_t shape, const float* data, size_t data_size);

} // namespace Ort

#endif /* MOCK_ONNXRUNTIME_H_ */
