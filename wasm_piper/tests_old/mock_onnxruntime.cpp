/**
 * Mock ONNX Runtime implementation (simplified version)
 */

#include "mock_onnxruntime.h"
#include <cmath>

namespace Ort {

Env::Env(LoggingLevel level, const std::string& session_name)
    : level_(level), session_name_(session_name) {}
Env::Env(int level, const std::string& session_name)
    : level_(static_cast<LoggingLevel>(level)), session_name_(session_name) {}
Env::Env() = default;
Env& Env::GetInstance() {
    static Env instance;
    return instance;
}

MemoryInfo MemoryInfo::CreateCpu(int allocator_type, int mem_type) {
    auto& info = last_created_;
    info.allocator_type_ = static_cast<OrtAllocatorType>(allocator_type);
    info.mem_type_ = static_cast<OrtMemType>(mem_type);
    return info;
}
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
MemoryInfo MemoryInfo::last_created_(OrtAllocatorType::OrtCpuMemoryAllocator, OrtMemType::OrtMemTypeDefault);

SessionOptions::SessionOptions() = default;
void SessionOptions::DisableCpuMemArena() { cpu_mem_arena_disabled = true; }
void SessionOptions::DisableMemPattern() { mem_pattern_disabled = true; }
void SessionOptions::DisableProfiling() { profiling_disabled = true; }
void SessionOptions::SetIntraOpNumThreads(int n) { intra_op_num_threads = n; }
void SessionOptions::SetGraphOptimizationLevel(int l) { graph_optimization_level = l; }

TensorTypeAndShapeInfo* TensorTypeAndShapeInfo::last_accessed_ = nullptr;
TensorTypeAndShapeInfo::TensorTypeAndShapeInfo(int64_t* shape, size_t shape_size, int type)
    : element_count_(1), element_type_(static_cast<ONNXTensorElementDataType>(type)) {
    for (size_t i = 0; i < shape_size; i++) { shape_.push_back(shape[i]); element_count_ *= shape[i]; }
}
std::vector<int64_t> TensorTypeAndShapeInfo::GetShape() const {
    shape_accessed = true;
    if (last_accessed_) last_accessed_->shape_accessed = true;
    return shape_;
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

bool Value::IsTensor() const { return true; }
const TensorTypeAndShapeInfo& Value::GetTensorTypeAndShapeInfo() const {
    static TensorTypeAndShapeInfo mock_info(
        const_cast<int64_t*>(tensor_shape_.data()), tensor_shape_.size(),
        static_cast<int>(tensor_type_));
    TensorTypeAndShapeInfo::last_accessed_ = const_cast<TensorTypeAndShapeInfo*>(&mock_info);
    return mock_info;
}

RunOptions::RunOptions() = default;
RunOptions::RunOptions(const SessionOptions*) {}
RunOptions& RunOptions::GetInstance() {
    static RunOptions instance;
    return instance;
}
bool RunOptions::IsFlagEnabled(const std::string& flag) const {
    auto it = config_entries_.find(flag);
    return it != config_entries_.end() && !it->second.empty();
}
void RunOptions::SetConfigEntry(const std::string& key, const std::string& value) {
    config_entries_[key] = value;
}

Session* Session::last_session_ = nullptr;
std::vector<Value> Session::last_run_outputs_ = {};

Session::Session(const Env&, const std::string& model_path, const SessionOptions& options)
    : model_path_(model_path), options_(options) {
    last_session_ = this;
    output_names_ = {"onnx::TensorString_Output_0", "onnx::TensorString_Output_1"};
}
Session::Session(const Session& other)
    : model_path_(other.model_path_), options_(other.options_),
      output_names_(other.output_names_), run_called(other.run_called) {
    if (other.last_session_ == &other) last_session_ = this;
    else last_session_ = other.last_session_;
}
std::vector<std::string> Session::GetOutputNames() const {
    get_output_names_call_count_++;
    return output_names_;
}
std::vector<const char*> Session::GetOutputNamesCStr() const {
    get_output_names_cstr_call_count_++;
    std::vector<const char*> names;
    for (const auto& name : output_names_) names.push_back(name.c_str());
    return names;
}
std::vector<Value> Session::Run(const RunOptions&, const char* const*,
                                 const Value*, size_t,
                                 const char* const*, size_t) {
    run_called = true;
    last_run_outputs_.clear();
    if (!mock_output_data_.empty()) {
        for (size_t i = 0; i < mock_output_data_.size(); i++) {
            Value output;
            output.tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
            output.tensor_data_count_ = mock_output_data_[i].size();
            output.tensor_shape_ = mock_output_shapes_[i];
            output.tensor_data_float_ = mock_output_data_[i];
            last_run_outputs_.push_back(output);
        }
    } else {
        // Cache default 440Hz sine wave to avoid recomputing on every call
        static std::vector<float> default_audio = []() {
            std::vector<float> audio_data(100);
            for (size_t i = 0; i < audio_data.size(); i++)
                audio_data[i] = std::sin(2 * M_PI * 440.0 * i / 16000.0);
            return audio_data;
        }();
        Value audio_out;
        audio_out.tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
        audio_out.tensor_data_count_ = default_audio.size();
        audio_out.tensor_shape_ = {1, 100};
        audio_out.tensor_data_float_ = default_audio;
        last_run_outputs_.push_back(audio_out);
        static std::vector<float> default_align(10, 256.0f);
        Value align_out;
        align_out.tensor_type_ = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
        align_out.tensor_data_count_ = default_align.size();
        align_out.tensor_shape_ = {1, 10};
        align_out.tensor_data_float_ = default_align;
        last_run_outputs_.push_back(align_out);
    }
    return last_run_outputs_;
}
std::vector<Value> Session::GetLastRunOutputs() { return last_run_outputs_; }

std::vector<int64_t> create_mock_tensor_data(const std::vector<int>& data) {
    std::vector<int64_t> r; r.reserve(data.size());
    for (int v : data) r.push_back(static_cast<int64_t>(v));
    return r;
}
std::vector<float> create_mock_audio_data(size_t n) {
    std::vector<float> a(n);
    for (size_t i = 0; i < n; i++) a[i] = std::sin(2 * M_PI * 440.0 * i / 16000.0);
    return a;
}
std::vector<float> create_mock_alignments_data(size_t n) {
    return std::vector<float>(n, 256.0f);
}
void reset_mock_state() {
    Value::GetLastCreatedTensors().clear();
    Session::last_run_outputs_.clear();
    Session::last_session_ = nullptr;
    MemoryInfo::last_created_ = MemoryInfo(OrtAllocatorType::OrtArenaAllocator, OrtMemType::OrtMemTypeDefault);
}
int get_tensor_create_call_count() { return Value::GetLastCreatedTensors().size(); }
const Value* get_last_created_tensor() {
    const auto& t = Value::GetLastCreatedTensors();
    return t.empty() ? nullptr : &t.back();
}
const std::vector<Value>* get_last_run_outputs() { return &Session::last_run_outputs_; }
int get_run_call_count() {
    return Session::last_session_ ? Session::last_session_->run_called ? 1 : 0 : 0;
}
int get_get_output_names_call_count() {
    return Session::last_session_ ? Session::last_session_->get_output_names_call_count_ : 0;
}
int get_get_output_names_cstr_call_count() {
    return Session::last_session_ ? Session::last_session_->get_output_names_cstr_call_count_ : 0;
}
void mock_session_set_output_shapes(const std::vector<std::vector<int64_t>>& s) {
    if (Session::last_session_) Session::last_session_->mock_output_shapes_ = s;
}
void mock_session_set_output_data(const std::vector<std::vector<float>>& d) {
    if (Session::last_session_) Session::last_session_->mock_output_data_ = d;
}
void mock_session_set_single_output(int64_t shape, const float* data, size_t data_size) {
    if (Session::last_session_) {
        Session::last_session_->mock_output_data_.push_back(std::vector<float>(data, data + data_size));
        Session::last_session_->mock_output_shapes_.push_back({1, shape});
    }
}

} // namespace Ort

/* GetTensorData explicit specializations */
template <>
const int64_t* Ort::Value::GetTensorData<int64_t>() const { return tensor_data_int64_.data(); }
template <>
const float* Ort::Value::GetTensorData<float>() const { return tensor_data_float_.data(); }
