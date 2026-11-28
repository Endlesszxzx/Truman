#!/usr/bin/env bash
# Generate a DBM for one linked driver LLVM bitcode module.
#
# Usage:
#   generate-dbm.sh <driver.bc> [driver-id] [result.bin]
#
# The script is deliberately self-contained so it can be used by a CLion
# External Tool: it first incrementally builds AnalyzerDBM, then invokes the
# LLVM 17 pass plugin.  The driver-id only labels the produced Device protobuf;
# the selected .bc module is what determines the code being analysed.

set -euo pipefail

die() {
    printf 'DBM generation error: %s\n' "$*" >&2
    exit 2
}

usage() {
    cat <<'EOF'
Usage: generate-dbm.sh <driver.bc> [driver-id] [result.bin]
       generate-dbm.sh --run-configuration-finished

  driver.bc  A linked PCI/platform driver LLVM bitcode module.
  driver-id  Optional DBM label; defaults to the .bc filename without .bc.
  result.bin Optional result path; defaults to out/dbm/<driver-id>/<driver-id>.bin.

The script also writes result.txt and result.json beside result.bin.

In CLion, set these arguments in Run | Edit Configurations | Generate DBM |
Script options.  Use a linked driver .bc, not an individual .bc compilation
unit.
EOF
}

if [[ ${1:-} == "--run-configuration-finished" && $# -eq 1 ]]; then
    # Reserved for callers that perform generation in a Before launch task.
    # The project Run configuration normally calls this script directly.
    printf '[DBM] Generation completed in the preceding Before launch step.\n'
    exit 0
fi

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
    exit 0
fi

[[ $# -ge 1 && $# -le 3 ]] || {
    die "missing driver .bc; set it in Run | Edit Configurations | Generate DBM | Script options"
}

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
BITCODE_INPUT="$1"
[[ -f "$BITCODE_INPUT" ]] || die "bitcode file does not exist: $BITCODE_INPUT"
[[ "$BITCODE_INPUT" == *.bc ]] || die "expected a linked .bc file, got: $BITCODE_INPUT"
BITCODE="$(readlink -f -- "$BITCODE_INPUT")"

default_driver="$(basename -- "$BITCODE" .bc)"
DRIVER_ID="${2:-$default_driver}"
[[ -n "$DRIVER_ID" ]] || DRIVER_ID="$default_driver"
[[ "$DRIVER_ID" =~ ^[[:alnum:]_.-]+$ ]] || \
    die "driver-id may contain only letters, digits, '.', '_' and '-': $DRIVER_ID"

if [[ -n ${3:-} ]]; then
    RESULT="$3"
else
    RESULT="$ROOT/out/dbm/$DRIVER_ID/$DRIVER_ID.bin"
fi
[[ "$RESULT" == *.bin ]] || die "result path must end in .bin: $RESULT"
if [[ "$RESULT" != /* ]]; then
    RESULT="$ROOT/$RESULT"
fi
RESULT_DIR="$(dirname -- "$RESULT")"
mkdir -p -- "$RESULT_DIR"
RESULT="$(cd -- "$RESULT_DIR" && pwd -P)/$(basename -- "$RESULT")"

# Match the repository's shared CMakePresets.json "llvm17-dbm" preset.
# TRUMAN_DBM_BUILD_DIR remains available for a private CLion build tree.
BUILD_DIR="${TRUMAN_DBM_BUILD_DIR:-$ROOT/build/clion-truman-llvm17-dbm}"
[[ -f "$BUILD_DIR/CMakeCache.txt" ]] || \
    die "CLion DBM build directory is not configured: $BUILD_DIR"

CMAKE_BIN="${CMAKE_BIN:-/usr/bin/cmake}"
OPT_BIN="${LLVM_OPT_BIN:-/usr/lib/llvm-17/bin/opt}"
PLUGIN="$BUILD_DIR/static_analysis/Analyzer/libAnalyzerDBM.so"

[[ -x "$CMAKE_BIN" ]] || die "CMake executable not found: $CMAKE_BIN"
[[ -x "$OPT_BIN" ]] || die "LLVM 17 opt executable not found: $OPT_BIN"

printf '[DBM] Building AnalyzerDBM incrementally...\n'
"$CMAKE_BIN" --build "$BUILD_DIR" --target AnalyzerDBM --parallel "${TRUMAN_DBM_JOBS:-2}"
[[ -f "$PLUGIN" ]] || die "AnalyzerDBM build completed but plugin is missing: $PLUGIN"

printf '[DBM] Analysing: %s\n' "$BITCODE"
printf '[DBM] Driver id: %s\n' "$DRIVER_ID"
printf '[DBM] Result: %s\n' "$RESULT"
"$OPT_BIN" \
    --disable-output \
    -load-pass-plugin "$PLUGIN" \
    -passes=truman-dbm \
    "-target=$DRIVER_ID" \
    "-result=$RESULT" \
    "$BITCODE"

for artifact in "$RESULT" "${RESULT%.bin}.txt" "${RESULT%.bin}.json"; do
    [[ -s "$artifact" ]] || die "analysis completed but did not produce: $artifact"
done

printf '[DBM] Done.\n'
printf '  %s\n' "$RESULT" "${RESULT%.bin}.txt" "${RESULT%.bin}.json"
