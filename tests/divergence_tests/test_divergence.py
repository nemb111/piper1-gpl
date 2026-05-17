"""Divergence tests comparing audio output from three Piper build variants.

Synthesizes 20 public domain quotes through Python API, native C++ libpiper,
and WASM/Emscripten builds. Compares pairwise by transcribing back to text
using Vosk speech recognition and comparing normalized transcriptions.

Usage:
    pytest tests/test_divergence.py -v
    pytest tests/test_divergence.py -v -k "test_python_vs_native"

Requirements:
    pip install vosk soundfile librosa
    # 100MB Vosk model: external/vosk-model-small-en-us-0.15
    # Download: https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip
    # Run: python3 tests/divergence_tests/setup.py all
"""

import difflib
import io
import json
import re
import subprocess
import wave
from pathlib import Path
from typing import NamedTuple

import librosa
import numpy as np
import pytest
import soundfile as sf
import vosk
from config import (
    DIR as _DIR,
)
from config import (
    ESPEAK_DATA_DIR as _ESPEAK_DATA,
)
from config import (
    NATIVE_BIN_DIR as _NATIVE_BIN,
)
from config import (
    REPO,
    VOSK_MODEL_DIR,
    get_voice_model,
    voice_paths,
)
from config import (
    WASM_JS as _WASM_JS,
)
from config import (
    WASM_SYNTHESIZE as _WASM_SYNTHESIZE,
)
from config import (
    WASM_WASM as _WASM_WASM,
)
from config import (
    WAV_DIR as _WAV_DIR,
)

from piper import PiperVoice, SynthesisConfig  # noqa: E402


def _model_path():
    """Return current model path (respects voice refresh)."""
    return voice_paths(get_voice_model())[0]


def _deterministic_config():
    """Return current deterministic config path (respects voice refresh)."""
    return voice_paths(get_voice_model())[2]

_SIMILARITY_THRESHOLD = 0.95

# ── 20 public domain quotes ──────────────────────────────

QUOTES = [
    "To be, or not to be, that is the question.",
    "In the beginning was the Word.",
    "I think therefore I am.",
    "The unexamined life is not worth living.",
    "Knowledge is power.",
    "Every cloud has a silver lining.",
    "Science is organized knowledge.",
    "Imagination is more important than knowledge.",
    "The only thing we have to fear is fear itself.",
    "That is one small step for man, one giant leap for mankind.",
    "Tell me and I forget, teach me and I may remember, involve me and I learn.",
    "The greatest glory in living lies not in never falling, but in rising every time we fall.",
    "Music expresses that which cannot be put into words.",
    "Without music, life would be a mistake.",
    "The mind is everything; what you think you become.",
    "In the middle of difficulty lies opportunity.",
    "It is during our darkest moments that we must focus to see the light.",
    "The future belongs to those who believe in the beauty of their dreams.",
    "All that we see or seem is but a dream within a dream.",
    "Let there be light.",
]


# ── Result type ─────────────────────────────────────────

class AudioResult(NamedTuple):
    wav_path: Path
    audio: np.ndarray | None = None
    sample_rate: int = 0


# ── Vosk transcription helpers ───────────────────────────

_vosk_model = None


def _get_vosk_model():
    """Load or return the cached Vosk model from external/."""
    global _vosk_model
    if _vosk_model is None:
        _vosk_model = vosk.Model(model_path=str(VOSK_MODEL_DIR))
    return _vosk_model


def _normalize_text(text: str) -> str:
    """Lowercase, strip non-alphanumeric characters, collapse whitespace."""
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def _resample_to_16k(audio: np.ndarray, sr: int) -> np.ndarray:
    """Resample audio to 16 kHz using librosa."""
    if sr == 16000:
        return audio
    return librosa.resample(audio, orig_sr=sr, target_sr=16000)


def _audio_to_vosk_bytes(audio: np.ndarray, sr: int) -> bytes:
    """Convert audio array to 16-bit PCM WAV bytes at 16 kHz for Vosk."""
    audio_16k = _resample_to_16k(audio, sr=sr)
    pcm_16 = np.clip(audio_16k * 32767.0, -32768, 32767).astype(np.int16)
    buf = io.BytesIO()
    wf = wave.open(buf, "wb")
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(16000)
    wf.writeframes(pcm_16.tobytes())
    wf.close()
    return buf.getvalue()


def _recognize(wav_bytes: bytes) -> str:
    """Run Vosk KaldiRecognizer on WAV bytes and return normalized transcription."""
    model = _get_vosk_model()
    rec = vosk.KaldiRecognizer(model, 16000)
    for i in range(0, len(wav_bytes), 4000):
        rec.AcceptWaveform(wav_bytes[i : i + 4000])
    return _normalize_text(json.loads(rec.FinalResult()).get("text", ""))


def _transcribe_wav_file(wav_path: Path) -> str:
    """Transcribe a WAV file using Vosk. Reads audio, resamples to 16 kHz, converts to PCM."""
    audio, sr = sf.read(str(wav_path))
    wav_bytes = _audio_to_vosk_bytes(audio, sr)
    return _recognize(wav_bytes)


def _get_variant_name(result: AudioResult) -> str:
    """Extract the variant name (python/native/wasm) from an AudioResult path."""
    parts = result.wav_path.parts
    idx = parts.index("divergence_wav")
    return parts[idx + 1]


def _transcription_similarity(a: AudioResult, b: AudioResult) -> tuple[float, str, str]:
    """Compare two audio results by transcribing and computing SequenceMatcher ratio.

    Audio is always read from disk (never from cached numpy arrays) to keep peak memory
    low -- only one WAV is loaded at a time during transcription.

    Returns (0.0–1.0 ratio, text1, text2), robust to minor ASR word-level errors.
    """
    text1 = _transcribe_wav_file(a.wav_path)
    text2 = _transcribe_wav_file(b.wav_path)

    matcher = difflib.SequenceMatcher(None, text1.split(), text2.split(), autojunk=False)
    return max(matcher.ratio(), 0.0), text1, text2


# ── Synthesis helpers ─────────────────────────────────────

def _synthesize_python(text: str, wav_path: Path, voice) -> AudioResult:
    """Synthesize text using Python API with deterministic options (noise_scale=0)."""
    syn_config = SynthesisConfig(noise_scale=0.0, noise_w_scale=0.0)
    with wave.open(str(wav_path), "wb") as wav_file:
        voice.synthesize_wav(text, wav_file, syn_config=syn_config)
    # Don't load audio into memory here -- lazy-load from disk when needed for transcription.
    return AudioResult(wav_path, None, 0)


def _synthesize_native(text: str, wav_path: Path) -> AudioResult:
    """Synthesize text using native C++ binary with deterministic options."""
    if not _ensure_native_built():
        pytest.skip("Native CMake configure/build failed")
    result = subprocess.run(
        [str(_NATIVE_BIN), str(_deterministic_config()), str(_model_path()),
         _ESPEAK_DATA, text, str(wav_path)],
        capture_output=True, timeout=120,
    )
    if result.returncode != 0:
        stderr = result.stderr.decode(errors="replace")
        pytest.fail(f"Native synthesis failed (rc={result.returncode}): {stderr}")
    # Don't load audio into memory here -- lazy-load from disk when needed for transcription.
    return AudioResult(wav_path, None, 0)


def _synthesize_wasm(text: str, wav_path: Path) -> AudioResult:
    """Synthesize text using WASM build, write 32-bit float WAV."""
    if not _wasm_available():
        pytest.skip("WASM build not found at wasm_piper/build/")

    result = subprocess.run(
        ["node", str(_WASM_SYNTHESIZE), str(_model_path()), str(_deterministic_config()), text, str(wav_path)],
        capture_output=True, timeout=180,
        cwd=str(REPO),
    )
    if result.returncode != 0:
        stderr = result.stderr.decode(errors="replace")
        pytest.fail(f"WASM synthesis failed (rc={result.returncode}): {stderr}")
    # Don't load audio into memory here -- lazy-load from disk when needed for transcription.
    return AudioResult(wav_path, None, 0)


# ── Build helpers ─────────────────────────────────────────

_native_built = False


def _ensure_native_built():
    """Build native test binary if not already present. Returns False on failure."""
    global _native_built
    if _native_built or _NATIVE_BIN.exists():
        return True

    build_dir = _DIR / "build"
    build_dir.mkdir(exist_ok=True)

    # Configure
    result = subprocess.run(
        ["cmake", str(_DIR), "-B", str(build_dir)],
        capture_output=True, text=True,
        cwd=str(REPO),
    )
    if result.returncode != 0:
        _native_built = False
        return False

    # Build
    result = subprocess.run(
        ["cmake", "--build", str(build_dir)],
        capture_output=True, text=True,
        cwd=str(REPO),
    )
    if result.returncode != 0:
        _native_built = False
        return False

    _native_built = True
    return True


def _wasm_available() -> bool:
    """Check that WASM build artifacts exist."""
    return Path(_WASM_JS).exists() and Path(_WASM_WASM).exists()


# ── Session-scoped fixture: load voice once ───────────────

@pytest.fixture(scope="module")
def piper_voice():
    """Load the Piper voice model once for all Python synthesis calls."""
    return PiperVoice.load(str(_model_path()))


# ── Module-scoped fixture: synthesize all WAVs once ───────

@pytest.fixture(scope="module")
def divergence_wavs(piper_voice, request):
    """Synthesize all 20 quotes from all 3 variants, return dict keyed by (variant, index).

    Only stores file paths -- audio is lazy-loaded from disk during transcription.
    Piper voice model is freed after synthesis to keep memory low for transcription.
    """
    wavs = {}
    variants = ["python", "native", "wasm"]
    synthesize_funcs = {
        "python": lambda t, p: _synthesize_python(t, p, piper_voice),
        "native": _synthesize_native,
        "wasm": _synthesize_wasm,
    }

    for variant in variants:
        variant_dir = _WAV_DIR / variant
        variant_dir.mkdir(parents=True, exist_ok=True)

        for i, text in enumerate(QUOTES, 1):
            wav_path = variant_dir / f"div_{i:02d}.wav"
            if wav_path.exists():
                # Reuse existing WAV -- no audio array loaded; lazy-load during transcription.
                wavs[(variant, i)] = AudioResult(wav_path, None, 0)
            else:
                wavs[(variant, i)] = synthesize_funcs[variant](text, wav_path)

    # Piper model is no longer needed after synthesis; free it before transcription phase.
    del piper_voice
    import gc; gc.collect()
    return wavs


# ── Parametrized tests ────────────────────────────────────

@pytest.mark.parametrize("i,text", enumerate(QUOTES, 1))
def test_python_vs_native(i, text, divergence_wavs):
    """Compare Python API output vs native C++ output."""
    py = divergence_wavs[("python", i)]
    native = divergence_wavs[("native", i)]

    sim, text1, text2 = _transcription_similarity(py, native)
    assert sim >= _SIMILARITY_THRESHOLD, (
        f"Python-Native mismatch for: {text[:60]}\n"
        f"  Python:  '{text1}'\n"
        f"  Native:  '{text2}'"
    )


@pytest.mark.parametrize("i,text", enumerate(QUOTES, 1))
def test_python_vs_wasm(i, text, divergence_wavs):
    """Compare Python API output vs WASM output."""
    py = divergence_wavs[("python", i)]
    wasm = divergence_wavs[("wasm", i)]

    sim, text1, text2 = _transcription_similarity(py, wasm)
    assert sim >= _SIMILARITY_THRESHOLD, (
        f"Python-WASM mismatch for: {text[:60]}\n"
        f"  Python:  '{text1}'\n"
        f"  WASM:    '{text2}'"
    )


@pytest.mark.parametrize("i,text", enumerate(QUOTES, 1))
def test_native_vs_wasm(i, text, divergence_wavs):
    """Compare native C++ output vs WASM output."""
    native = divergence_wavs[("native", i)]
    wasm = divergence_wavs[("wasm", i)]

    sim, text1, text2 = _transcription_similarity(native, wasm)
    assert sim >= _SIMILARITY_THRESHOLD, (
        f"Native-WASM mismatch for: {text[:60]}\n"
        f"  Native:  '{text1}'\n"
        f"  WASM:    '{text2}'"
    )


# ── Negative tests: different text should NOT be similar ──

@pytest.mark.parametrize("variant", ["python", "native", "wasm"])
def test_different_texts_not_similar(variant, divergence_wavs):
    """Compare quote 1 vs quote 20 from same variant -- similarity must be low.

    Negative test: two very different phrases should produce different audio.
    """
    a = divergence_wavs[(variant, 1)]  # "To be, or not to be..."
    b = divergence_wavs[(variant, 20)]  # "Let there be light."

    sim, text1, text2 = _transcription_similarity(a, b)
    assert sim < 0.5, (
        f"Same-variant different-text similarity {sim:.4f} -- "
        f"test logic may not distinguish dissimilar audio\n"
        f"  Quote 1: '{text1}'\n"
        f"  Quote 2: '{text2}'"
    )
