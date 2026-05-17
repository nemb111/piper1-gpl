"""Shared configuration for divergence tests.

All paths used by setup.py and test_divergence.py live here.
Call refresh(voice) after changing the voice to recompute voice-dependent paths.
"""

import os
from pathlib import Path

# ──────────────────────────────────────────────────────────────────────────────
# Repository layout
# ──────────────────────────────────────────────────────────────────────────────

# Directory containing this config module (tests/divergence_tests/).
# Used as the anchor for all other relative paths in this package.
DIR = Path(__file__).resolve().parent

# The top-level repository root (tests/divergence_tests/.. == tests/.. == repo root).
# Almost all absolute paths resolve relative to this.
REPO = DIR.parent.parent

# ──────────────────────────────────────────────────────────────────────────────
# Vosk speech-recognition model
# ──────────────────────────────────────────────────────────────────────────────

# URL from which the Vosk English (US) speech-recognition model is downloaded.
# The divergence tests use Vosk to transcribe synthesized audio back to text,
# then compare the recognized text against the original input via SequenceMatcher.
# Using the small model (~100MB disk, ~500MB RAM) — sufficient accuracy for
# same-text divergence comparison, avoids filling RAM on low-memory systems.
VOSK_MODEL_URL = "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"

# Base directory for externally-downloaded assets (Vosk model, voice files, …).
# Overrides via the EXTERNAL_DIR environment variable for CI / multi-repo setups.
EXTERNAL_DIR = Path(os.environ.get("EXTERNAL_DIR", REPO / "external"))

# Path to the extracted Vosk model directory.
# setup.py downloads and unzips the model here before tests run.
VOSK_MODEL_DIR = EXTERNAL_DIR / "vosk-model-small-en-us-0.15"

# Path to the Vosk model ZIP archive (before extraction).
# Exists transiently during setup; safe to delete after extraction.
VOSK_MODEL_ZIP_DIR = EXTERNAL_DIR / "vosk-model-small-en-us-0.15.zip"

# ──────────────────────────────────────────────────────────────────────────────
# Native C++ binary (piper_synthesize_start / piper_synthesize_next)
# ──────────────────────────────────────────────────────────────────────────────

# Build output directory for the native divergence test binary.
# Created by `setup.py build-native`; wiped and recreated on each build.
NATIVE_BUILD_DIR = DIR / "build"

# Path to the compiled native divergence test binary itself.
# test_divergence.py spawns this process to generate audio via the C++ libpiper
# code path, then compares the result against Python and WASM outputs.
NATIVE_BIN_DIR = NATIVE_BUILD_DIR / "native_divergence_test"

# ──────────────────────────────────────────────────────────────────────────────
# Piper voice models
# ──────────────────────────────────────────────────────────────────────────────

# Directory where Piper voice files (.onnx + .onnx.json) are stored.
# Downloaded by `setup.py download-voices` from the rhasspy/piper-voices
# HuggingFace repository. Multiple voices may coexist here; the active voice
# is selected via the --voice CLI flag to setup.py.
PIPER_VOICES_DIR = EXTERNAL_DIR / "piper_voices"

# ──────────────────────────────────────────────────────────────────────────────
# Deterministic config files
# ──────────────────────────────────────────────────────────────────────────────

# Directory for deterministic ONNX config copies (.onnx.json).
# setup.py copies the original voice config here and normalizes fields
# (e.g., removing non-deterministic metadata) so that the native binary
# and Python code path use identical settings. Files here are generated,
# not committed to version control.
DETERMINISTIC_CONFIG_DIR = DIR / "generated"

# ──────────────────────────────────────────────────────────────────────────────
# WASM build artifacts
# ──────────────────────────────────────────────────────────────────────────────

# Path to the generated JavaScript glue file for the WASM piper build.
# Produced by the Emscripten toolchain; called by test_divergence.py to
# synthesize audio in Node.js via the piper_wasm code path.
WASM_JS = REPO / "wasm_piper" / "build" / "piper_wasm.js"

# Path to the compiled WASM module (.wasm binary).
# Also produced by the Emscripten build; loaded by piper_wasm.js at runtime.
WASM_WASM = REPO / "wasm_piper" / "build" / "piper_wasm.wasm"

# Path to the Node.js synthesis driver script.
# This script imports piper_wasm.js, calls the piper C API through WASM,
# and writes output WAV files. Used by test_divergence.py for the WASM leg
# of the divergence comparison.
WASM_SYNTHESIZE = REPO / "wasm_piper" / "synthesize.js"

# ──────────────────────────────────────────────────────────────────────────────
# Output directory for divergence test WAV files
# ──────────────────────────────────────────────────────────────────────────────

# Where synthesized WAV files from each comparison run are written.
# Organized under generated/divergence_wav/ to keep test artifacts separate
# from source. Safe to gitignore; regenerated on each test run.
WAV_DIR = DIR / "generated" / "divergence_wav"

# ──────────────────────────────────────────────────────────────────────────────
# espeak-ng data directory
# ──────────────────────────────────────────────────────────────────────────────

# Path to the espeak-ng data directory (phoneme tables, voices, rules).
# Bundled by the CMake build into src/piper/espeak-ng-data/ at install time.
# Passed explicitly to the native binary and WASM build so both code paths
# use the same pronunciation rules (critical for deterministic output).
ESPEAK_DATA_DIR = str(REPO / "src" / "piper" / "espeak-ng-data")

# ──────────────────────────────────────────────────────────────────────────────
# Voice-dependent paths (computed from default, recomputed on voice change)
# ──────────────────────────────────────────────────────────────────────────────

# Default voice used when no --voice flag is passed to setup.py / tests.
DEFAULT_VOICE = "en_US-lessac-medium"
_voice_model = DEFAULT_VOICE


def voice_paths(voice: str):
    """Return (model_path, config_path, deterministic_config_path) for voice.

    Args:
        voice: Voice identifier, e.g. "en_US-lessac-medium".

    Returns:
        model_path:      Path to the ONNX model file (e.g. …/en_US-lessac-medium.onnx).
        config_path:     Path to the companion JSON config sidecar (…/.onnx.json).
        deterministic_config_path:  Path to the normalized/deterministic config copy
                                    stored in DETERMINISTIC_CONFIG_DIR.

    The three paths are needed by all three synthesis backends (Python, native, WASM).
    """
    onnx = PIPER_VOICES_DIR / f"{voice}.onnx"
    json_cfg = onnx.with_suffix(".onnx.json")
    det_cfg = DETERMINISTIC_CONFIG_DIR / f"{voice}-deterministic.onnx.json"
    return onnx, json_cfg, det_cfg


# Eagerly compute paths for the default voice so that config.py is usable
# immediately after import without needing to call refresh().
_MODEL_PATH, _CONFIG_PATH, _DETERMINISTIC_CONFIG_PATH = voice_paths(_voice_model)


def refresh(voice: str):
    """Recompute voice-dependent paths. Call after voice override.

    When the user selects a different voice via --voice, this function updates
    the module-level _MODEL_PATH, _CONFIG_PATH, and _DETERMINISTIC_CONFIG_PATH
    variables so that downstream code (setup.py, test_divergence.py) picks up
    the new voice without needing to restart the interpreter.

    Args:
        voice: New voice identifier (e.g. "en_US-amy-low").
    """
    global _voice_model, _MODEL_PATH, _CONFIG_PATH, _DETERMINISTIC_CONFIG_PATH
    _voice_model = voice
    _MODEL_PATH, _CONFIG_PATH, _DETERMINISTIC_CONFIG_PATH = voice_paths(voice)


def get_voice_model() -> str:
    """Return current voice model name.

    Returns:
        The string identifier of the currently-selected voice (e.g. "en_US-lessac-medium").
    """
    return _voice_model
