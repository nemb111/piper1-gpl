#!/usr/bin/env python3
"""Clone and build ONNX Runtime for WebAssembly, matching cmake/onnxruntime_web_external.cmake.

Outputs:
  external/onnxruntime/libonnxruntime_webassembly.a

Usage:
    python3 script/build_onnxruntime_web.py [--version 1.25.0]
    python3 script/build_onnxruntime_web.py --extra-args --parallel 3
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "external" / "onnxruntime"
LIB_FILE = SRC_DIR / "libonnxruntime_webassembly.a"
VERSION = "1.25.0"

def run(cmd, **kwargs):
    print(f"+ {' '.join(str(a) for a in cmd)}")
    return subprocess.run(cmd, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default=VERSION)
    parser.add_argument("--extra-args", nargs=argparse.REMAINDER, default=[],
                        help="Extra args passed to build.sh (e.g. --parallel 3)")
    args = parser.parse_args()

    lib_file = str(LIB_FILE)
    if os.path.exists(lib_file):
        print(f"Library already exists: {lib_file}")
        return 0

    if not SRC_DIR.exists():
        print(f"Cloning onnxruntime v{args.version} ...")
        run([
            "git", "clone",
            f"--branch", f"v{args.version}",
            "--depth", "1",
            "--recurse-submodules",
            "https://github.com/microsoft/onnxruntime.git",
            str(SRC_DIR),
        ])
    else:
        print(f"Source already exists at {SRC_DIR} (skipping clone)")

    env = os.environ.copy()
    emscripten_path = str(SRC_DIR / "emsdk_port_dir" / "emsdk" / "upstream" / "emscripten")
    env["PATH"] = f"{emscripten_path}:{env.get('PATH', '')}"
    env["PYTHON"] = sys.executable

    run([
        str(SRC_DIR / "build.sh"),
        "--build_wasm_static_lib",
        "--config", "Release",
        "--skip_tests",
        *args.extra_args,
    ], env=env)


if __name__ == "__main__":
    sys.exit(main() or 0)
