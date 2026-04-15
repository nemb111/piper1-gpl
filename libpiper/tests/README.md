# Piper Test Suite

This directory contains mock implementations, test suites, and documentation for testing libpiper without requiring actual espeak-ng or ONNX Runtime installations.

## Overview

The test suite provides comprehensive testing infrastructure including:
- **Mock implementations**: Exact API interfaces for espeak-ng and ONNX Runtime
- **Google Test suite**: 23 tests covering all mock APIs
- **Modular CMake structure**: Easy integration and compile-time verification
- **Complete documentation**: Usage guides and examples

## Directory Contents

### Mock Libraries
- **mock_espeak_ng.h/cpp** - Mock implementations of espeak-ng API
- **mock_onnxruntime.h/cpp** - Mock implementations of ONNX Runtime API

### Documentation
- **EXTERNAL_API_CALLS.md** - Complete list of all external API calls with locations in source code
- **TEST_USAGE.md** - Comprehensive guide on how to use the mocks for testing

### Examples
- **mock_example.cpp** - Working example demonstrating mock usage
- **test_simple.cpp** - Comprehensive Google Test (GTest) test suite (23 tests covering all mock APIs)

### Build Configuration
- **CMakeLists.txt** - CMake configuration for building with mocks and Google Test

## Quick Start

### Building and Running Tests

```bash
cd libpiper
mkdir build && cd build
cmake ..
make -j$(nproc)

# Run all tests
./tests/test_simple

# Run specific test
./tests/test_simple --gtest_filter=MockOrt_SessionTest
```

### Using Mocks in Your Tests

1. Include the mock headers in your test code:
```cpp
#include "piper.h"
#include "mock_espeak_ng.h"
#include "mock_onnxruntime.h"
```

2. Reset mock state before each test:
```cpp
mock_espeak_reset();
MockOrt::reset_mock_state();
```

3. Use mock functions to customize behavior and verify calls

## Key Features

### espeak-ng Mocks
- Track all API calls (initialize, set voice, text-to-phonemes, terminate)
- Simulate errors
- Customize phoneme output
- Verify correct parameters

### onnxruntime Mocks
- Track all API calls (session creation, tensor creation, inference, cleanup)
- Track tensor shapes and types
- Configure mock output data
- Verify correct configuration

## Usage Examples

See **mock_example.cpp** for complete working examples covering:
- Basic initialization
- Custom phoneme output
- Error simulation
- Tensor creation tracking
- Session configuration
- Mock output configuration
- Multiple syntheses
- Error handling

## Building Tests

The test directory includes a modular CMake configuration. The main CMakeLists.txt in the parent directory handles the build automatically:

```bash
cd libpiper
mkdir build && cd build
cmake ..
make -j$(nproc)
```

The modular structure provides:
- **test_simple**: Google Test executable with 23 tests
- **mock_espeak_ng**: Static library for espeak-ng mock
- **mock_onnxruntime**: Static library for ONNX Runtime mock

### Compile-Time API Verification

The modular structure enables **compile-time API verification**:

1. Build with mocks (current state)
2. Swap mock libraries with real implementations:
   - Replace `libmock_espeak_ng.a` with `libespeak-ng.a`
   - Replace `libmock_onnxruntime.a` with `onnxruntime.so`
3. Rebuild - successful compilation = API compatibility verified

See [TEST_USAGE.md](TEST_USAGE.md) for detailed documentation.

## Testing Strategy

The mocks enable:
- **Unit testing** - Test piper functions in isolation
- **API verification** - Ensure correct external calls
- **Error testing** - Test error conditions without real libraries
- **Performance testing** - No overhead from actual library loading

## Related Files

- **../src/piper.cpp** - Implementation being tested
- **../include/piper_impl.hpp** - Internal implementation details
- **../include/piper.h** - Public API header

## Dependencies

None - These are pure C++ mock implementations that work with standard C++17.

## License

See root project LICENSE file.