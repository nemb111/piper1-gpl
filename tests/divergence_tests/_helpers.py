"""Shared helper functions for divergence tests.

These are kept in a separate module so they can be imported
by both conftest.py (fixtures) and test_divergence.py (tests).
"""

from pathlib import Path
from typing import Any, Callable, NamedTuple

import numpy as np
import soundfile as sf
import vosk


SynthesizeFunc = Callable[[str, Path], "AudioResult"]


class AudioResult(NamedTuple):
    wav_path: Path
    audio: object | None = None
    sample_rate: int = 0


def synthesize_python(text: str, wav_path: Path, voice: Any) -> AudioResult:
    """Synthesize text using Python API with deterministic options (noise_scale=0)."""
    from piper import SynthesisConfig

    syn_config = SynthesisConfig(noise_scale=0.0, noise_w_scale=0.0)
    with __import__("wave").open(str(wav_path), "wb") as wav_file:
        voice.synthesize_wav(text, wav_file, syn_config=syn_config)
    return AudioResult(wav_path, None, 0)


def synthesize_native(
    text: str, wav_path: Path, config: Any, native_built: bool
) -> AudioResult:
    """Synthesize text using native C++ binary with deterministic options."""
    import pytest

    if not native_built:
        pytest.skip("Native CMake configure/build failed")
    import subprocess

    result = subprocess.run(
        [
            str(config.native_bin_dir),
            str(config.deterministic_config_path),
            str(config.model_path),
            config.espeak_data_dir,
            text,
            str(wav_path),
        ],
        capture_output=True,
        timeout=120,
    )
    if result.returncode != 0:
        stderr = result.stderr.decode(errors="replace")
        pytest.fail(f"Native synthesis failed (rc={result.returncode}): {stderr}")
    return AudioResult(wav_path, None, 0)


def synthesize_wasm(text: str, wav_path: Path, config: Any) -> AudioResult:
    """Synthesize text using WASM build, write 32-bit float WAV."""
    import pytest

    if not Path(config.wasm_js).exists() or not Path(config.wasm_wasm).exists():
        pytest.skip("WASM build not found at wasm_piper/build/")
    import subprocess

    result = subprocess.run(
        ["node", str(config.wasm_synthesize), str(config.model_path),
         str(config.deterministic_config_path), text, str(wav_path)],
        capture_output=True,
        timeout=180,
        cwd=str(config.repo),
    )
    if result.returncode != 0:
        stderr = result.stderr.decode(errors="replace")
        pytest.fail(f"WASM synthesis failed (rc={result.returncode}): {stderr}")
    return AudioResult(wav_path, None, 0)


def transcribe_wav_file(wav_path: Path, vosk_model: vosk.Model) -> str:
    """Transcribe a WAV file using Vosk. Reads audio, resamples to 16 kHz, converts to PCM."""
    import io
    import json
    import re
    import wave

    audio, sr = sf.read(str(wav_path))  # pyright: ignore[reportUnknownMemberType, reportUnknownVariableType]
    audio_16k = _resample_to_16k(audio, sr)  # pyright: ignore[reportUnknownArgumentType]
    pcm_16 = np.clip(audio_16k * 32767.0, -32768, 32767).astype(np.int16)
    buf = io.BytesIO()
    wf = wave.open(buf, "wb")
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(16000)
    wf.writeframes(pcm_16.tobytes())
    wf.close()
    wav_bytes = buf.getvalue()

    rec = vosk.KaldiRecognizer(vosk_model, 16000)
    for i in range(0, len(wav_bytes), 4000):
        rec.AcceptWaveform(wav_bytes[i : i + 4000])  # pyright: ignore[reportUnknownMemberType]
    result_text = json.loads(rec.FinalResult()).get("text", "")  # pyright: ignore[reportUnknownArgumentType]
    return re.sub(r"[^a-z0-9]+", " ", result_text.lower()).strip()


def _resample_to_16k(audio: np.ndarray, sr: int) -> np.ndarray:
    """Resample audio to 16 kHz using librosa."""
    if sr == 16000:
        return audio
    import librosa

    return librosa.resample(audio, orig_sr=sr, target_sr=16000)
