#!/usr/bin/env python3
"""Setup script for Piper divergence tests.

Installs Python dependencies, builds the native C++ test binary via CMake,
downloads voice models and the Vosk speech recognition model, copies
espeak-ng data for WASM, and builds WASM if Emscripten is available.

Usage:
    python setup.py                      # run all steps (skip if already set up)
    python setup.py deps                 # install Python dependencies only
    python setup.py build-native         # build native binary only
    python setup.py download-model       # download Vosk model only
    python setup.py download-voices      # download voice models only
    python setup.py espeak-data          # copy espeak-ng data for WASM
    python setup.py build-wasm           # build WASM binary (if emcc available)
    python setup.py clean               # remove build artifacts
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

# Voice model for divergence tests
_VOICE_MODEL = "en_US-lessac-medium"
_VOICE_ONNX = EXTERNAL_DIR / f"{_VOICE_MODEL}.onnx"
_VOICE_JSON = EXTERNAL_DIR / f"{_VOICE_MODEL}.onnx.json"
_WASM_MODEL_DIR = _REPO / "wasm_piper" / "tests" / "data"
_WASM_MODEL_ONNX = _WASM_MODEL_DIR / f"{_VOICE_MODEL}.onnx"
_WASM_MODEL_JSON = _WASM_MODEL_DIR / f"{_VOICE_MODEL}.onnx.json"
_ESPEAK_SRC = _REPO / "src" / "piper" / "espeak-ng-data"
_ESPEAK_WASM = _WASM_MODEL_DIR / "espeak-ng-data"

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
    """Check that voice model files and WASM symlinks exist."""
    return _VOICE_ONNX.exists() and _VOICE_JSON.exists() and _WASM_MODEL_ONNX.exists() and _WASM_MODEL_JSON.exists()


def espeak_data_exists() -> bool:
    """Check that espeak-ng-data is available for WASM builds."""
    return _ESPEAK_WASM.exists() and (_ESPEAK_WASM / "phontab").exists()


def deps_exist() -> bool:
    """Check if all prerequisites are already set up."""
    return (all_deps_met() and _NATIVE_BIN.exists() and VOSK_EXTERNAL_DIR.exists()
            and voice_models_exist() and espeak_data_exists())


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
    if voice_models_exist():
        print(f"Voice models already exist at {EXTERNAL_DIR}, skipping download.")
        return

    EXTERNAL_DIR.mkdir(parents=True, exist_ok=True)
    _WASM_MODEL_DIR.mkdir(parents=True, exist_ok=True)

    # HuggingFace path: en/en_US/lessac/medium/en_US-lessac-medium.onnx
    # Extract: "en_US-lessac-medium" -> language="en_US", voice="lessac", level="medium"
    parts = _VOICE_MODEL.split("-")
    language = parts[0]  # "en_US"
    level = parts[-1]     # "medium"
    voice = "-".join(parts[1:-1])  # "lessac"
    onnx_url = (
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/"
        f"en/{language}/{voice}/{level}/{_VOICE_MODEL}.onnx?download=true"
    )
    json_url = (
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/"
        f"en/{language}/{voice}/{level}/{_VOICE_MODEL}.onnx.json?download=true"
    )

    onnx_path = EXTERNAL_DIR / f"{_VOICE_MODEL}.onnx"
    json_path = EXTERNAL_DIR / f"{_VOICE_MODEL}.onnx.json"

    for url, path in [(onnx_url, onnx_path), (json_url, json_path)]:
        if not path.exists() or path.stat().st_size == 0:
            print(f"  DL {path.name}...")
            urllib.request.urlretrieve(url, str(path))
            print(f"  OK  {path.name} ({path.stat().st_size / 1_000_000:.1f}MB)")
        else:
            print(f"  SKIP {path.name} (already exists)")

    # Create symlinks in wasm_piper/tests/data/
    if not _WASM_MODEL_ONNX.exists():
        _WASM_MODEL_ONNX.symlink_to(
            Path("../../../external") / f"{_VOICE_MODEL}.onnx"
        )
        print(f"  LINK  {_WASM_MODEL_ONNX.name} -> ../../../external/{_VOICE_MODEL}.onnx")
    if not _WASM_MODEL_JSON.exists():
        _WASM_MODEL_JSON.symlink_to(
            Path("../../../external") / f"{_VOICE_MODEL}.onnx.json"
        )
        print(f"  LINK  {_WASM_MODEL_JSON.name} -> ../../../external/{_VOICE_MODEL}.onnx.json")

    print(f"Voice models available at: {EXTERNAL_DIR}")


def copy_espeak_data():
    """Copy espeak-ng data to WASM test data directory."""
    print("=== Setting up espeak-ng data for WASM ===")
    if espeak_data_exists():
        print(f"espeak-ng-data already exists at {_ESPEAK_WASM}, skipping.")
        return

    if not _ESPEAK_SRC.exists():
        print(f"WARNING: source espeak-ng-data not found at {_ESPEAK_SRC}, skipping.")
        return

    _WASM_MODEL_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copytree(_ESPEAK_SRC, _ESPEAK_WASM, dirs_exist_ok=True)
    print(f"Copied espeak-ng-data to {_ESPEAK_WASM}")


def build_wasm():
    """Build WASM piper binary if Emscripten is available."""
    print("=== Building WASM piper binary ===")

    if _WASM_JS.exists() and _WASM_WASM.exists():
        print(f"WASM build already exists, skipping.")
        return

    if not _is_emcc_available():
        print("Emscripten (emcc) not found on PATH. Skipping WASM build.")
        print("Run: python3 build.py  (in root repo) to install Emscripten.")
        return

    # Ensure CMake build dir exists and is configured
    build_dir = _REPO / "wasm_piper" / "build"
    if not (build_dir / "CMakeCache.txt").exists():
        print("Configuring CMake for WASM build...")
        result = subprocess.run(
            ["cmake", "-B", str(build_dir), "-S", str(_REPO / "wasm_piper")],
            capture_output=True, text=True,
            cwd=str(_REPO),
        )
        if result.returncode != 0:
            print("CMake configure stderr:", file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            print("WASM build failed. Install Emscripten first, then try again.")
            return

    print("Building WASM...")
    result = subprocess.run(
        ["cmake", "--build", str(build_dir), "-j"],
        capture_output=True, text=True,
        cwd=str(_REPO),
    )
    if result.returncode != 0:
        print("CMake build stderr:", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        print("WASM build failed.")
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
    # Clean WASM test data (not the external dir)
    for f in [_WASM_MODEL_ONNX, _WASM_MODEL_JSON, _ESPEAK_WASM]:
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
        "command",
        nargs="?",
        default="all",
        choices=[
            "all", "deps", "build-native", "download-model",
            "download-voices", "espeak-data", "build-wasm", "clean",
        ],
        help="Which step to run (default: all)",
    )
    args = parser.parse_args()

    # When running all steps, exit early if everything is already set up
    if args.command == "all" and deps_exist():
        print("All dependencies, native binary, and models are already set up.")
        return

    step_map = {
        "all": ["deps", "build-native", "download-voices", "espeak-data", "download-model", "build-wasm"],
        "deps": ["deps"],
        "build-native": ["build-native"],
        "download-model": ["download-model"],
        "download-voices": ["download-voices"],
        "espeak-data": ["espeak-data"],
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
        elif step == "build-wasm":
            build_wasm()
        elif step == "clean":
            clean()

    if args.command != "clean":
        print("Setup complete.")


if __name__ == "__main__":
    main()
