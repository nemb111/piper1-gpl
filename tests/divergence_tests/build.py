#!/usr/bin/env python3
"""Build script for Piper divergence tests.

Installs Python dependencies, builds the native C++ test binary via CMake,
downloads voice models and the Vosk speech recognition model, and
builds WASM if Emscripten is available.

Usage:
    python build.py                               # run all steps (skip if already set up)
    python build.py deps                          # install Python dependencies only
    python build.py build-native                  # build native binary only
    python build.py download-vosk-model                # download Vosk model only
    python build.py download-voices               # download voice models only
    python build.py deterministic-config          # generate deterministic config
    python build.py build-wasm                    # build WASM binary (if emcc available)
    python build.py clean                         # remove build artifacts
    python build.py --list-voices                 # list all available Piper voices
    python build.py --voice en_US-amy-low all     # use a different voice
"""

import argparse
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from typing import Any, List

from config import (
    DEFAULT_VOICE,
    DETERMINISTIC_CONFIG_DIR,
    DIR,
    EXTERNAL_DIR,
    NATIVE_BIN_DIR,
    NATIVE_BUILD_DIR,
    PIPER_VOICES_DIR,
    REPO,
    VOSK_MODEL_DIR,
    VOSK_MODEL_URL,
    VOSK_MODEL_ZIP_DIR,
    config_instance,
    voice_paths,
)

PIP_CMD = [sys.executable, "-m", "pip"]


BUILD_TOOLS = [
    # System-level build tools (checked via PATH, not pip)
    "cmake",
]


def run(cmd: List[str], **kwargs: Any) -> int:
    """Run a command, raising on failure."""
    print(f"+ {' '.join(cmd)}")
    return subprocess.check_call(cmd, **kwargs)


def all_deps_met() -> bool:
    """Check if all Python dependencies are already satisfied."""
    # Check system build tools
    for tool in BUILD_TOOLS:
        if shutil.which(tool) is None:
            return False
    return True


def voice_models_exist() -> bool:
    """Check that voice model files exist in external/piper_voices."""
    onnx, json_cfg, _ = voice_paths(config_instance.voice)
    return onnx.exists() and json_cfg.exists()


def deterministic_config_exists() -> bool:
    """Check that the deterministic config file exists."""
    return DETERMINISTIC_CONFIG_DIR.is_dir() and any(
        DETERMINISTIC_CONFIG_DIR.glob("*.onnx.json")
    )


def deps_exist() -> bool:
    """Check if all prerequisites are already set up."""
    return (
        all_deps_met()
        and NATIVE_BIN_DIR.exists()
        and VOSK_MODEL_DIR.exists()
        and voice_models_exist()
        and deterministic_config_exists()
    )


def install_python_pkgs() -> None:
    """Install Python dependencies and build the C extension."""

    run(
        PIP_CMD + ["install", "-e", ".[test]"],
        cwd=REPO,
    )

    # Editable install doesn't build the C extension — compile it in-place.
    run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=REPO,
    )


class PiperBuilds:
    def __init__(self) -> None:
        pass

    @staticmethod
    def native() -> None:
        """Build the native C++ divergence test binary via CMake."""
        print("=== Building native divergence test binary ===")
        run(["cmake", str(DIR), "-B", str(NATIVE_BUILD_DIR)], cwd=str(REPO))
        run(["cmake", "--build", str(NATIVE_BUILD_DIR), "-j"], cwd=str(REPO))
        if not NATIVE_BIN_DIR.exists():
            print(f"Error: binary not found at {NATIVE_BIN_DIR}", file=sys.stderr)
            sys.exit(1)
        print(f"Native binary built: {NATIVE_BIN_DIR}")

    @staticmethod
    def python() -> None:
        """Build the Piper Python package (prerequisite for CMake-native build)."""
        print("=== Building Piper Python package ===")
        run(
            [sys.executable, "setup.py", "build_ext", "--inplace"],
            cwd=REPO,
        )
        print("Piper Python package built.")

    @staticmethod
    def wasm() -> None:
        """Build WASM piper binary via wasm_piper/build.py."""
        print("=== Building WASM piper binary ===")
        build_script = REPO / "wasm_piper" / "build.py"
        run([sys.executable, str(build_script)], cwd=str(REPO))


def download_vosk_model() -> None:
    """Download the Vosk English speech recognition model to external/."""
    print("=== Downloading Vosk model ===")

    if VOSK_MODEL_DIR.exists() and any(VOSK_MODEL_DIR.rglob("*")):
        print(f"Model already exists at {VOSK_MODEL_DIR}, skipping download.")
        return

    EXTERNAL_DIR.mkdir(parents=True, exist_ok=True)

    if not VOSK_MODEL_ZIP_DIR.exists():
        print(f"Downloading {VOSK_MODEL_URL} ...")
        print("This is ~100MB.")
        urllib.request.urlretrieve(VOSK_MODEL_URL, VOSK_MODEL_ZIP_DIR)
        print("Download complete.")
        print(f"Extracting {VOSK_MODEL_ZIP_DIR} ...")
        with zipfile.ZipFile(VOSK_MODEL_ZIP_DIR, "r") as zf:
            zf.extractall(str(VOSK_MODEL_ZIP_DIR.parent))
        print("Extraction complete.")
    else:
        print(f"Zip already exists at {VOSK_MODEL_ZIP_DIR}, extracting...")
        with zipfile.ZipFile(VOSK_MODEL_ZIP_DIR, "r") as zf:
            zf.extractall(str(VOSK_MODEL_ZIP_DIR.parent))

    print(f"Model available at: {VOSK_MODEL_DIR}")


def download_voices() -> None:
    """Download voice models needed for divergence tests."""
    print("=== Downloading voice models ===")
    PIPER_VOICES_DIR.mkdir(parents=True, exist_ok=True)

    if voice_models_exist():
        print(f"Voice models already exist at {PIPER_VOICES_DIR}, skipping download.")
        return

    from piper.download_voices import download_voice

    download_voice(config_instance.voice, PIPER_VOICES_DIR)
    print(f"Voice models available at: {PIPER_VOICES_DIR}")


def copy_deterministic_config() -> None:
    """Generate deterministic config (noise_scale=0, noise_w=0) from the voice model."""
    print("=== Setting up deterministic config ===")
    if DETERMINISTIC_CONFIG_DIR.is_dir() and any(
        DETERMINISTIC_CONFIG_DIR.glob("*.onnx.json")
    ):
        print("Deterministic config already exists, skipping.")
        return

    import json

    voice = config_instance.voice
    source = PIPER_VOICES_DIR / f"{voice}.onnx.json"
    if not source.exists():
        print(f"WARNING: source config not found at {source}, skipping.")
        return

    with open(source) as f:
        cfg = json.load(f)
    cfg["inference"]["noise_scale"] = 0.0
    cfg["inference"]["noise_w"] = 0.0

    dest = DETERMINISTIC_CONFIG_DIR / f"{voice}-deterministic.onnx.json"
    DETERMINISTIC_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(dest, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=True)
        f.write("\n")
    print(f"Created {dest}")


def clean() -> None:
    """Remove build artifacts."""
    print("=== Cleaning build artifacts ===")
    for d in [NATIVE_BUILD_DIR, REPO / "build"]:
        if d.exists():
            print(f"Removing {d}")
            shutil.rmtree(d)
    # Clean deterministic config
    if DETERMINISTIC_CONFIG_DIR.exists():
        if DETERMINISTIC_CONFIG_DIR.is_symlink():
            DETERMINISTIC_CONFIG_DIR.unlink()
        elif DETERMINISTIC_CONFIG_DIR.is_dir():
            shutil.rmtree(DETERMINISTIC_CONFIG_DIR)
        print(f"Removing {DETERMINISTIC_CONFIG_DIR}")
    print("Clean complete.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Setup script for Piper divergence tests"
    )
    parser.add_argument(
        "--list-voices",
        action="store_true",
        help="List all available Piper voices and exit",
    )
    parser.add_argument(
        "--voice",
        type=str,
        default=DEFAULT_VOICE,
        metavar="VOICE",
        help="Voice to use for divergence tests (default: %(default)s)",
    )
    parser.add_argument(
        "command",
        nargs="?",
        default="all",
        choices=[
            "all",
            "deps",
            "build-native",
            "download-vosk-model",
            "download-voices",
            "deterministic-config",
            "build-wasm",
            "clean",
        ],
        help="Which step to run (default: all)",
    )
    args = parser.parse_args()

    if args.list_voices:
        from piper.download_voices import list_voices

        list_voices()
        return

    config_instance.voice = args.voice

    # When running all steps, exit early if everything is already set up
    if args.command == "all" and deps_exist():
        print("All dependencies, native binary, and models are already set up.")
        return

    step_map = {
        "all": [
            "deps",
            "build-native",
            "download-voices",
            "deterministic-config",
            "download-vosk-model",
            "build-wasm",
        ],
        "deps": ["deps"],
        "build-native": ["build-native"],
        "download-vosk-model": ["download-vosk-model"],
        "download-voices": ["download-voices"],
        "deterministic-config": ["deterministic-config"],
        "build-wasm": ["build-wasm"],
        "clean": ["clean"],
    }

    for step in step_map[args.command]:
        if step == "deps":
            install_python_pkgs()
        elif step == "build-native":
            PiperBuilds.native()
        elif step == "build-wasm":
            PiperBuilds.wasm()
        elif step == "build-python":
            PiperBuilds.python()
        elif step == "download-vosk-model":
            download_vosk_model()
        elif step == "download-voices":
            download_voices()
        elif step == "deterministic-config":
            copy_deterministic_config()
        elif step == "clean":
            clean()

    if args.command != "clean":
        print("Setup complete.")


if __name__ == "__main__":
    main()
