"""Pytest fixtures for divergence tests.

Session-scoped fixtures:
    config        -- Config instance (from config.config_instance)
    vosk_model    -- Lazily loaded Vosk speech recognition model
    native_built  -- Ensures native C++ binary is built

Module-scoped fixtures:
    piper_voice     -- Loads PiperVoice model once per module
    divergence_wavs -- Synthesizes all 20 quotes x 3 variants, returns dict
"""

import subprocess

import pytest
import vosk
from piper import PiperVoice

from _helpers import AudioResult, SynthesizeFunc
from config import (
    Config,
    DIR,
    NATIVE_BIN_DIR,
    REPO,
    VOSK_MODEL_DIR,
    config_instance,
)


# ── Session-scoped fixtures ──────────────────────────


@pytest.fixture(scope="session")
def config() -> Config:
    """Return the session-wide Config instance."""
    return config_instance


_vosk_model_cache: vosk.Model | None = None


@pytest.fixture(scope="session")
def vosk_model() -> vosk.Model:
    """Load or return the cached Vosk model (session-scoped)."""
    global _vosk_model_cache
    if _vosk_model_cache is None:
        _vosk_model_cache = vosk.Model(model_path=str(VOSK_MODEL_DIR))
    return _vosk_model_cache


@pytest.fixture(scope="session")
def native_built() -> bool:
    """Build native test binary if not already present.

    Replaces the module-level _native_built global and _ensure_native_built().
    Returns True on success, False on failure (test functions should skip).
    """
    if NATIVE_BIN_DIR.exists():
        return True

    build_dir = DIR / "build"
    build_dir.mkdir(exist_ok=True)

    result = subprocess.run(
        ["cmake", str(DIR), "-B", str(build_dir)],
        capture_output=True, text=True, cwd=str(REPO),
    )
    if result.returncode != 0:
        return False

    result = subprocess.run(
        ["cmake", "--build", str(build_dir)],
        capture_output=True, text=True, cwd=str(REPO),
    )
    if result.returncode != 0:
        return False

    return True


# ── Module-scoped fixtures ───────────────────────────




@pytest.fixture(scope="module")
def piper_voice(config: Config) -> PiperVoice:
    """Load the Piper voice model once for all Python synthesis calls."""
    return PiperVoice.load(str(config.model_path))


@pytest.fixture(scope="module")
def divergence_wavs(
    piper_voice: PiperVoice,
    config: Config,
    native_built: bool,
    vosk_model: vosk.Model,
) -> dict[tuple[str, int], AudioResult]:
    """Synthesize all 20 quotes from all 3 variants, return dict keyed by (variant, index).

    Only stores file paths -- audio is lazy-loaded from disk during transcription.
    Piper voice model is freed after synthesis to keep memory low for transcription.
    """
    from _helpers import synthesize_native, synthesize_python, synthesize_wasm

    from test_divergence import QUOTES, AudioResult

    wavs: dict[tuple[str, int], AudioResult] = {}
    variants: list[str] = ["python", "native", "wasm"]
    synthesize_funcs: dict[str, SynthesizeFunc] = {
        "python": lambda t, p, pv=piper_voice: synthesize_python(t, p, pv),  # type: ignore[misc]
        "native": lambda t, p: synthesize_native(t, p, config, native_built),
        "wasm": lambda t, p: synthesize_wasm(t, p, config),
    }

    for variant in variants:
        variant_dir = config.wave_dir / variant
        variant_dir.mkdir(parents=True, exist_ok=True)

        for i, text in enumerate(QUOTES, 1):
            wav_path = variant_dir / f"div_{i:02d}.wav"
            if wav_path.exists():
                wavs[(variant, i)] = AudioResult(wav_path, None, 0)
            else:
                wavs[(variant, i)] = synthesize_funcs[variant](text, wav_path)

    del piper_voice
    import gc
    gc.collect()
    return wavs
