/**
 * Include MockOrt as Ort namespace for compilation testing
 *
 * This file makes MockOrt classes accessible under the Ort namespace,
 * allowing the code to compile without the actual ONNX Runtime library.
 */

#ifndef ORT_NAMESPACE_HPP
#define ORT_NAMESPACE_HPP

// Include the mock header
#include "mock_onnxruntime.h"

// Ort namespace with constants (for compatibility)
namespace Ort {
    constexpr int ORT_LOGGING_LEVEL_VERBOSE = 0;
    constexpr int ORT_LOGGING_LEVEL_WARNING = 3;
    constexpr int ORT_LOGGING_LEVEL_ERROR = 4;
}

// Ort namespace with typedef for AllocatorWithDefaultOptions
namespace Ort {
    using AllocatorWithDefaultOptions = MockOrt::MemoryInfo;
}

// Ort namespace with using declarations for MockOrt classes
namespace Ort {
    using MockOrt::Env;
    using MockOrt::SessionOptions;
    using MockOrt::Session;
    using MockOrt::Value;
    using MockOrt::MemoryInfo;
    using MockOrt::RunOptions;
}

// Ort namespace: detail::OrtRelease
namespace Ort {
    namespace detail {
        inline void OrtRelease(void*) {}
    }
}

// Ort namespace enum class definitions (using MockOrt)
namespace Ort {
    enum OrtAllocatorType {
        OrtArenaAllocator = static_cast<int>(MockOrt::OrtAllocatorType::OrtArenaAllocator),
        OrtCpuMemoryAllocator = static_cast<int>(MockOrt::OrtAllocatorType::OrtCpuMemoryAllocator),
        OrtDeviceMemAllocator = static_cast<int>(MockOrt::OrtAllocatorType::OrtDeviceMemAllocator)
    };

    enum OrtMemType {
        OrtMemTypeDefault = static_cast<int>(MockOrt::OrtMemType::Default),
        OrtMemTypePreallocated = static_cast<int>(MockOrt::OrtMemType::Preallocated),
        OrtMemTypeArena = static_cast<int>(MockOrt::OrtMemType::Arena),
        Default = OrtMemTypeDefault,
        Preallocated = OrtMemTypePreallocated,
        Arena = OrtMemTypeArena
    };
}

// Using declarations to make Ort constants accessible in global namespace
using Ort::ORT_LOGGING_LEVEL_VERBOSE;
using Ort::ORT_LOGGING_LEVEL_WARNING;
using Ort::ORT_LOGGING_LEVEL_ERROR;
using Ort::OrtAllocatorType;
using Ort::OrtMemType;

#endif /* ORT_NAMESPACE_HPP */
