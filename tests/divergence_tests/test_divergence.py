"""Divergence tests comparing audio output from three Piper build variants.

Synthesizes 20 public domain quotes through Python API, native C++ libpiper,
and WASM/Emscripten builds. Compares pairwise by transcribing back to text
using Vosk speech recognition and comparing normalized transcriptions.

Usage:
    pytest tests/test_divergence.py -v
    pytest tests/test_divergence.py -v -k "test_python_vs_native"

Requirements:
    pip install vosk soundfile librosa
    # 1.8GB Vosk model: external/vosk-model-en-us-0.22
    # Download: https://alphacephei.com/vosk/models/vosk-model-en-us-0.22.zip
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

import numpy as np
import pytest
import librosa
import soundfile as sf
import vosk

from piper import PiperVoice, SynthesisConfig  # noqa: E402

_DIR = Path(__file__).resolve().parent
_REPO = _DIR.parent.parent  # repo root = tests/divergence_tests/.. = tests/.. = repo root
_WAV_DIR = _REPO / "external" / "divergence_wav"
_PIPER_VOICES_DIR = _REPO / "external" / "piper_voices"
_DEFAULT_VOICE = "en_US-lessac-medium"

def _ensure_wav_dir():
    """Create divergence_wav/{python,native,wasm} dirs if they don't exist."""
    _WAV_DIR.mkdir(parents=True, exist_ok=True)
    for v in ("python", "native", "wasm"):
        (_WAV_DIR / v).mkdir(exist_ok=True)
_MODEL_PATH = _PIPER_VOICES_DIR / f"{_DEFAULT_VOICE}.onnx"
_CONFIG_PATH = _MODEL_PATH.with_suffix(".onnx.json")
_DETERMINISTIC_CONFIG = _DIR / "data" / f"{_DEFAULT_VOICE}-deterministic.onnx.json"
_ESPEAK_DATA = str(_REPO / "src" / "piper" / "espeak-ng-data")
_NATIVE_BIN = _DIR / "build" / "native_divergence_test"
_WASM_SYNTHESIZE = str(_REPO / "wasm_piper" / "synthesize.js")
_WASM_JS = str(_REPO / "wasm_piper" / "build" / "piper_wasm.js")
_WASM_WASM = str(_REPO / "wasm_piper" / "build" / "piper_wasm.wasm")

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
    audio: np.ndarray
    sample_rate: int


# ── Vosk transcription helpers ───────────────────────────

_vosk_model = None


def _get_vosk_model():
    """Load or return the cached Vosk model from external/."""
    global _vosk_model
    if _vosk_model is None:
        _vosk_model = vosk.Model(
            model_path=str(_REPO / "external" / "vosk-model-en-us-0.22"),
        )
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


def _transcribe_audio_array(audio: np.ndarray, sr: int) -> str:
    """Transcribe a float numpy array using Vosk (resamples to 16 kHz if needed)."""
    wav_bytes = _audio_to_vosk_bytes(audio, sr)
    return _recognize(wav_bytes)


def _get_variant_name(result: AudioResult) -> str:
    """Extract the variant name (python/native/wasm) from an AudioResult path."""
    parts = result.wav_path.parts
    idx = parts.index("divergence_wav")
    return parts[idx + 1]


def _transcription_similarity(a: AudioResult, b: AudioResult) -> float:
    """Compare two audio results by transcribing and computing SequenceMatcher ratio.

    Native WAVs (32-bit float) are transcribed in-memory from the numpy array.
    Python/WASM WAVs (16-bit PCM) are read from disk.

    Returns 0.0–1.0 ratio, robust to minor ASR word-level errors.
    """
    if _get_variant_name(a) == "native":
        text1 = _transcribe_audio_array(a.audio, a.sample_rate)
    else:
        text1 = _transcribe_wav_file(a.wav_path)

    if _get_variant_name(b) == "native":
        text2 = _transcribe_audio_array(b.audio, b.sample_rate)
    else:
        text2 = _transcribe_wav_file(b.wav_path)

    matcher = difflib.SequenceMatcher(None, text1.split(), text2.split(), autojunk=False)
    return max(matcher.ratio(), 0.0)


# ── Synthesis helpers ─────────────────────────────────────

def _synthesize_python(text: str, wav_path: Path, voice) -> AudioResult:
    """Synthesize text using Python API with deterministic options (noise_scale=0)."""
    syn_config = SynthesisConfig(noise_scale=0.0, noise_w_scale=0.0)
    with wave.open(str(wav_path), "wb") as wav_file:
        voice.synthesize_wav(text, wav_file, syn_config=syn_config)
    audio, sr = sf.read(str(wav_path))
    return AudioResult(wav_path, audio, sr)


def _synthesize_native(text: str, wav_path: Path) -> AudioResult:
    """Synthesize text using native C++ binary with deterministic options."""
    if not _ensure_native_built():
        pytest.skip("Native CMake configure/build failed")
    result = subprocess.run(
        [str(_NATIVE_BIN), str(_DETERMINISTIC_CONFIG), str(_MODEL_PATH),
         _ESPEAK_DATA, text, str(wav_path)],
        capture_output=True, timeout=120,
    )
    if result.returncode != 0:
        stderr = result.stderr.decode(errors="replace")
        pytest.fail(f"Native synthesis failed (rc={result.returncode}): {stderr}")
    audio, sr = sf.read(str(wav_path))
    return AudioResult(wav_path, audio, sr)


def _synthesize_wasm(text: str, wav_path: Path) -> AudioResult:
    """Synthesize text using WASM build, write 32-bit float WAV."""
    if not _wasm_available():
        pytest.skip("WASM build not found at wasm_piper/build/")

    result = subprocess.run(
        ["node", _WASM_SYNTHESIZE, str(_MODEL_PATH), str(_DETERMINISTIC_CONFIG), text, str(wav_path)],
        capture_output=True, timeout=180,
        cwd=str(_REPO),
    )
    if result.returncode != 0:
        stderr = result.stderr.decode(errors="replace")
        pytest.fail(f"WASM synthesis failed (rc={result.returncode}): {stderr}")
    audio, sr = sf.read(str(wav_path))
    return AudioResult(wav_path, audio, sr)


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
        cwd=str(_REPO),
    )
    if result.returncode != 0:
        _native_built = False
        return False

    # Build
    result = subprocess.run(
        ["cmake", "--build", str(build_dir)],
        capture_output=True, text=True,
        cwd=str(_REPO),
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
    return PiperVoice.load(str(_MODEL_PATH))


# ── Module-scoped fixture: synthesize all WAVs once ───────

@pytest.fixture(scope="module")
def divergence_wavs(piper_voice, request):
    """Synthesize all 20 quotes from all 3 variants, return dict keyed by (variant, index)."""
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
                audio, sr = sf.read(str(wav_path))
                wavs[(variant, i)] = AudioResult(wav_path, audio, sr)
            else:
                wavs[(variant, i)] = synthesize_funcs[variant](text, wav_path)

    return wavs


# ── Parametrized tests ────────────────────────────────────

@pytest.mark.parametrize("i,text", enumerate(QUOTES, 1))
def test_python_vs_native(i, text, divergence_wavs):
    """Compare Python API output vs native C++ output."""
    py = divergence_wavs[("python", i)]
    native = divergence_wavs[("native", i)]

    sim = _transcription_similarity(py, native)
    assert sim >= _SIMILARITY_THRESHOLD, f"Python-Native mismatch for: {text[:60]}"


@pytest.mark.parametrize("i,text", enumerate(QUOTES, 1))
def test_python_vs_wasm(i, text, divergence_wavs):
    """Compare Python API output vs WASM output."""
    py = divergence_wavs[("python", i)]
    wasm = divergence_wavs[("wasm", i)]

    sim = _transcription_similarity(py, wasm)
    assert sim >= _SIMILARITY_THRESHOLD, f"Python-WASM mismatch for: {text[:60]}"


@pytest.mark.parametrize("i,text", enumerate(QUOTES, 1))
def test_native_vs_wasm(i, text, divergence_wavs):
    """Compare native C++ output vs WASM output."""
    native = divergence_wavs[("native", i)]
    wasm = divergence_wavs[("wasm", i)]

    sim = _transcription_similarity(native, wasm)
    assert sim >= _SIMILARITY_THRESHOLD, f"Native-WASM mismatch for: {text[:60]}"


# ── Negative tests: different text should NOT be similar ──

@pytest.mark.parametrize("variant", ["python", "native", "wasm"])
def test_different_texts_not_similar(variant, divergence_wavs):
    """Compare quote 1 vs quote 20 from same variant -- similarity must be low.

    Negative test: two very different phrases should produce different audio.
    """
    a = divergence_wavs[(variant, 1)]  # "To be, or not to be..."
    b = divergence_wavs[(variant, 20)]  # "Let there be light."

    sim = _transcription_similarity(a, b)
    assert sim < 0.5, (
        f"Same-variant different-text similarity {sim:.4f} -- "
        "test logic may not distinguish dissimilar audio"
    )
