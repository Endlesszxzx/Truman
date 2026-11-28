#!/usr/bin/env bash
# Generate LLVM bitcode for one Linux kernel driver module via Kbuild.
#
# Usage:
#   generate-bc.sh <driver> [build-dir]
#
# <driver> is either a module name (e.g. qat_420xx, natsemi, 3w-9xxx),
# which is resolved automatically against the kernel Makefiles, or a full
# Kbuild module object path (e.g. drivers/net/ethernet/natsemi/natsemi.o,
# the .o suffix is optional).  <module>.bc and .ll are produced beside the
# module .o inside the Kbuild output directory.
#
# The Kbuild output directory defaults to $TRUMAN_BC_BUILD_DIR or the
# shared allmodconfig tree under build/linux; it is created and configured
# with allmodconfig on first use.

set -euo pipefail

die() {
    printf 'Bitcode generation error: %s\n' "$*" >&2
    exit 2
}

usage() {
    cat <<'EOF'
Usage: generate-bc.sh <driver> [build-dir]

  driver         Module name, auto-resolved via the kernel Makefiles
                 (e.g. qat_420xx, natsemi, 3w-9xxx), or a kernel-relative
                 module object path like drivers/net/ethernet/natsemi/natsemi.o
                 (.o optional).
  build-dir      Optional Kbuild O= directory; defaults to
                 $TRUMAN_BC_BUILD_DIR or the shared allmodconfig tree.

The script runs Kbuild through the clang/ld wrapper scripts, so each .c
also emits a .bc and multi-object modules are merged with llvm-link into
<module>.bc.  Follow up with generate-dbm.sh to obtain the DBM.
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
    exit 0
fi

[[ $# -ge 1 && $# -le 2 ]] || {
    usage >&2
    exit 2
}

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
LINUX="$ROOT/third_party/linux"
[[ -f "$LINUX/Makefile" ]] || \
    die "Linux source tree is missing: $LINUX (initialize third_party/linux first)"

# The toolchain bundle provides the host-tool headers and libraries Kbuild
# itself needs (e.g. libelf for objtool); source it before pinning PATH to
# LLVM 17 so the toolchain's LLVM 13 cannot win clang/llvm-link resolution.
TOOLCHAIN_ENV="$ROOT/install/e1000-toolchain/env.sh"
[[ -f "$TOOLCHAIN_ENV" ]] || \
    die "Host toolchain environment is missing: $TOOLCHAIN_ENV"
# shellcheck disable=SC1091
source "$TOOLCHAIN_ENV"

# Every tool the wrappers invoke (clang, llvm-link, llvm-dis) must come
# from the same LLVM major version as the analyzer.
LLVM_BIN="${TRUMAN_LLVM_BIN:-/usr/lib/llvm-17/bin}"
[[ -x "$LLVM_BIN/clang" ]] || die "LLVM clang not found: $LLVM_BIN/clang"
export PATH="$LLVM_BIN:$PATH"
export CLANG="$LLVM_BIN/clang"

# Resolve the user input into a Kbuild module object target.  A bare name
# (qat_420xx) is looked up in the kernel Makefiles: the "obj-$(CONFIG_*)
# += <name>.o" line reveals both the module and the directory declaring it.
resolve_driver() {
    local input="$1" hits candidates=() hit dir mod
    if [[ "$input" == */* ]]; then
        local target="${input#/}"
        target="${target%/}"
        target="${target%.o}"
        RESOLVED_TARGET="$target.o"
        return 0
    fi

    local esc
    esc=$(printf '%s' "$input" | sed -e 's/[.+*?]/\\&/g')
    hits=$(grep -rn --include=Makefile -E \
        "obj-[^=]*\+=[[:space:]]*${esc}\.o([[:space:]]|$)" "$LINUX" 2>/dev/null || true)
    if [[ -z "$hits" ]]; then
        # Fall back to a substring match (e.g. "420xx" -> qat_420xx.o).
        hits=$(grep -rn --include=Makefile -E \
            "obj-[^=]*\+=[[:space:]]*[A-Za-z0-9_-]*${esc}[A-Za-z0-9_-]*\.o([[:space:]]|$)" \
            "$LINUX" 2>/dev/null || true)
    fi

    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        dir="${hit%%:*}"
        dir="$(dirname -- "$dir")"
        dir="${dir#"$LINUX"/}"
        mod="${hit##*:}"
        mod="${mod##*+=}"
        mod="${mod//[[:space:]]/}"
        mod="${mod%%.o*}"
        [[ -n "$dir" && "$dir" != "." && -n "$mod" ]] || continue
        candidates+=("$dir/$mod.o")
    done <<< "$hits"

    local unique
    unique=$(printf '%s\n' "${candidates[@]:-}" | sort -u | grep -v '^$' || true)
    local count
    count=$(printf '%s\n' "$unique" | grep -c . || true)
    if [[ "$count" -eq 1 ]]; then
        RESOLVED_TARGET="$unique"
        return 0
    fi
    if [[ "$count" -eq 0 ]]; then
        die "No kernel Makefile declares a module named '$input'; pass a full path like drivers/net/ethernet/natsemi/natsemi.o"
    fi
    printf 'Ambiguous driver name: %s\n' "$input" >&2
    printf '%s\n' "$unique" | sed 's/^/  candidate: /' >&2
    die "Pass one of the paths above (or the exact module name) as <driver>"
}

resolve_driver "$1"
MODULE_TARGET="$RESOLVED_TARGET"
[[ "$MODULE_TARGET" != /* && "$MODULE_TARGET" != ..* ]] || \
    die "module target must be kernel-relative: $MODULE_TARGET"
if [[ "$1" != */* ]]; then
    printf '[BC] Resolved %s -> %s\n' "$1" "$MODULE_TARGET"
fi

BUILD_DIR="${2:-${TRUMAN_BC_BUILD_DIR:-$ROOT/build/linux/v7.3}}"
mkdir -p -- "$BUILD_DIR"
BUILD_DIR="$(cd -- "$BUILD_DIR" && pwd)"

WRAP="$ROOT/scripts/shell"
BASE=(make -C "$LINUX" "O=$BUILD_DIR"
    "CC=$WRAP/clang.sh" "AR=$WRAP/ar.sh" "LD=$WRAP/ld.sh" "OBJCOPY=$WRAP/objcopy.sh"
    HOSTCC=gcc "HOSTCFLAGS=$E1000_HOSTCFLAGS" "HOSTLDFLAGS=$E1000_HOSTLDFLAGS")

if [[ ! -f "$BUILD_DIR/.config" ]]; then
    printf '[BC] No .config in %s, running allmodconfig first...\n' "$BUILD_DIR"
    "${BASE[@]}" "CC=$CLANG" allmodconfig
fi

printf '[BC] Building: %s\n' "$MODULE_TARGET"
printf '[BC] Kbuild output: %s\n' "$BUILD_DIR"
"${BASE[@]}" -j"${TRUMAN_BC_JOBS:-4}" "$MODULE_TARGET"

BITCODE="$BUILD_DIR/${MODULE_TARGET%.o}.bc"
[[ -s "$BITCODE" ]] || \
    die "Kbuild finished but no bitcode was produced: $BITCODE (check the module target and CONFIG_*=m)"

printf '[BC] Done.\n'
printf '  %s  (%s bytes)\n' "$BITCODE" "$(stat -c%s -- "$BITCODE")"
[[ -s "${BITCODE%.bc}.ll" ]] && printf '  %s\n' "${BITCODE%.bc}.ll"
printf '[BC] Next: scripts/shell/generate-dbm.sh %s <driver-id>\n' "$BITCODE"
