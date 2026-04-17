/**
 * Mock ONNX Runtime API for testing
 *
 * This file provides mock implementations of ONNX Runtime C++ API that can be
 * used in unit tests without requiring a full ONNX Runtime installation.
 */

#ifndef MOCK_ONNXRUNTIME_H_
#define MOCK_ONNXRUNTIME_H_

#include <memory>
#include <vector>
#include <string>
#include <map>
#include <functional>
#include <cstdint>
#include <cstddef>
#include <type_traits>

// ONNX Tensor Element Data Type enum
enum ONNXTensorElementDataType {
    ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT = 1,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64 = 7,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32 = 6,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8 = 0,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL = 11
};

/**
 * Mock ONNX Runtime API namespace
 */
namespace MockOrt {

/**
 * Environment logging level
 */
enum class LoggingLevel {
    Level0 = 0,
    Level1 = 1,
    Level2 = 2,
    Level3 = 3,
    Level4 = 4,
    LevelWarning = 3,
    LevelError = 4
};

/**
 * Allocator type
 */
enum class OrtAllocatorType {
    OrtArenaAllocator,
    OrtCpuMemoryAllocator,
    OrtDeviceMemAllocator
};

/**
 * Memory type
 */
enum class OrtMemType {
    Default,
    Preallocated,
    Arena
};

// Aliases for ONNX Runtime compatibility (enum values)
constexpr auto OrtMemTypeDefault = MockOrt::OrtMemType::Default;
constexpr auto OrtMemTypePreallocated = MockOrt::OrtMemType::Preallocated;
constexpr auto OrtMemTypeArena = MockOrt::OrtMemType::Arena;

/**
 * Mock Environment
 */
class Env {
public:
    Env(LoggingLevel level, const std::string& session_name);
    Env(int level, const std::string& session_name);
    Env() = default;
    Env(const Env&) = delete;
    Env& operator=(const Env&) = delete;

    static Env& GetInstance();

    LoggingLevel GetLevel() const { return level_; }
    std::string GetSessionName() const { return session_name_; }

private:
    LoggingLevel level_;
    std::string session_name_;
};

/**
 * Mock Session Options
 */
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

    // Track configuration calls
    bool cpu_mem_arena_disabled = false;
    bool mem_pattern_disabled = false;
    bool profiling_disabled = false;
    int intra_op_num_threads = 1;
    int graph_optimization_level = 1;
};

/**
 * Mock Memory Info
 */
class MemoryInfo;

/**
 * Mock Memory Info
 */
class MemoryInfo {
public:
    static MemoryInfo CreateCpu(int allocator_type, int mem_type);
    static MemoryInfo CreateCpu(OrtMemType mem_type);
    MemoryInfo() = default;
    MemoryInfo(OrtAllocatorType allocator_type, OrtMemType mem_type);
    MemoryInfo(const MemoryInfo&) = default;
    MemoryInfo(MemoryInfo&&) = default;
    MemoryInfo& operator=(const MemoryInfo&) = default;
    MemoryInfo& operator=(MemoryInfo&&) = default;

    OrtAllocatorType GetAllocatorType() const { return allocator_type_; }
    OrtMemType GetMemoryType() const { return mem_type_; }

    // Track creation
    static MemoryInfo& GetLastCreated() { return last_created_; }

private:
    OrtAllocatorType allocator_type_;
    OrtMemType mem_type_;
    static MemoryInfo last_created_;  // Static member declared here
};

/**
 * Mock Tensor Type and Shape Info
 */
class TensorTypeAndShapeInfo {
public:
    TensorTypeAndShapeInfo(int64_t* shape, size_t shape_size, int type);
    TensorTypeAndShapeInfo(const TensorTypeAndShapeInfo&) = delete;

    std::vector<int64_t> GetShape() const;
    size_t GetShapeElementCount() const;
    ONNXTensorElementDataType GetElementType() const;

    // Track access
    mutable bool shape_accessed = false;
    mutable bool element_count_accessed = false;
    mutable bool element_type_accessed = false;
    static TensorTypeAndShapeInfo* GetLastAccessed() { return last_accessed_; }

public:
    std::vector<int64_t> shape_;
    size_t element_count_;
    ONNXTensorElementDataType element_type_;
    static TensorTypeAndShapeInfo* last_accessed_;

private:
};

/**
 * Mock Value (tensor)
 */
class Value {
public:
    // CreateTensor overloads
    static Value CreateTensor_int64_t(const MemoryInfo& memory_info, const int64_t* data,
                                      size_t count, const int64_t* shape, size_t shape_size,
                                      ONNXTensorElementDataType type);
    static Value CreateTensor_float(const MemoryInfo& memory_info, const float* data,
                                     size_t count, const int64_t* shape, size_t shape_size);

    // Template CreateTensor matching real ONNX Runtime API
    template <typename T>
    static Value CreateTensor(const MemoryInfo& memory_info, const T* data,
                              size_t count, const int64_t* shape, size_t shape_size,
                              ONNXTensorElementDataType type = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
        Value val;
        val.tensor_type_ = (type != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) ? type : ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
        val.tensor_data_count_ = count;
        val.tensor_shape_.assign(shape, shape + shape_size);
        if constexpr (std::is_same_v<T, int64_t>) {
            val.tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64;
            std::vector<int> temp_data(count);
            for (size_t i = 0; i < count; i++) temp_data[i] = static_cast<int>(data[i]);
            val.tensor_data_int64_.swap(temp_data);
        } else {
            val.tensor_data_float_.assign(reinterpret_cast<const float*>(data),
                                          reinterpret_cast<const float*>(data) + count);
        }
        GetLastCreatedTensors().push_back(val);
        return val;
    }

    bool IsTensor() const;
    const TensorTypeAndShapeInfo& GetTensorTypeAndShapeInfo() const;

    // Get tensor data pointer
    const int64_t* GetTensorData_int64_t() const;
    const float* GetTensorData_float() const;

    // Template GetTensorData matching real ONNX Runtime API
    template <typename T>
    const T* GetTensorData() const {
        if constexpr (std::is_same_v<T, int64_t>) {
            return reinterpret_cast<const int64_t*>(tensor_data_int64_.data());
        } else {
            return reinterpret_cast<const T*>(tensor_data_float_.data());
        }
    }

    // release() for Ort::detail::OrtRelease
    void* release() { return nullptr; }

    // Track tensor creation and access
    int64_t tensor_data_count_ = 0;
    ONNXTensorElementDataType tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
    std::vector<int64_t> tensor_shape_;
    std::vector<int> tensor_data_int64_;
    std::vector<float> tensor_data_float_;

    static std::vector<Value>& GetLastCreatedTensors() {
        static std::vector<Value> last_created;
        return last_created;
    }

public:
    Value() = default;
    friend class MockOrt;
};

/**
 * Mock Run Options
 */
class RunOptions {
public:
    RunOptions();
    RunOptions(const SessionOptions* parent);
    RunOptions(const RunOptions&) = delete;

    static RunOptions& GetInstance();

    bool IsFlagEnabled(const std::string& flag) const;
    void SetConfigEntry(const std::string& key, const std::string& value);

    // Track configuration
    std::map<std::string, std::string> config_entries_;
};

/**
 * Mock Session
 */
class Session {
public:
    Session(const Env& env, const std::string& model_path, const SessionOptions& options);
    Session(const Session& other);
    Session& operator=(const Session&) = default;

    std::vector<std::string> GetOutputNames() const;
    std::vector<const char*> GetOutputNamesCStr() const;

    // Track GetOutputNames call count
    mutable int get_output_names_call_count_ = 0;
    mutable int get_output_names_cstr_call_count_ = 0;

    // Run inference
    std::vector<Value> Run(const RunOptions& run_options, const char* const* input_names,
                           const Value* input_tensors, size_t num_inputs,
                           const char* const* output_names, size_t num_outputs);

    // Track session creation and usage
    std::string model_path_;
    SessionOptions options_;
    std::vector<std::string> output_names_;
    bool run_called = false;

public:
    static Session* last_session_;
    static std::vector<Value> last_run_outputs_;

    // Mock output configuration
    std::vector<std::vector<int64_t>> mock_output_shapes_;
    std::vector<std::vector<float>> mock_output_data_;

    static Session* GetLastSession() { return last_session_; }
    static std::vector<Value> GetLastRunOutputs();
};

/**
 * Helper functions for creating mock data
 */

/**
 * Create mock tensor data
 */
std::vector<int64_t> create_mock_tensor_data(const std::vector<int>& data);

std::vector<float> create_mock_audio_data(size_t sample_count);

std::vector<float> create_mock_alignments_data(size_t alignment_count);

/**
 * Track function calls for testing
 */

/**
 * Reset all mock state
 */
void reset_mock_state();

/**
 * Get call count for a function
 */
int get_tensor_create_call_count();
int get_run_call_count();
int get_get_output_names_call_count();
int get_get_output_names_cstr_call_count();

/**
 * Get last tensor created
 */
const Value* get_last_created_tensor();
const std::vector<Value>* get_last_run_outputs();

/**
 * Configure mock session to return specific outputs
 */
void mock_session_set_output_shapes(const std::vector<std::vector<int64_t>>& shapes);
void mock_session_set_output_data(const std::vector<std::vector<float>>& data);
void mock_session_set_single_output(int64_t shape, const float* data, size_t data_size);

} // namespace MockOrt

#endif /* MOCK_ONNXRUNTIME_H_ */