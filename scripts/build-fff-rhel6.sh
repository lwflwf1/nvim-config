#!/usr/bin/env bash
#
# build-fff-rhel6.sh — cross-build fff's nvim backend for RHEL6 (glibc 2.17)
#
# Why this exists:
#   fff's prebuilt Linux binaries are unusable on RHEL6:
#     - x86_64-unknown-linux-gnu  -> linked for glibc >= 2.31
#     - x86_64-unknown-linux-musl -> dynamic musl (DT_NEEDED libc.so), cannot be
#       dlopen'd by a glibc Neovim (fails with "/usr/lib64/libc.so: invalid ELF header")
#   Upstream's CI comment (.github/workflows/release.yaml) states:
#     "Rust 1.91+ requires glibc >= 2.31 ... earlier targets (2.17) no longer link."
#   So we pin an older toolchain (1.90) and cross-build to a 2.17 target with
#   cargo-zigbuild. The resulting .so runs on RHEL6.
#
# Where to run:  a Linux host / WSL with network access. NOT RHEL6 (offline, and
#                its rust 1.97 is too new to target 2.17).
#
# Output:  scripts/prebuilt/fff/libfff_nvim.so
#          (committed to the repo; package.ps1 copies it into the bundle)
#
# Verify afterwards (must print max GLIBC_ <= 2.17 and the exported symbol):
#   objdump -T <so> | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1
#   nm -D <so> | grep luaopen_fff_nvim
#
# Keep FFF_COMMIT in sync with the fff entry in lazy-lock.json.
set -euo pipefail

# Resolve the script's own directory NOW (before any cd) so DEST is stable even
# when invoked via a relative path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FFF_REPO="${FFF_REPO:-https://github.com/dmtrKovalenko/fff.git}"
FFF_COMMIT="${FFF_COMMIT:-7f8537e70f0ea1210f9acbbfc4640141105cdc78}"  # 0.10.7-nightly.7f8537e
RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-1.90.0}"   # <1.91: last std baseline that links against 2.17
ZIG_VERSION="${ZIG_VERSION:-0.16.0}"          # zlob requires zig >= 0.16 (build.zig.zon)
TARGET_TRIPLE="${TARGET_TRIPLE:-x86_64-unknown-linux-gnu.2.17}"
# Walker/glob engine. The DEFAULT (ripgrep feature) is the only one that works on
# glibc 2.17: the `zlob` feature pulls in zig >= 0.16, whose std (Io.Threaded)
# makes *strong* calls to statx/getrandom/copy_file_range (glibc 2.25-2.28),
# which RHEL6's glibc 2.17 does not provide -> the .so gets undefined symbols and
# dlopen fails. (Upstream's own prebuilts use zlob, but they target .2.31.)
# Set FFF_FEATURES="--no-default-features --features zlob" only when targeting a
# glibc >= 2.28.
FFF_FEATURES="${FFF_FEATURES:-}"

B="${FFF_BUILD_DIR:-$HOME/.fff-build}"
CARGO_TARGET_DIR="$B/target"
export CARGO_TARGET_DIR

# Prefer an already-provisioned toolchain (rustup + the target toolchain + zig +
# cargo-zigbuild on PATH). Only fall back to an isolated bootstrap when missing,
# so a bare machine still works but a prepared one rebuilds fast.
persistent_ok() {
    command -v rustup >/dev/null 2>&1 \
        && rustup toolchain list 2>/dev/null | grep -q "^$RUST_TOOLCHAIN" \
        && command -v zig >/dev/null 2>&1 \
        && command -v cargo-zigbuild >/dev/null 2>&1
}

if persistent_ok; then
    echo "== using persistent toolchain: rustup $RUST_TOOLCHAIN + $(zig version) + cargo-zigbuild =="
else
    echo "== no persistent toolchain found; bootstrapping isolated env in $B =="
    RUSTUP_HOME="$B/rustup"; CARGO_HOME="$B/cargo"
    mkdir -p "$B/bin"
    export RUSTUP_HOME CARGO_HOME PATH="$B/bin:$CARGO_HOME/bin:$PATH"

    echo "-- rustup + $RUST_TOOLCHAIN --"
    if [ ! -x "$CARGO_HOME/bin/rustup" ]; then
        curl -sSfL -o /tmp/rustup-init https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init
        chmod +x /tmp/rustup-init
        /tmp/rustup-init -y --profile minimal --default-toolchain "$RUST_TOOLCHAIN" --no-modify-path
    fi

    echo "-- zig $ZIG_VERSION --"
    if [ ! -x "$B/bin/zig" ]; then
        curl -sSfL -o /tmp/zig.tar.xz "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz"
        tar -xf /tmp/zig.tar.xz -C /tmp
        ln -sf "/tmp/zig-x86_64-linux-$ZIG_VERSION/zig" "$B/bin/zig"
    fi

    echo "-- cargo-zigbuild --"
    [ -x "$CARGO_HOME/bin/cargo-zigbuild" ] || cargo install cargo-zigbuild --locked
fi

echo "== fetch fff @ $FFF_COMMIT =="
SRC="$B/fff"
# FFF_SRC lets you point at an existing checkout (e.g. a copy of the plugin dir
# from the Windows machine) so the build works without network access.
if [ -n "${FFF_SRC:-}" ]; then
    [ -d "$FFF_SRC" ] || { echo "FFF_SRC not a directory: $FFF_SRC" >&2; exit 1; }
    echo "  using FFF_SRC=$FFF_SRC (skipping git fetch)"
    SRC="$FFF_SRC"
else
    if [ ! -d "$SRC/.git" ]; then
        mkdir -p "$SRC"; cd "$SRC"
        git init -q; git remote add origin "$FFF_REPO"
    fi
    cd "$SRC"
    # GitHub's TLS occasionally drops; retry the shallow fetch a few times.
    fetch_ok=0
    for i in 1 2 3 4 5; do
        if git fetch --depth 1 origin "$FFF_COMMIT"; then fetch_ok=1; break; fi
        echo "  fetch attempt $i failed; retrying in 3s..." >&2; sleep 3
    done
    [ "$fetch_ok" = 1 ] || { echo "failed to fetch $FFF_COMMIT from $FFF_REPO" >&2; exit 1; }
    git checkout -q FETCH_HEAD
fi
cd "$SRC"

echo "== build ($TARGET_TRIPLE) features: ${FFF_FEATURES:-<default>} =="
# zlob's build script runs bindgen, which needs libclang. The persistent toolchain
# may not have it (needs root via apt); the PyPI `libclang` wheel works without
# root -- auto-detect it so no sudo is required.
if [ -z "${LIBCLANG_PATH:-}" ]; then
    for d in "$HOME"/.local/lib/python*/site-packages/clang/native \
             "$HOME"/.local/lib/python*/site-packages/clang; do
        if [ -e "$d/libclang.so" ]; then export LIBCLANG_PATH="$d"; echo "  LIBCLANG_PATH=$d"; break; fi
    done
fi
if [ -z "${LIBCLANG_PATH:-}" ]; then
    echo "  WARNING: libclang.so not found; zlob builds will fail." >&2
    echo "  install it without root:  pip3 install --user --break-system-packages libclang" >&2
fi
# zlob compiles Zig sources itself (build.rs) and requires zig >= 0.16. NOTE:
# zlob is NOT usable against glibc 2.17 (see FFF_FEATURES comment) -- this branch
# only helps when targeting a newer glibc.
if [[ " ${FFF_FEATURES} " == *" zlob "* ]]; then
    case "$TARGET_TRIPLE" in
        *linux-gnu.2.1[0-7]|*linux-gnu.2.1[0-7].*)
            echo "WARNING: zlob + glibc <= 2.17 will produce a .so with undefined" >&2
            echo "         statx/getrandom/copy_file_range; it will NOT load on RHEL6." >&2
            ;;
    esac
    export ZIG="$(command -v zig)"
    echo "  zlob compiler: ZIG=$ZIG ($("$ZIG" version))"
fi
# shellcheck disable=SC2086
RUSTUP_TOOLCHAIN="$RUST_TOOLCHAIN" \
    cargo zigbuild --release -p fff-nvim --target "$TARGET_TRIPLE" $FFF_FEATURES

SO="$CARGO_TARGET_DIR/x86_64-unknown-linux-gnu/release/libfff_nvim.so"
[ -f "$SO" ] || { echo "build did not produce $SO" >&2; exit 1; }

echo "== verify =="
file "$SO"
echo -n "max GLIBC_ (versioned): "; objdump -T "$SO" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1
# A "max GLIBC_" check alone is NOT enough: symbols referenced without a version
# tag (e.g. from statically-linked Zig code) are invisible to it and would break
# at dlopen time. Fail on *strong* (non-weak) undefined symbols newer than 2.17.
BAD_UNDEF=$(nm -D --undefined-only "$SO" 2>/dev/null \
    | awk '$1=="U" && $2!="" {print $2}' \
    | grep -E '^(statx|getrandom|copy_file_range|pidfd_|openat2|faccessat2)$' || true)
if [ -n "$BAD_UNDEF" ]; then
    echo "FAIL: strong undefined symbols absent on glibc 2.17:" >&2
    echo "$BAD_UNDEF" | sed 's/^/  - /' >&2
    echo "  (the 'zlob' feature pulls these in via zig 0.16's std; use ripgrep on 2.17)" >&2
    exit 1
fi
echo "undefined-symbol check: OK (no post-2.17 strong refs)"
nm -D "$SO" | grep -q luaopen_fff_nvim && echo "symbols OK"

DEST="${DEST:-}"
if [ -n "$DEST" ]; then
    DEST="$DEST/libfff_nvim.so"
else
    DEST="$SCRIPT_DIR/../scripts/prebuilt/fff/libfff_nvim.so"
fi
mkdir -p "$(dirname "$DEST")"
cp "$SO" "$DEST"
echo "wrote $DEST"
echo "commit scripts/prebuilt/fff/libfff_nvim.so (and keep FFF_COMMIT == lazy-lock fff commit)"
