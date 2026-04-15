/**
 * Mock ONNX Runtime implementation (simplified version)
 */

#include "mock_onnxruntime.h"
#include <cstring>
#include <cmath>
#include <algorithm>

namespace MockOrt {

/* Env Implementation */

Env::Env(LoggingLevel level, const std::string& session_name)
    : level_(level), session_name_(session_name) {}

Env& Env::GetInstance() {
    static Env instance(LoggingLevel::LevelWarning, "piper");
    return instance;
}

/* SessionOptions Implementation */
SessionOptions::SessionOptions() = default;

void SessionOptions::DisableCpuMemArena() {
    cpu_mem_arena_disabled = true;
}

void SessionOptions::DisableMemPattern() {
    mem_pattern_disabled = true;
}

void SessionOptions::DisableProfiling() {
    profiling_disabled = true;
}

void SessionOptions::SetIntraOpNumThreads(int num_threads) {
    intra_op_num_threads = num_threads;
}

void SessionOptions::SetGraphOptimizationLevel(int level) {
    graph_optimization_level = level;
}

/* MemoryInfo Implementation */
MemoryInfo MemoryInfo::CreateCpu(OrtAllocatorType allocator_type, OrtMemType mem_type) {
    auto& info = last_created_;
    info.allocator_type_ = allocator_type;
    info.mem_type_ = mem_type;
    return info;
}

MemoryInfo MemoryInfo::CreateCpu(OrtMemType mem_type) {
    return CreateCpu(OrtAllocatorType::OrtArenaAllocator, mem_type);
}

MemoryInfo::MemoryInfo(OrtAllocatorType allocator_type, OrtMemType mem_type)
    : allocator_type_(allocator_type), mem_type_(mem_type) {}

// Initialize static member
MemoryInfo MemoryInfo::last_created_(OrtAllocatorType::OrtCpuMemoryAllocator, OrtMemType::Default);

/* TensorTypeAndShapeInfo Implementation */
TensorTypeAndShapeInfo* TensorTypeAndShapeInfo::last_accessed_ = nullptr;

TensorTypeAndShapeInfo::TensorTypeAndShapeInfo(int64_t* shape, size_t shape_size, int type)
    : element_count_(1), element_type_(static_cast<ONNXTensorElementDataType>(type)) {
    for (size_t i = 0; i < shape_size; i++) {
        shape_.push_back(shape[i]);
        element_count_ *= shape[i];
    }
}

const int64_t* TensorTypeAndShapeInfo::GetShape() const {
    shape_accessed = true;
    if (last_accessed_) last_accessed_->shape_accessed = true;
    return shape_.data();
}

size_t TensorTypeAndShapeInfo::GetShapeElementCount() const {
    element_count_accessed = true;
    if (last_accessed_) last_accessed_->element_count_accessed = true;
    return element_count_;
}

ONNXTensorElementDataType TensorTypeAndShapeInfo::GetElementType() const {
    element_type_accessed = true;
    if (last_accessed_) last_accessed_->element_type_accessed = true;
    return element_type_;
}

/* Value Implementation */
Value Value::CreateTensor_int64_t(const MemoryInfo& memory_info, const int64_t* data,
                                    size_t count, const int64_t* shape, size_t shape_size,
                                    ONNXTensorElementDataType type) {
    Value val;
    val.tensor_type_ = type;
    val.tensor_data_count_ = count;
    val.tensor_shape_.assign(shape, shape + shape_size);

    if (type == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64) {
        std::vector<int> temp_data(count);
        for (size_t i = 0; i < count; i++) {
            temp_data[i] = static_cast<int>(data[i]);
        }
        val.tensor_data_int64_.swap(temp_data);
    }

    GetLastCreatedTensors().push_back(val);
    return val;
}

Value Value::CreateTensor_float(const MemoryInfo& memory_info, const float* data,
                                  size_t count, const int64_t* shape, size_t shape_size) {
    Value val;
    val.tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
    val.tensor_data_count_ = count;
    val.tensor_shape_.assign(shape, shape + shape_size);

    val.tensor_data_float_.assign(data, data + count);

    GetLastCreatedTensors().push_back(val);
    return val;
}

bool Value::IsTensor() const {
    return true;
}

const TensorTypeAndShapeInfo& Value::GetTensorTypeAndShapeInfo() const {
    static TensorTypeAndShapeInfo mock_info(
        const_cast<int64_t*>(tensor_shape_.data()), tensor_shape_.size(),
        static_cast<int>(tensor_type_)
    );
    TensorTypeAndShapeInfo::last_accessed_ = const_cast<TensorTypeAndShapeInfo*>(&mock_info);
    return mock_info;
}

const int64_t* Value::GetTensorData_int64_t() const {
    static std::vector<int64_t> temp_data;
    temp_data.resize(tensor_data_int64_.size());
    for (size_t i = 0; i < tensor_data_int64_.size(); i++) {
        temp_data[i] = static_cast<int64_t>(tensor_data_int64_[i]);
    }
    return temp_data.data();
}

const float* Value::GetTensorData_float() const {
    return tensor_data_float_.data();
}

/* RunOptions Implementation */
RunOptions& RunOptions::GetInstance() {
    static RunOptions instance;
    return instance;
}

RunOptions::RunOptions() = default;

bool RunOptions::IsFlagEnabled(const std::string& flag) const {
    auto it = config_entries_.find(flag);
    return it != config_entries_.end() && !it->second.empty();
}

void RunOptions::SetConfigEntry(const std::string& key, const std::string& value) {
    config_entries_[key] = value;
}

/* Session Implementation */
Session* Session::last_session_ = nullptr;
std::vector<std::vector<Value>> Session::last_run_outputs_ = {};

Session::Session(const Env& env, const std::string& model_path, const SessionOptions& options)
    : model_path_(model_path), options_(options) {
    last_session_ = this;
    // Mock output names - match ONNX Runtime naming convention
    output_names_ = {"onnx::TensorString_Output_0", "onnx::TensorString_Output_1"};
}

std::vector<std::string> Session::GetOutputNames() const {
    get_output_names_call_count_++;
    return output_names_;
}

std::vector<const char*> Session::GetOutputNamesCStr() const {
    get_output_names_cstr_call_count_++;
    std::vector<const char*> names;
    for (const auto& name : output_names_) {
        names.push_back(name.c_str());
    }
    return names;
}

std::vector<std::vector<Value>> Session::Run(const RunOptions& run_options, const char* const* input_names,
                                const Value* input_tensors, size_t num_inputs,
                                const char* const* output_names, size_t num_outputs) {
    run_called = true;
    last_run_outputs_.clear();

    // Check if mock outputs are configured
    if (!mock_output_data_.empty()) {
        for (size_t i = 0; i < mock_output_data_.size(); i++) {
            std::vector<Value> output_vector;
            Value output;
            output.tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
            output.tensor_data_count_ = mock_output_data_[i].size();
            output.tensor_shape_ = mock_output_shapes_[i];
            output.tensor_data_float_ = mock_output_data_[i];
            output_vector.push_back(output);
            last_run_outputs_.push_back(output_vector);
        }
    } else {
        // Return default mock outputs
        // Output 0: audio with 100 samples
        std::vector<float> audio_data(100);
        for (size_t i = 0; i < audio_data.size(); i++) {
            audio_data[i] = std::sin(2 * M_PI * 440.0 * i / 16000.0); // 440Hz sine wave
        }

        std::vector<Value> audio_output_vector;
        Value audio_output;
        audio_output.tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
        audio_output.tensor_data_count_ = audio_data.size();
        audio_output.tensor_shape_ = {1, 100};
        audio_output.tensor_data_float_ = audio_data;
        audio_output_vector.push_back(audio_output);
        last_run_outputs_.push_back(audio_output_vector);

        // Output 1: alignments with 10 alignments
        std::vector<float> alignments_data(10, 256.0f); // hop_length = 256
        std::vector<Value> alignments_output_vector;
        Value alignments_output;
        alignments_output.tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
        alignments_output.tensor_data_count_ = alignments_data.size();
        alignments_output.tensor_shape_ = {1, 10};
        alignments_output.tensor_data_float_ = alignments_data;
        alignments_output_vector.push_back(alignments_output);
        last_run_outputs_.push_back(alignments_output_vector);
    }

    return last_run_outputs_;
}

std::vector<std::vector<Value>> Session::GetLastRunOutputs() {
    return last_run_outputs_;
}

/* Session Helper Function */
std::vector<std::vector<Value>>& GetSessionRunOutputs() {
    return Session::last_run_outputs_;
}

/* Helper Functions for Mock Data Creation */

std::vector<int64_t> create_mock_tensor_data(const std::vector<int>& data) {
    std::vector<int64_t> result;
    result.reserve(data.size());
    for (int value : data) {
        result.push_back(static_cast<int64_t>(value));
    }
    return result;
}

std::vector<float> create_mock_audio_data(size_t sample_count) {
    std::vector<float> audio(sample_count);
    for (size_t i = 0; i < sample_count; i++) {
        audio[i] = std::sin(2 * M_PI * 440.0 * i / 16000.0);
    }
    return audio;
}

std::vector<float> create_mock_alignments_data(size_t alignment_count) {
    std::vector<float> alignments(alignment_count, 256.0f);
    return alignments;
}

/* State Tracking Functions */

void reset_mock_state() {
    // Reset all mock state
    Value::GetLastCreatedTensors().clear();
    Session::last_run_outputs_.clear();
    Session::last_session_ = nullptr;
    if (Session::last_session_) {
        Session::last_session_->get_output_names_call_count_ = 0;
        Session::last_session_->get_output_names_cstr_call_count_ = 0;
    }

    // Reset session options
    SessionOptions session_opts;
    MemoryInfo::last_created_ = MemoryInfo(
        OrtAllocatorType::OrtArenaAllocator,
        OrtMemType::Default
    );
}

int get_tensor_create_call_count() {
    return Value::GetLastCreatedTensors().size();
}

const Value* get_last_created_tensor() {
    const auto& tensors = Value::GetLastCreatedTensors();
    if (tensors.empty()) {
        return nullptr;
    }
    return &tensors.back();
}

const std::vector<std::vector<Value>>* get_last_run_outputs() {
    return &GetSessionRunOutputs();
}

int get_run_call_count() {
    if (Session::last_session_) {
        return Session::last_session_->run_called ? 1 : 0;
    }
    return 0;
}

int get_get_output_names_call_count() {
    if (Session::last_session_) {
        return Session::last_session_->get_output_names_call_count_;
    }
    return 0;
}

int get_get_output_names_cstr_call_count() {
    if (Session::last_session_) {
        return Session::last_session_->get_output_names_cstr_call_count_;
    }
    return 0;
}

void mock_session_set_output_shapes(const std::vector<std::vector<int64_t>>& shapes) {
    if (Session::last_session_) {
        Session::last_session_->mock_output_shapes_ = shapes;
    }
}

void mock_session_set_output_data(const std::vector<std::vector<float>>& data) {
    if (Session::last_session_) {
        Session::last_session_->mock_output_data_ = data;
    }
}

void mock_session_set_single_output(int64_t shape, const float* data, size_t data_size) {
    if (Session::last_session_) {
        Session::last_session_->mock_output_data_.clear();
        Session::last_session_->mock_output_shapes_.clear();

        std::vector<float> mock_data(data, data + data_size);
        Session::last_session_->mock_output_data_.push_back(mock_data);

        std::vector<int64_t> mock_shape = {1, shape};
        Session::last_session_->mock_output_shapes_.push_back(mock_shape);
    }
}

} // namespace MockOrt