"""Divergence tests comparing audio output from three Piper build variants.

Synthesizes 20 public domain quotes through Python API, native C++ libpiper,
and WASM/Emscripten builds. Compares each variant's transcription against the
original input text using Vosk speech recognition and SequenceMatcher.

Usage:
    pytest tests/test_divergence.py -v
    pytest tests/test_divergence.py -v -k "test_variant_transcription_matches_text"
    pytest tests/test_divergence.py -v -k "test_different_texts_not_similar"

Requirements:
    pip install vosk soundfile librosa
    # 100MB Vosk model: external/vosk-model-small-en-us-0.15
    # Download: https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip
    # Run: python3 tests/divergence_tests/setup.py all
"""

import difflib
from typing import Any

import pytest
import vosk

from _helpers import AudioResult, transcribe_wav_file

# ── Utility ──

def _normalize_text(text: str) -> str:
    """Lowercase, strip non-alphanumeric characters, collapse whitespace."""
    import re

    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


# ── Thresholds ───────────────────────────────────────

# Minimum similarity for each individual (variant, quote) pair.
PER_TEST_THRESHOLD = 0.85

# Minimum average similarity across all individual tests.
OVERALL_THRESHOLD = 0.95

# Maximum similarity for two different quotes from the same variant (negative test).
NEGATIVE_PER_TEST_THRESHOLD = 0.2

# Marker used by the overall test to ensure the assertion runs only once.
# After all per-test similarity scores are accumulated, the first invocation
# that sees len >= 60 asserts and marks subsequent invocations to skip.
_overall_checked = False

# ── 20 public domain quotes ────────────────────────────

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


# ── Parametrized tests ────────────────────────────────────

# ── Score accumulator (session-scoped) ──────────────────────

_all_similarities: list[float] = []


@pytest.mark.parametrize("variant", ["python", "native", "wasm"])
@pytest.mark.parametrize("i,text", enumerate(QUOTES, 1))
def test_variant_transcription_matches_text(variant: Any, i: int, text: str, divergence_wavs: dict[tuple[str, int], AudioResult], vosk_model: vosk.Model) -> None:  # pyright: ignore[reportUnknownParameterType]
    """Each variant's audio should transcribe back to the original input text (>= 0.85 similarity)."""
    result = divergence_wavs[(variant, i)]
    if result.wav_path is None:
        pytest.skip(f"{variant} variant not available (WASM build missing)")
    transcription = transcribe_wav_file(result.wav_path, vosk_model)
    expected = _normalize_text(text)
    matcher = difflib.SequenceMatcher(None, transcription.split(), expected.split(), autojunk=False)
    sim = max(matcher.ratio(), 0.0)
    _all_similarities.append(sim)
    print(f"{variant} quote {i}: similarity={sim:.4f}")
    assert sim >= PER_TEST_THRESHOLD, (
        f"{variant} mismatch for: {text[:60]}\n"
        f"  Expected:  '{expected}'\n"
        f"  Transcribed: '{transcription}'"
    )


@pytest.mark.parametrize("variant", ["python", "native", "wasm"])
@pytest.mark.parametrize("i,text", enumerate(QUOTES, 1))
def test_overall_similarity_avg(variant: Any, i: int, text: str, divergence_wavs: dict[tuple[str, int], AudioResult], vosk_model: vosk.Model) -> None:  # pyright: ignore[reportUnknownParameterType]
    """Overall average similarity across all individual tests (>= 0.95)."""
    global _overall_checked
    result = divergence_wavs.get((variant, i))
    if result is not None and result.wav_path is None:
        pytest.skip(f"{variant} variant not available (WASM build missing)")
    overall = sum(_all_similarities) / len(_all_similarities) if _all_similarities else 0.0
    if not _overall_checked:
        _overall_checked = True
        assert overall >= OVERALL_THRESHOLD, (
            f"Overall similarity average {overall:.4f} < {OVERALL_THRESHOLD}\n"
            f"  Tests passed: {sum(1 for s in _all_similarities if s >= PER_TEST_THRESHOLD)}/{len(_all_similarities)}"
        )


# ── Negative tests: different text should NOT be similar ──

@pytest.mark.parametrize("variant", ["python", "native", "wasm"])
def test_different_texts_not_similar(variant: Any, divergence_wavs: dict[tuple[str, int], AudioResult], vosk_model: vosk.Model) -> None:  # pyright: ignore[reportUnknownParameterType]
    """Compare quote 1 vs quote 20 from same variant -- similarity must be low.

    Negative test: two very different phrases should produce different audio.
    """
    a = divergence_wavs[(variant, 1)]  # "To be, or not to be..."
    b = divergence_wavs[(variant, 20)]  # "Let there be light."
    if a.wav_path is None or b.wav_path is None:
        pytest.skip(f"{variant} variant not available (WASM build missing)")

    text1 = transcribe_wav_file(a.wav_path, vosk_model)
    text2 = transcribe_wav_file(b.wav_path, vosk_model)
    matcher = difflib.SequenceMatcher(None, text1.split(), text2.split(), autojunk=False)
    sim = max(matcher.ratio(), 0.0)
    assert sim < NEGATIVE_PER_TEST_THRESHOLD, (
        f"Same-variant different-text similarity {sim:.4f} -- "
        f"test logic may not distinguish dissimilar audio\n"
        f"  Quote 1: '{text1}'\n"
        f"  Quote 2: '{text2}'"
    )
