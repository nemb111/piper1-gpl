#!/usr/bin/env python3
"""Setup script for Piper divergence tests.

Installs Python dependencies, builds the native C++ test binary via CMake,
downloads voice models and the Vosk speech recognition model, copies
espeak-ng data for WASM, and builds WASM if Emscripten is available.

Usage:
    python setup.py                               # run all steps (skip if already set up)
    python setup.py deps                          # install Python dependencies only
    python setup.py build-native                  # build native binary only
    python setup.py download-model                # download Vosk model only
    python setup.py download-voices               # download voice models only
    python setup.py espeak-data                   # copy espeak-ng data for WASM
    python setup.py deterministic-config          # generate deterministic config
    python setup.py build-wasm                    # build WASM binary (if emcc available)
    python setup.py clean                         # remove build artifacts
    python setup.py --list-voices                 # list all available Piper voices
    python setup.py --voice en_US-amy-low all     # use a different voice
"""

import argparse
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

_DIR = Path(__file__).resolve().parent
_REPO = _DIR.parent.parent

# ── Paths ──────────────────────

_MODEL_URL = "https://alphacephei.com/vosk/models/vosk-model-en-us-0.22.zip"
EXTERNAL_DIR = Path(os.environ.get("EXTERNAL_DIR", _REPO / "external"))
VOSK_EXTERNAL_DIR = EXTERNAL_DIR / "vosk-model-en-us-0.22"
_MODEL_ZIP = EXTERNAL_DIR / "vosk-model-en-us-0.22.zip"

_NATIVE_BUILD = _DIR / "build"
_NATIVE_BIN = _NATIVE_BUILD / "native_divergence_test"

# Voice model for divergence tests (overridden by --voice argument in main())
# All _VOICE_* paths are recomputed in main() when --voice is specified.
_DEFAULT_VOICE = "en_US-lessac-medium"
_VOICE_MODEL = _DEFAULT_VOICE
_PIPER_VOICES_DIR = EXTERNAL_DIR / "piper_voices"
_VOICE_ONNX = _PIPER_VOICES_DIR / f"{_VOICE_MODEL}.onnx"
_VOICE_JSON = _PIPER_VOICES_DIR / f"{_VOICE_MODEL}.onnx.json"
_WASM_MODEL_DIR = _REPO / "wasm_piper" / "tests" / "data"
_ESPEAK_SRC = _REPO / "src" / "piper" / "espeak-ng-data"
_ESPEAK_WASM = _WASM_MODEL_DIR / "espeak-ng-data"

# Deterministic config for native/WASM tests
_DETERMINISTIC_CONFIG_DIR = _DIR / "data"
_DETERMINISTIC_CONFIG_PATH = _DETERMINISTIC_CONFIG_DIR / f"{_VOICE_MODEL}-deterministic.onnx.json"


def _recompute_voice_paths(voice: str) -> None:
    """Recompute all voice-dependent paths after --voice override."""
    global _VOICE_MODEL, _VOICE_ONNX, _VOICE_JSON, _DETERMINISTIC_CONFIG_PATH
    _VOICE_MODEL = voice
    _VOICE_ONNX = _PIPER_VOICES_DIR / f"{_VOICE_MODEL}.onnx"
    _VOICE_JSON = _PIPER_VOICES_DIR / f"{_VOICE_MODEL}.onnx.json"
    _DETERMINISTIC_CONFIG_PATH = _DETERMINISTIC_CONFIG_DIR / f"{_VOICE_MODEL}-deterministic.onnx.json"

# WASM build artifacts
_WASM_JS = _REPO / "wasm_piper" / "build" / "piper_wasm.js"
_WASM_WASM = _REPO / "wasm_piper" / "build" / "piper_wasm.wasm"

PIP_CMD = [sys.executable, "-m", "pip"]

REQUIRED_PACKAGES = [
    # Base Piper package (onnxruntime, pathvalidate)
    "piper-tts",
    # Dev build deps: scikit-build calls CMake
    "scikit-build<1",
    # Divergence test deps
    "vosk>=0.3.45,<1",
    "soundfile>=0.12,<1",
    "librosa>=0.10,<1",
]

BUILD_TOOLS = [
    # System-level build tools (checked via PATH, not pip)
    "cmake",
]

DEV_PACKAGES = [
    "pytest>=8",
]


def run(cmd, **kwargs):
    """Run a command, raising on failure."""
    print(f"+ {' '.join(cmd)}")
    return subprocess.check_call(cmd, **kwargs)


def _pip_install_satisfied(pkg: str) -> bool:
    """Check if a single pip package is already satisfied."""
    # Strip version specifiers for pip show (e.g. "vosk>=0.3.45,<1" → "vosk")
    name = pkg.split(">=")[0].split("<")[0].split(">")[0].split("=")[0].split("[")[0].strip()
    result = subprocess.run(
        [sys.executable, "-m", "pip", "show", name],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def all_deps_met() -> bool:
    """Check if all Python dependencies are already satisfied."""
    for pkg in REQUIRED_PACKAGES + DEV_PACKAGES:
        if not _pip_install_satisfied(pkg):
            return False
    # Check system build tools
    for tool in BUILD_TOOLS:
        if shutil.which(tool) is None:
            return False
    return True


def _is_emcc_available() -> bool:
    """Check if emcc (Emscripten compiler) is available on PATH."""
    return shutil.which("emcc") is not None


def voice_models_exist() -> bool:
    """Check that voice model files exist in external/piper_voices."""
    return _VOICE_ONNX.exists() and _VOICE_JSON.exists()


def espeak_data_exists() -> bool:
    """Check that espeak-ng-data is available for WASM builds."""
    return _ESPEAK_WASM.exists() and (_ESPEAK_WASM / "phontab").exists()


def deterministic_config_exists() -> bool:
    """Check that the deterministic config file exists."""
    return _DETERMINISTIC_CONFIG_PATH.exists()


def deps_exist() -> bool:
    """Check if all prerequisites are already set up."""
    return (all_deps_met() and _NATIVE_BIN.exists() and VOSK_EXTERNAL_DIR.exists()
            and voice_models_exist() and espeak_data_exists()
            and deterministic_config_exists())


def install_deps():
    """Install Python dependencies."""
    if all_deps_met():
        print("All Python dependencies already satisfied.")
        return
    print("=== Installing Python dependencies ===")
    try:
        run(PIP_CMD + ["install", "--upgrade", "pip"])
        run(PIP_CMD + ["install", "--upgrade", "setuptools", "wheel"])
        for pkg in REQUIRED_PACKAGES:
            run(PIP_CMD + ["install", pkg])
        # Build tools: try pip first, fall back to system packages
        for tool in BUILD_TOOLS:
            if shutil.which(tool) is None:
                run(PIP_CMD + ["install", tool])
                break  # only try one at a time
        run(PIP_CMD + ["install"] + DEV_PACKAGES)
    except subprocess.CalledProcessError as e:
        print(f"pip install failed (rc={e.returncode}).", file=sys.stderr)
        print("If using a system Python, you may need to use a venv or pass --break-system-packages.", file=sys.stderr)
        sys.exit(1)
    print("Dependencies installed.")


def ensure_piper_installed():
    """Build the Piper Python package (prerequisite for CMake-native build)."""
    piper_src = _REPO / "src"
    if piper_src.glob("**/espeakbridge.cpython-*.so"):
        print("Piper Python module already built, skipping.")
        return

    print("=== Building Piper Python package ===")
    run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=_REPO,
    )
    print("Piper Python package built.")


def build_native():
    """Build the native C++ divergence test binary via CMake."""
    print("=== Building native divergence test binary ===")

    ensure_piper_installed()

    if _NATIVE_BIN.exists():
        print(f"Native binary already exists at {_NATIVE_BIN}, skipping build.")
        return

    if _NATIVE_BUILD.exists():
        print(f"Cleaning partial build at {_NATIVE_BUILD}")
        shutil.rmtree(_NATIVE_BUILD)
    _NATIVE_BUILD.mkdir(parents=True, exist_ok=True)

    print("Configuring CMake...")
    result = subprocess.run(
        ["cmake", str(_DIR), "-B", str(_NATIVE_BUILD)],
        capture_output=True,
        text=True,
        cwd=str(_REPO),
    )
    if result.returncode != 0:
        print("CMake configure stderr:", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    print("Building...")
    result = subprocess.run(
        ["cmake", "--build", str(_NATIVE_BUILD), "-j"],
        capture_output=True,
        text=True,
        cwd=str(_REPO),
    )
    if result.returncode != 0:
        print("CMake build stderr:", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    if not _NATIVE_BIN.exists():
        print(f"Error: binary not found at {_NATIVE_BIN}", file=sys.stderr)
        sys.exit(1)

    print(f"Native binary built: {_NATIVE_BIN}")


def download_model():
    """Download the Vosk English speech recognition model to external/."""
    print("=== Downloading Vosk model ===")

    if VOSK_EXTERNAL_DIR.exists() and any(VOSK_EXTERNAL_DIR.rglob("*")):
        print(f"Model already exists at {VOSK_EXTERNAL_DIR}, skipping download.")
        return

    EXTERNAL_DIR.mkdir(parents=True, exist_ok=True)

    if not _MODEL_ZIP.exists():
        print(f"Downloading {_MODEL_URL} ...")
        print("This is ~1.8GB and may take several minutes.")
        urllib.request.urlretrieve(_MODEL_URL, _MODEL_ZIP)
        print("Download complete.")
        print(f"Extracting {_MODEL_ZIP} ...")
        with zipfile.ZipFile(_MODEL_ZIP, "r") as zf:
            zf.extractall(str(_MODEL_ZIP.parent))
        print("Extraction complete.")
    else:
        print(f"Zip already exists at {_MODEL_ZIP}, extracting...")
        with zipfile.ZipFile(_MODEL_ZIP, "r") as zf:
            zf.extractall(str(_MODEL_ZIP.parent))

    print(f"Model available at: {VOSK_EXTERNAL_DIR}")


def download_voices():
    """Download voice models needed for divergence tests."""
    print("=== Downloading voice models ===")
    _PIPER_VOICES_DIR.mkdir(parents=True, exist_ok=True)

    if voice_models_exist():
        print(f"Voice models already exist at {_PIPER_VOICES_DIR}, skipping download.")
        return

    from piper.download_voices import download_voice

    download_voice(_VOICE_MODEL, _PIPER_VOICES_DIR)
    print(f"Voice models available at: {_PIPER_VOICES_DIR}")


def copy_espeak_data():
    """Copy espeak-ng data to WASM test data and external/ directories."""
    print("=== Setting up espeak-ng data for WASM ===")
    if not _ESPEAK_SRC.exists():
        print(f"WARNING: source espeak-ng-data not found at {_ESPEAK_SRC}, skipping.")
        return

    # Copy to wasm_piper/tests/data/
    _WASM_MODEL_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copytree(_ESPEAK_SRC, _ESPEAK_WASM, dirs_exist_ok=True)
    print(f"Copied espeak-ng-data to {_ESPEAK_WASM}")

    # Copy to external/ for WASM CMake preload
    ext_espeak = EXTERNAL_DIR / "espeak-ng-data"
    if not ext_espeak.exists():
        ext_espeak.mkdir(parents=True, exist_ok=True)
        shutil.copytree(_ESPEAK_SRC, ext_espeak, dirs_exist_ok=True)
        print(f"Copied espeak-ng-data to {ext_espeak}")
    elif not espeak_data_exists():
        ext_espeak.mkdir(parents=True, exist_ok=True)
        shutil.copytree(_ESPEAK_SRC, ext_espeak, dirs_exist_ok=True)
        print(f"Copied espeak-ng-data to {ext_espeak}")


def copy_deterministic_config():
    """Generate deterministic config (noise_scale=0, noise_w=0) from the voice model."""
    print("=== Setting up deterministic config ===")
    if _DETERMINISTIC_CONFIG_PATH.exists():
        print(f"Deterministic config already exists, skipping.")
        return

    import json

    source = _PIPER_VOICES_DIR / f"{_VOICE_MODEL}.onnx.json"
    if not source.exists():
        print(f"WARNING: source config not found at {source}, skipping.")
        return

    with open(source) as f:
        cfg = json.load(f)
    cfg["inference"]["noise_scale"] = 0.0
    cfg["inference"]["noise_w"] = 0.0

    _DETERMINISTIC_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(_DETERMINISTIC_CONFIG_PATH, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print(f"Created {_DETERMINISTIC_CONFIG_PATH}")


def build_wasm():
    """Build WASM piper binary via wasm_piper/build.py."""
    print("=== Building WASM piper binary ===")

    if _WASM_JS.exists() and _WASM_WASM.exists():
        print(f"WASM build already exists, skipping.")
        return

    build_script = _REPO / "wasm_piper" / "build.py"
    print("Running wasm_piper/build.py (this may take a while)...")
    result = subprocess.run(
        [sys.executable, str(build_script)],
        capture_output=True, text=True,
        cwd=str(_REPO),
    )
    if result.returncode != 0:
        print("WASM build failed:", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        return

    if _WASM_JS.exists() and _WASM_WASM.exists():
        print(f"WASM build complete: {_WASM_JS}, {_WASM_WASM}")
    else:
        print("Warning: build reported success but artifacts not found.", file=sys.stderr)


def clean():
    """Remove build artifacts."""
    print("=== Cleaning build artifacts ===")
    for d in [_NATIVE_BUILD, _REPO / "build"]:
        if d.exists():
            print(f"Removing {d}")
            shutil.rmtree(d)
    # Clean WASM test data and deterministic config
    for f in [_ESPEAK_WASM, _DETERMINISTIC_CONFIG_PATH]:
        if f.exists():
            if f.is_symlink():
                f.unlink()
            elif f.is_dir():
                shutil.rmtree(f)
            print(f"Removing {f}")
    print("Clean complete.")


def main():
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
        default=_DEFAULT_VOICE,
        metavar="VOICE",
        help="Voice to use for divergence tests (default: %(default)s)",
    )
    parser.add_argument(
        "command",
        nargs="?",
        default="all",
        choices=[
            "all", "deps", "build-native", "download-model",
            "download-voices", "espeak-data", "deterministic-config",
            "build-wasm", "clean",
        ],
        help="Which step to run (default: all)",
    )
    args = parser.parse_args()

    if args.list_voices:
        from piper.download_voices import list_voices
        list_voices()
        return

    _recompute_voice_paths(args.voice)

    # When running all steps, exit early if everything is already set up
    if args.command == "all" and deps_exist():
        print("All dependencies, native binary, and models are already set up.")
        return

    step_map = {
        "all": ["deps", "build-native", "download-voices", "espeak-data",
                "deterministic-config", "download-model", "build-wasm"],
        "deps": ["deps"],
        "build-native": ["build-native"],
        "download-model": ["download-model"],
        "download-voices": ["download-voices"],
        "espeak-data": ["espeak-data"],
        "deterministic-config": ["deterministic-config"],
        "build-wasm": ["build-wasm"],
        "clean": ["clean"],
    }

    for step in step_map[args.command]:
        if step == "deps":
            install_deps()
        elif step == "build-native":
            build_native()
        elif step == "download-model":
            download_model()
        elif step == "download-voices":
            download_voices()
        elif step == "espeak-data":
            copy_espeak_data()
        elif step == "deterministic-config":
            copy_deterministic_config()
        elif step == "build-wasm":
            build_wasm()
        elif step == "clean":
            clean()

    if args.command != "clean":
        print("Setup complete.")


if __name__ == "__main__":
    main()
