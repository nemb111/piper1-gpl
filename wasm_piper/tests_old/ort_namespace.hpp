/**
 * Include MockOrt as Ort namespace for compilation testing
 *
 * This file provides definitions missing from mock_onnxruntime.h
 * that are needed by piper code compiled against mocks.
 */

#ifndef ORT_NAMESPACE_HPP
#define ORT_NAMESPACE_HPP

// Include the mock header (provides Ort::Env, Session, Value, etc.)
#include "mock_onnxruntime.h"

#endif /* ORT_NAMESPACE_HPP */
