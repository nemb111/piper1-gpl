"""Shared configuration for divergence tests.

All paths used by setup.py and test_divergence.py live here.
Call refresh(voice) after changing the voice to recompute voice-dependent paths.
"""

import os
from pathlib import Path

DIR = Path(__file__).resolve().parent
REPO = DIR.parent.parent

# ── Static paths ──

VOSK_MODEL_URL = "https://alphacephei.com/vosk/models/vosk-model-en-us-0.22.zip"
EXTERNAL_DIR = Path(os.environ.get("EXTERNAL_DIR", REPO / "external"))
VOSK_EXTERNAL_DIR = EXTERNAL_DIR / "vosk-model-en-us-0.22"
VOSK_MODEL_ZIP = EXTERNAL_DIR / "vosk-model-en-us-0.22.zip"

NATIVE_BUILD = DIR / "build"
NATIVE_BIN = NATIVE_BUILD / "native_divergence_test"

PIPER_VOICES_DIR = EXTERNAL_DIR / "piper_voices"

DETERMINISTIC_CONFIG_DIR = DIR / "generated"

WASM_JS = REPO / "wasm_piper" / "build" / "piper_wasm.js"
WASM_WASM = REPO / "wasm_piper" / "build" / "piper_wasm.wasm"
WASM_SYNTHESIZE = REPO / "wasm_piper" / "synthesize.js"

WAV_DIR = DIR / "generated" / "divergence_wav"

ESPEAK_DATA = str(REPO / "src" / "piper" / "espeak-ng-data")

# ── Voice-dependent paths (computed from default, recomputed on voice change) ──

DEFAULT_VOICE = "en_US-lessac-medium"
_voice_model = DEFAULT_VOICE


def _voice_paths(voice: str):
    """Return (model_path, config_path, deterministic_config_path) for voice."""
    onnx = PIPER_VOICES_DIR / f"{voice}.onnx"
    json_cfg = onnx.with_suffix(".onnx.json")
    det_cfg = DETERMINISTIC_CONFIG_DIR / f"{voice}-deterministic.onnx.json"
    return onnx, json_cfg, det_cfg


_MODEL_PATH, _CONFIG_PATH, _DETERMINISTIC_CONFIG_PATH = _voice_paths(_voice_model)


def refresh(voice: str):
    """Recompute voice-dependent paths. Call after voice override."""
    global _voice_model, _MODEL_PATH, _CONFIG_PATH, _DETERMINISTIC_CONFIG_PATH
    _voice_model = voice
    _MODEL_PATH, _CONFIG_PATH, _DETERMINISTIC_CONFIG_PATH = _voice_paths(voice)


def get_voice_model() -> str:
    """Return current voice model name."""
    return _voice_model
