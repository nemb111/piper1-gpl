#!/usr/bin/env python3
"""Native piper audio synthesis using onnxruntime + compiled espeak-ng.
Produces a WAV file from text using the Piper voice model.
"""
import json
import os
import struct
import subprocess
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
_BUILD_DIR = _REPO_ROOT / "build"
_DATA_DIR = Path(__file__).resolve().parent / "data"

ESPEAK_BIN = os.environ.get(
    "ESPEAK_BIN", str(_BUILD_DIR / "espeak_ng-install" / "bin" / "espeak-ng")
)
ESPEAK_DATA = os.environ.get(
    "ESPEAK_DATA", str(_DATA_DIR / "espeak-ng-data")
)


def phonemize(text: str) -> str:
    """Get IPA phonemes from espeak-ng."""
    result = subprocess.run(
        [ESPEAK_BIN, "-v", "en-us", "--ipa", "--stdout", text],
        capture_output=True,
        env={**dict(__import__("os").environ), "ESPEAK_DATA": ESPEAK_DATA},
    )
    # First line is IPA text, rest is audio binary (ignored)
    return result.stdout.split(b"\n")[0].decode("utf-8", errors="replace")


def text_to_phoneme_ids(text: str, phoneme_id_map: dict) -> list[list[int]]:
    """Convert text to phoneme IDs (with BOS/EOS/padding).
    Matches piper.cpp logic:
      [1] + [pad + char_id]* + [0 (separator)] + [pad + char_id]* ... + [2]
    """
    phonemes = phonemize(text)
    result = []
    result.append(1)  # BOS

    for i, ch in enumerate(phonemes):
        if ch == " ":
            result.append(0)  # phoneme separator
        else:
            ids = phoneme_id_map.get(ch, [0])
            result.append(0)  # pad before phoneme
            result.extend(ids)

    result.append(2)  # EOS
    return result


def write_wav(filename: str, samples: list[float], sample_rate: int):
    """Write float samples as WAV (no external deps)."""
    import struct
    audio_np = np.clip(np.array(samples, dtype=np.float32), -1.0, 1.0)
    audio_int16 = (audio_np * 32767).astype(np.int16)
    with open(filename, "wb") as f:
        data_bytes = audio_int16.tobytes()
        file_size = 36 + len(data_bytes)
        f.write(b"RIFF")
        f.write(struct.pack("<I", file_size))
        f.write(b"WAVE")
        f.write(b"fmt ")
        f.write(struct.pack("<I", 16))  # chunk size
        f.write(struct.pack("<H", 1))   # PCM
        f.write(struct.pack("<H", 1))   # mono
        f.write(struct.pack("<I", sample_rate))
        f.write(struct.pack("<I", sample_rate * 2))  # byte rate
        f.write(struct.pack("<H", 2))   # block align
        f.write(struct.pack("<H", 16))  # bits per sample
        f.write(b"data")
        f.write(struct.pack("<I", len(data_bytes)))
        f.write(data_bytes)


def synthesize(model_path: str, config_path: str, text: str, output_path: str):
    """Full synthesis pipeline: text -> phonemes -> ONNX -> WAV."""
    with open(config_path) as f:
        config = json.load(f)

    phoneme_id_map = {}
    for sym, ids in config.get("phoneme_id_map", {}).items():
        for ch in sym:
            phoneme_id_map[ch] = ids

    num_speakers = config.get("num_speakers", 1)
    sr = config["audio"]["sample_rate"]

    # Phonemize
    all_phoneme_ids = text_to_phoneme_ids(text, phoneme_id_map)

    # Prepare ONNX inputs
    phoneme_ids_np = np.array([all_phoneme_ids], dtype=np.int64)
    input_lengths = np.array([len(all_phoneme_ids)], dtype=np.int64)

    noise_scale = config.get("inference", {}).get("noise_scale", 0.667)
    length_scale = config.get("inference", {}).get("length_scale", 1.0)
    noise_w_scale = config.get("inference", {}).get("noise_w", 0.8)

    # Build input dict
    # scales is shape [3], input is [1, N], input_lengths is [1]
    inputs = {
        "input": phoneme_ids_np,
        "input_lengths": input_lengths,
        "scales": np.array(
            [noise_scale, length_scale, noise_w_scale], dtype=np.float32
        ),
    }

    if num_speakers > 1:
        sid = config.get("speaker_id_map", {}).get("speaker_0", 0)
        inputs["sid"] = np.array([sid], dtype=np.int64)

    # Run inference
    session = ort.InferenceSession(
        model_path,
        providers=["CPUExecutionProvider"],
        session_options=ort.SessionOptions(),
    )

    audio_np = session.run(None, inputs)[0]
    samples = audio_np.flatten().tolist()

    # Write output
    write_wav(output_path, samples, sr)
    duration = len(samples) / sr
    print(f"Synthesized {len(samples)} samples ({duration:.1f}s) -> {output_path}")
    print(f"  Phonemes: {phonemize(text)[:60]}")
    print(f"  Phoneme IDs: {len(all_phoneme_ids)}")


if __name__ == "__main__":
    model_path = sys.argv[1] if len(sys.argv) > 1 else "model.onnx"
    config_path = sys.argv[2] if len(sys.argv) > 2 else "model.onnx.json"
    text = sys.argv[3] if len(sys.argv) > 3 else "hello world"
    output_path = sys.argv[4] if len(sys.argv) > 4 else "native_output.wav"

    synthesize(model_path, config_path, text, output_path)
