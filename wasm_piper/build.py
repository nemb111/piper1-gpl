#!/usr/bin/env python3
"""Build script for WASM Piper.

Downloads pinned Node.js and Emscripten SDK, installs onnxruntime-web,
configures and builds the WASM target via CMake, and downloads the default
voice (en_US-lessac-medium) if not present.

Steps are idempotent: already-installed tools are skipped.

Usage:
    python3 build.py              # run all steps + download default voice
    python3 build.py download-tools   # download Node.js + Emscripten only
    python3 build.py npm-install        # install onnxruntime-web only
    python3 build.py cmake              # configure CMake only
    python3 build.py build              # build WASM only
    python3 build.py clean              # remove build artifacts
    python3 build.py --list-voices      # list all available voices
    python3 build.py --voice en_US-amy-low  # download specified voice(s)
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

# ── Pinned versions (from cmake/emscripten/options.cmake, cmake/emscripten/find_npm.cmake) ──
NODE_VERSION = "22.16.0"
EMSCRIPTEN_VERSION = "5.0.6"
CMAKE_MIN_VERSION = "3.26"
NODE_PLATFORM = "linux-x64"
NODE_SHA256 = "f4cb75bb036f0d0eddf6b79d9596df1aaab9ddccd6a20bf489be5abe9467e84e"

_DIR = Path(__file__).resolve().parent
_REPO = _DIR.parent
_EXTERNAL_DIR = EXTERNAL_DIR = Path(os.path.realpath(str(_REPO / "external")))
_BUILD_DIR_PATH = Path(os.path.realpath(str(_DIR / "build")))
BUILD_DIR = _BUILD_DIR_PATH

NODE_DOWNLOAD_DIR = EXTERNAL_DIR / f"node-v{NODE_VERSION}"
NODE_BIN = NODE_DOWNLOAD_DIR / "bin" / "node"
NPM_BIN = NODE_DOWNLOAD_DIR / "bin" / "npm"
NODE_TARBALL = f"node-v{NODE_VERSION}-{NODE_PLATFORM}.tar.xz"
NODE_URL = f"https://nodejs.org/dist/v{NODE_VERSION}/{NODE_TARBALL}"

EMSDK_DIR = EXTERNAL_DIR / f"emsdk-{EMSCRIPTEN_VERSION}"
EMSDK_TARBALL_URL = (
    f"https://github.com/emscripten-core/emsdk/archive/refs/tags/"
    f"{EMSCRIPTEN_VERSION}.tar.gz"
)
EMCC = EMSDK_DIR / "emsdk" / "upstream" / "emscripten" / "emcc"

ORT_NODE_MODULES = _DIR / "node_modules" / "onnxruntime-web"

_BUILD_TOOLS = ["cmake"]


def run(cmd, **kwargs):
    """Run a command, raising on failure."""
    print(f"+ {' '.join(cmd)}")
    return subprocess.check_call(cmd, **kwargs)


def which(name: str) -> str | None:
    return shutil.which(name)


# ── Download tools ────────────────────────────────────────────────


def _cached_dir(name: Path) -> Path:
    """Return a cache dir inside build/external/."""
    d = BUILD_DIR / "external" / name
    d.mkdir(parents=True, exist_ok=True)
    return d


def ensure_node() -> None:
    """Download and extract Node.js binary distribution if not present."""
    if NODE_BIN.exists():
        print(f"Node.js {NODE_VERSION} already at {NODE_DOWNLOAD_DIR}")
        return

    print(f"Downloading Node.js {NODE_VERSION}...")
    tarball = _cached_dir("node") / NODE_TARBALL

    tmp_tarball = Path(str(tarball) + ".tmp")
    if not tarball.exists():
        run(["curl", "-fSL", "--progress-bar", NODE_URL, "-o", str(tmp_tarball)])

        # Verify SHA-256
        result = subprocess.run(
            ["sha256sum", str(tmp_tarball)], capture_output=True, text=True
        )
        actual_hash = result.stdout.split()[0]
        if actual_hash != NODE_SHA256:
            tmp_tarball.unlink()
            print(f"SHA-256 mismatch: got {actual_hash}, expected {NODE_SHA256}", file=sys.stderr)
            sys.exit(1)
        tmp_tarball.rename(tarball)
    else:
        print("Node.js tarball cached")

    if NODE_DOWNLOAD_DIR.exists():
        shutil.rmtree(NODE_DOWNLOAD_DIR)
    NODE_DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    run(["tar", "xf", str(tarball), "--strip-components=1"], cwd=str(NODE_DOWNLOAD_DIR))
    print(f"Node.js {NODE_VERSION} installed to {NODE_DOWNLOAD_DIR}")


def ensure_emscripten() -> None:
    """Download and install Emscripten SDK if not present."""
    if EMCC.exists():
        print(f"Emscripten {EMSCRIPTEN_VERSION} already at {EMSDK_DIR}")
        return

    print(f"Downloading Emscripten SDK {EMSCRIPTEN_VERSION}...")
    tarball = _cached_dir("emsdk") / f"emsdk-{EMSCRIPTEN_VERSION}.tar.gz"

    if not tarball.exists():
        run(["curl", "-fSL", "--progress-bar", EMSDK_TARBALL_URL, "-o", str(tarball)])

    work_dir = EMSDK_DIR
    if work_dir.exists():
        print(f"Removing stale installation at {work_dir}")
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True, exist_ok=True)
    run(["tar", "xf", str(tarball), "--strip-components=1"], cwd=str(work_dir))

    # Install and activate
    env = os.environ.copy()
    env["PATH"] = str(work_dir) + os.pathsep + env.get("PATH", "")

    print("Installing Emscripten...")
    run(
        ["python3", str(work_dir / "emsdk.py"), "install", EMSCRIPTEN_VERSION],
        cwd=str(work_dir),
        env=env,
    )

    print("Activating Emscripten...")
    run(
        ["python3", str(work_dir / "emsdk.py"), "activate", EMSCRIPTEN_VERSION],
        cwd=str(work_dir),
        env=env,
    )
    print(f"Emscripten {EMSCRIPTEN_VERSION} installed to {EMSDK_DIR}")


def ensure_tools() -> None:
    """Ensure Node.js and Emscripten are downloaded and installed."""
    ensure_node()
    ensure_emscripten()


# ── npm ───────────────────────────────────────────────────────────


def npm_install() -> None:
    """Install onnxruntime-web via npm."""
    if ORT_NODE_MODULES.exists():
        print("onnxruntime-web already installed")
        return

    print("Installing onnxruntime-web via npm...")
    env = os.environ.copy()
    env["PATH"] = str(NODE_DOWNLOAD_DIR / "bin") + os.pathsep + env.get("PATH", "")
    run([str(NPM_BIN), "install"], cwd=str(_DIR), env=env)
    print("onnxruntime-web installed")


# ── CMake ─────────────────────────────────────────────────────────


def _build_env() -> dict:
    """Return env with Node.js and Emscripten on PATH."""
    env = os.environ.copy()
    parts = [str(NODE_DOWNLOAD_DIR / "bin"), str(EMSDK_DIR / "emsdk")]
    env["PATH"] = os.pathsep.join(parts) + os.pathsep + env.get("PATH", "")
    return env


def _data_dir_for_build() -> Path:
    """Resolve the external/ directory to a canonical path.

    CMAKE_CURRENT_SOURCE_DIR may resolve differently on different mount points
    (e.g. /home/claude/... vs /mnt/agent_workspace/...). Always return the
    realpath so the --preload-file paths are absolute and unambiguous.
    """
    candidate = _DIR / "../external"
    if candidate.is_dir():
        return Path(os.path.realpath(str(candidate)))
    # Fallback: try the realpath of _DIR
    real = Path(os.path.realpath(_DIR))
    fallback = real / "../external"
    if fallback.is_dir():
        return fallback
    return Path(os.path.realpath(str(candidate)))




def cmake_configure() -> None:
    """Run CMake to configure the WASM build."""
    print("=== Configuring CMake ===")

    # Validate that the data dir CMake would preload actually exists.
    # The CMakeLists.txt uses ${PIPER_WASM_DATA_DIR}/espeak-ng-data@/ and
    # ${PIPER_WASM_DATA_DIR}/piper_voices@/ which may resolve to a
    # different mount point. We verify the realpath exists and tell CMake
    # to override via cache variable.
    data_dir = _data_dir_for_build()
    if not data_dir.is_dir():
        print(f"Error: data directory not found at {data_dir}", file=sys.stderr)
        sys.exit(1)

    # Ensure build directory exists; CMake handles incremental reconfigure.
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    # Force the real repo root path so CMake resolves all paths correctly
    # (dual mount-point: /mnt/agent_workspace/ vs /home/claude/workspace/)
    real_repo = Path(os.path.realpath(str(_REPO)))
    real_data_dir = Path(os.path.realpath(str(data_dir)))

    run(
        [
            "cmake",
            str(_DIR),
            f"-B{BUILD_DIR}",
            f"-DCMAKE_BUILD_TYPE=Release",
            f"-DPIPER_WASM_DATA_DIR={real_data_dir}",
            f"-DCMAKE_BINARY_DIR={BUILD_DIR}",
        ],
        cwd=str(real_repo),
        env=_build_env(),
    )
    print("CMake configured")


def cmake_build() -> None:
    """Run CMake build (compile WASM)."""
    print("=== Building WASM ===")
    # Fast-path: if output already exists, cmake --build would be a no-op.
    # Skip spawning cmake just to discover it's up to date.
    if not (BUILD_DIR / "piper_wasm.js").exists():
        nproc = os.cpu_count() or 4
        run(
            ["cmake", "--build", str(BUILD_DIR), f"-j{nproc}"],
            cwd=str(Path(os.path.realpath(str(_REPO)))),
            env=_build_env(),
        )
    print(f"WASM build complete (output in {BUILD_DIR})")


# ── System checks ─────────────────────────────────────────────────


def check_cmake() -> None:
    """Verify cmake is available and meets minimum version."""
    cmake = which("cmake")
    if not cmake:
        print("cmake not found on PATH. Install it first.", file=sys.stderr)
        sys.exit(1)

    result = subprocess.run([cmake, "--version"], capture_output=True, text=True)
    actual = result.stdout.splitlines()[0].split()[-1]

    def ver(s: str) -> tuple:
        return tuple(int(x) for x in s.split("."))

    if ver(actual) < ver(CMAKE_MIN_VERSION):
        print(f"cmake {actual} found, but >= {CMAKE_MIN_VERSION} required.", file=sys.stderr)
        sys.exit(1)


def tools_exist() -> bool:
    """Check if Node.js and Emscripten are already installed."""
    return NODE_BIN.exists() and EMCC.exists()


def deps_exist() -> bool:
    """Check if everything is already set up."""
    if not tools_exist():
        return False
    if not ORT_NODE_MODULES.exists():
        return False
    # Check cmake
    if which("cmake") is None:
        return False
    return True


# ── Cleanup ───────────────────────────────────────────────────────


def clean() -> None:
    """Remove build artifacts."""
    print("=== Cleaning build artifacts ===")
    if BUILD_DIR.exists():
        print(f"Removing {BUILD_DIR}")
        shutil.rmtree(BUILD_DIR)
    print("Clean complete.")


# ── Main ──────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(description="Build WASM Piper")
    parser.add_argument(
        "command",
        nargs="?",
        default="all",
        choices=[
            "all",
            "download-tools",
            "npm-install",
            "cmake",
            "build",
            "clean",
        ],
        help="Which step to run (default: all)",
    )
    parser.add_argument(
        "--list-voices",
        action="store_true",
        help="List all available Piper voices and exit",
    )
    parser.add_argument(
        "--voice",
        nargs="+",
        metavar="VOICE",
        help="Download the specified voice(s) to external/ and exit",
    )
    args = parser.parse_args()

    if args.list_voices:
        from piper.download_voices import list_voices
        list_voices()
        return

    if args.voice:
        from piper.download_voices import download_voice
        target_dir = _EXTERNAL_DIR / "piper_voices"
        target_dir.mkdir(parents=True, exist_ok=True)
        for voice_name in args.voice:
            download_voice(voice_name, target_dir)
        print(f"Voice(s) downloaded to {target_dir}")
        return

    # Download default voice if not present
    DEFAULT_VOICE = "en_US-lessac-medium"
    VOICE_DIR = _EXTERNAL_DIR / "piper_voices"
    default_model = VOICE_DIR / f"{DEFAULT_VOICE}.onnx"
    if not default_model.exists():
        print(f"Downloading default voice {DEFAULT_VOICE}...")
        VOICE_DIR.mkdir(parents=True, exist_ok=True)
        from piper.download_voices import download_voice
        download_voice(DEFAULT_VOICE, VOICE_DIR)

    # When running the default "all" step and everything is already set up,
    # skip the pipeline entirely. Individual subcommands (cmake, build, etc.)
    # are always executed regardless.
    if args.command == "all" and deps_exist():
        print("Tools and dependencies are already installed, nothing to do.")
        return

    step_map = {
        "all": ["download-tools", "npm-install", "cmake", "build"],
        "download-tools": ["download-tools"],
        "npm-install": ["npm-install"],
        "cmake": ["cmake"],
        "build": ["build"],
        "clean": ["clean"],
    }

    for step in step_map[args.command]:
        if step == "download-tools":
            check_cmake()
            ensure_tools()
        elif step == "npm-install":
            check_cmake()
            npm_install()
        elif step == "cmake":
            check_cmake()
            cmake_configure()
        elif step == "build":
            check_cmake()
            cmake_build()
        elif step == "clean":
            clean()

    if args.command != "clean":
        print("Setup complete.")


if __name__ == "__main__":
    main()
