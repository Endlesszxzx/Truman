#!/usr/bin/env bash
# Incrementally build the AnalyzerDBM plugin used by generate-dbm.sh.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# Keep the script default aligned with the repository's shared
# CMakePresets.json "llvm17-dbm" preset.  A developer can still point to a
# private CLion build tree through TRUMAN_DBM_BUILD_DIR.
BUILD_DIR="${TRUMAN_DBM_BUILD_DIR:-$ROOT/build/clion-truman-llvm17-dbm}"
CMAKE_BIN="${CMAKE_BIN:-/usr/bin/cmake}"

[[ -f "$BUILD_DIR/CMakeCache.txt" ]] || {
    printf 'AnalyzerDBM build error: CLion DBM build directory is not configured: %s\n' "$BUILD_DIR" >&2
    exit 2
}
[[ -x "$CMAKE_BIN" ]] || {
    printf 'AnalyzerDBM build error: CMake executable not found: %s\n' "$CMAKE_BIN" >&2
    exit 2
}

exec "$CMAKE_BIN" --build "$BUILD_DIR" --target AnalyzerDBM --parallel "${TRUMAN_DBM_JOBS:-2}"
