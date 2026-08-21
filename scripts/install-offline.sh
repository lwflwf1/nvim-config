#!/usr/bin/env bash
#
# nvim-config offline installer (Linux only / intranet, no network needed)
#
# Usage:
#   ./install-offline.sh <nvim-bundle-linux-x86_64-*.tar.gz> [--update]
#
#   default (full install): for a fresh machine, runs non-interactively
#     - Extracts bundle (config / data / nvim / parser-sources / tools / lazy-lock)
#     - Interactive confirmation for external tools: skip if installed, otherwise install from tools/ cache or system packages
#     - Installs neovim (old-glibc build bundled in the archive, supports RHEL6/glibc2.17)
#     - Restores config and data directories
#     - Compiles treesitter parsers directly with gcc -> ~/.local/share/nvim/site/parser/ (no tree-sitter CLI needed)
#     - Verifies
#   --update: incremental update on an already-installed machine (uses state saved
#     in ~/.nvim-offline-state by a previous run)
#     - Replaces config (with automatic backup), merges data (keeps user data)
#     - Recompiles only changed/new parsers (rev-compared against the last manifest)
#     - Installs only missing tools from the bundle cache; refreshes npm tools
#       only when their content changed
#     - Replaces nvim only when the bundled version differs
#     - Falls back to a full install when no previous state exists
#
# RHEL6 (kernel 2.6.32 / glibc 2.17) deployment notes:
#   Tool matrix (all verified on RHEL6):
#     - nvim: old-glibc build bundled in the archive (glibc 2.17 baseline)
#     - 27 treesitter parsers: compiled on-target with gcc (devtoolset-7 recommended)
#     - standalone static binaries (musl / Go static), from upstream releases:
#         ty       https://github.com/astral-sh/ty/releases        x86_64-unknown-linux-musl
#         ruff     https://github.com/astral-sh/ruff/releases      x86_64-unknown-linux-musl
#         stylua   https://github.com/JohnnyMorganz/StyLua/releases  linux-x86_64-musl.zip
#         perl-lsp https://github.com/tree-sitter-perl/perl-lsp/releases  x86_64-unknown-linux-musl
#         fd/rg    x86_64-unknown-linux-musl ; fzf linux_amd64 ; verible *-linux-static-x86_64
#     - node 18.20.4 + glibc-2.34: PATCH the binary with patchelf
#         patchelf --set-interpreter /home/yingfangong/.local/glibc-2.34/lib/ld-linux-x86-64.so.2 node
#         patchelf --set-rpath /home/yingfangong/.local/glibc-2.34/lib:/tools/gcc/gcc11/lib64 node
#       and wrap it as:  unset LD_LIBRARY_PATH; exec <node> "$@"
#       (without patching, process.execPath resolves to the loader and fork breaks)
#     - clangd (needs GLIBC_2.18) / lua-language-server (needs GLIBC_2.27):
#       same patchelf recipe, applied below.
#     - Rust toolchain: PIN 1.97.x, build with RUSTFLAGS="-C linker-flavor=lld"
#       (RHEL6 binutils 2.20 lacks -plugin; plain '-C linker-flavor=lld' works only
#       via the RUSTFLAGS env var). Official Rust baseline is kernel 3.2+ — do NOT
#       rustup update on RHEL6 (future std may use syscalls absent on 2.6.32).
#   Known issues on RHEL6:
#     - std::fs::remove_dir_all can fail with ENOTEMPTY on kernel 2.6.32 (fd-based
#       recursive delete quirk); prefer shell 'rm -rf' in Rust tooling there.
#     - never export LD_LIBRARY_PATH in glibc wrappers — it poisons every child
#       process; always strip it and rely on patchelf RUNPATH / explicit loader.
#
set -euo pipefail

BUNDLE=""
UPDATE_MODE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --update) UPDATE_MODE=1; shift;;
        -*) echo "Unknown argument: $1"; exit 1;;
        *) [ -z "$BUNDLE" ] && BUNDLE="$1" || { echo "Unexpected argument: $1"; exit 1; }; shift;;
    esac
done
[ -n "$BUNDLE" ] || { echo "Usage: $0 <bundle.tar.gz> [--update]"; exit 1; }
[ -f "$BUNDLE" ] || { echo "bundle not found: $BUNDLE"; exit 1; }
# Non-interactive by default (O6 semantics: confirmations default to YES, so
# backups happen before any overwrite and cached tools install automatically)
NO_INTERACTIVE=1

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
PARSER_DIR="$DATA_DIR/site/parser"
# User-local install root for all tools (no admin rights needed)
LOCAL_DIR="$HOME/.local"
# Previous-install state: a full install writes it, --update consumes it
STATE_DIR="$HOME/.nvim-offline-state"
LAST_MANIFEST="$STATE_DIR/last-manifest.txt"
LAST_LOCK="$STATE_DIR/lazy-lock.json"
TMP="$(mktemp -d)"
# O7 fix: report a clear non-zero exit instead of a silent rc=1
trap 'rc=$?; if [ "$rc" -ne 0 ]; then printf "\033[1;31m[error]\033[0m script exited with rc=$rc\n" >&2; fi; rm -rf "$TMP"' EXIT

ts()   { date +%H:%M:%S; }
log()  { printf '\033[1;34m[offline %s]\033[0m %s\n' "$(ts)" "$*"; }
ok()   { printf '\033[1;32m  [OK] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  [!] %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# O1 fix: on WSL the Windows-interop paths (/mnt/c/...) sit at the END of PATH
# and can shadow Linux tools with non-executable Windows shims.
if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
    log "WSL detected (${WSL_DISTRO_NAME:-unknown}), stripping Windows-interop paths from PATH"
    export PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd ':' -)"
fi

confirm() {
    # Always YES: the installer runs non-interactively. Config/data backups
    # happen before any overwrite (never silently destroying the old setup),
    # cached tools install automatically, and missing caches still fail
    # safely: the install command returns 1 -> warn.
    return 0
}

need() { # need <name> [install-command] [description] [probe]
    local name="$1" inst="$2" desc="${3:-}" probe="${4:-}"
    # O2 fix: smoke-test the binary (--version) — "present on PATH" is not
    # enough (a non-executable binary would pass `command -v` and fail later).
    # NB: $probe must be UNQUOTED so "git --version" splits into command+args.
    if command -v "$name" >/dev/null 2>&1 \
       && { [ -z "$probe" ] || $probe >/dev/null 2>&1; }; then
        ok "$name ($(command -v "$name"))"; return 0
    fi
    warn "$name not found${desc:+ ($desc)}"
    if ! confirm "  Install $name${desc:+ ($desc)}? [y/N] "; then
        warn "$name skipped"
        return 0
    fi
    if [ -n "$inst" ]; then
        echo "  Installing $name ..."
        eval "$inst" && command -v "$name" >/dev/null 2>&1 \
            && { [ -z "$probe" ] || $probe >/dev/null 2>&1; } \
            && { ok "$name installed"; return 0; }
    fi
    warn "$name not installed (skipped)"
    return 0
}

# Tool cache install helper
# Extract the tool archive into a private temp dir, then move only the binary into
# ~/.local/bin (avoids scanning $LOCAL_DIR with find and avoids leaving the
# extracted top-level dir behind).
install_from_cache() { # install_from_cache <tools/*.tar.gz|*.xz|*.zip> <binary name>
    local cache="$TMP/tools/$1" name="$2" found td
    [ -f "$cache" ] || return 1
    mkdir -p "$LOCAL_DIR/bin"
    td="$(mktemp -d)"
    case "$cache" in
        *.gz)  tar xzf "$cache" -C "$td" 2>/dev/null && found="$(find "$td" -name "$name" -type f | head -1)";;
        *.xz)  tar xJf "$cache" -C "$td" 2>/dev/null && found="$(find "$td" -name "$name" -type f | head -1)";;
        *.zip)
            if command -v unzip >/dev/null 2>&1; then unzip -oq "$cache" -d "$td"
            elif command -v python3 >/dev/null 2>&1; then python3 -m zipfile -e "$cache" "$td" 2>/dev/null || { rm -rf "$td"; return 1; }
            else warn "unzip and python3 both missing, cannot unpack $1"; rm -rf "$td"; return 1; fi
            found="$(find "$td" -name "$name" -type f | head -1)";;
        *) rm -rf "$td"; return 1;;
    esac
    [ -n "$found" ] || { rm -rf "$td"; return 1; }
    mv -f "$found" "$LOCAL_DIR/bin/$name"
    chmod +x "$LOCAL_DIR/bin/$name"
    rm -rf "$td"
    export PATH="$LOCAL_DIR/bin:$PATH"
    command -v "$name" >/dev/null 2>&1
}

# node from the bundle cache: the official tarball keeps bin/ relative to
# lib/node_modules, so the whole directory must be installed (moving only the
# binary would leave npm broken). Complements install_from_cache for node.tar.xz.
install_node_from_cache() { # install_node_from_cache <tools/node.tar.xz>
    local cache="$TMP/tools/$1" d
    [ -f "$cache" ] || return 1
    mkdir -p "$LOCAL_DIR"
    tar xJf "$cache" -C "$LOCAL_DIR" 2>/dev/null || return 1
    d="$(find "$LOCAL_DIR" -maxdepth 1 -type d -name 'node-v*' | head -1)"
    [ -n "$d" ] || return 1
    rm -rf "$LOCAL_DIR/node"
    mv "$d" "$LOCAL_DIR/node"
    export PATH="$LOCAL_DIR/node/bin:$PATH"
    command -v node >/dev/null 2>&1
}

# Compile one treesitter parser directly with gcc -> $PARSER_DIR/<lang>.so.
# The online-built .so in the bundle is NEVER used: it was compiled for the
# packager's glibc and would not run on the target (e.g. RHEL6 glibc 2.17).
compile_parser() { # compile_parser <lang.tar.gz> [location] -> 0 on success
    local tgz="$1" loc="${2:-}" lang work top dir src out d
    [ -f "$tgz" ] || return 1
    lang="$(basename "$tgz" .tar.gz)"
    work="$TMP/pbuild"; rm -rf "$work"; mkdir -p "$work"
    if ! tar xzf "$tgz" -C "$work" 2>/dev/null; then warn "  $lang extraction failed"; return 1; fi
    # Locate source dir. When parsers.lua sets a `location` (e.g. markdown_inline
    # -> tree-sitter-markdown-inline inside the same repo tarball) the real
    # sources live there; otherwise fall back to a recursive src/ search.
    top="$(find "$work" -maxdepth 1 -mindepth 1 -type d | head -1)"
    if [ -n "$loc" ] && [ -d "$top/$loc" ]; then
        dir="$top/$loc"
    elif [ ! -d "$work/src" ]; then
        d="$(find "$work" -mindepth 2 -maxdepth 3 -name src -type d | head -1)"
        [ -n "$d" ] && dir="$(dirname "$d")" || dir="$top"
    else
        dir="$work"
    fi
    src="$dir/src"
    if [ ! -f "$src/parser.c" ]; then warn "  $lang missing src/parser.c (location=$loc), skipping"; return 1; fi
    out="$PARSER_DIR/$lang.so"
    rm -f "$out"
    (
        cd "$dir" || exit 1
        if [ -f src/scanner.cc ]; then
            "$CXX_BIN" -Isrc -shared -fPIC -O2 src/parser.c src/scanner.cc -o "$out" >/dev/null 2>&1 || true
        elif [ -f src/scanner.c ]; then
            "$CC_BIN" -Isrc -shared -fPIC -O2 src/parser.c src/scanner.c -o "$out" >/dev/null 2>&1 || true
        else
            "$CC_BIN" -Isrc -shared -fPIC -O2 src/parser.c -o "$out" >/dev/null 2>&1 || true
        fi
    ) || true
    [ -f "$out" ]
}

# Shared by full install and --update: required tools, external tool cache,
# npm tools cache and the Rust toolchain. Idempotent: already-present tools are
# skipped, missing ones are offered for install from the bundle cache.
apply_tools() {
    # ---------------------------------------------------------------- External tools
    log "== External tool confirmation =="
    need git   "" "required for lazy plugin repositories" "git --version"
    need gcc   "" "required to compile treesitter parsers" "gcc --version"
    need make  "" "compile helper" "make --version"
    need node  "install_node_from_cache node.tar.xz" "mason npm packages (bash/json/yaml-lsp, prettier)" "node --version"
    need python3 "" "optional: zip unpack fallback if unzip is missing" "python3 --version"

    # Required tools must be present and RUNNABLE or the install is aborted with a
    # clear message (declining a need() above only warns, so enforce it here).
    # python3 is NOT required anymore (pyrefly was replaced by ty, a standalone Rust
    # binary); it only serves as a zip fallback when unzip is missing.
    for t in git gcc make node; do
        if ! command -v "$t" >/dev/null 2>&1 || ! "$t" --version >/dev/null 2>&1; then
            err "Required tool '$t' is missing or not runnable; install it manually (e.g. into $LOCAL_DIR/bin) and re-run"
            exit 1
        fi
    done

    # gcc version check (parsers need C11, gcc >= 5 recommended, 7.x best).
    # RHEL6: prefer the devtoolset-7 toolchain (gcc 7, supports C11/C++11) so the 27
    # treesitter parsers compile fast + correctly instead of hanging/failing under
    # the system gcc 4.4.7. DEVTOOLSET_GCC is the path provisioned on the target box.
    CC_BIN="${CC:-gcc}"
    CXX_BIN="${CXX:-}"
    DEVTOOLSET_GCC="/home/yingfangong/.local/devtoolset-7/opt/rh/devtoolset-7/root/usr/bin/gcc"
    DEVTOOLSET_GPP="/home/yingfangong/.local/devtoolset-7/opt/rh/devtoolset-7/root/usr/bin/g++"
    if [ -x "$DEVTOOLSET_GCC" ]; then
        CC_BIN="$DEVTOOLSET_GCC"; CXX_BIN="$DEVTOOLSET_GPP"
    elif [ -x /opt/rh/devtoolset-7/root/usr/bin/gcc ]; then
        CC_BIN=/opt/rh/devtoolset-7/root/usr/bin/gcc; CXX_BIN=/opt/rh/devtoolset-7/root/usr/bin/g++
    elif [ -n "${CC:-}" ]; then
        CXX_BIN="${CXX:-$(dirname "$CC_BIN")/g++}"
    else
        for ds in /opt/rh/devtoolset-*/root/usr/bin/gcc; do
            [ -x "$ds" ] || continue
            CC_BIN="$ds"; CXX_BIN="$(dirname "$ds")/g++"; break
        done
    fi
    CXX_BIN="${CXX_BIN:-$(dirname "$CC_BIN")/g++}"
    export CC="$CC_BIN" CXX="$CXX_BIN"
    GCC_VER="$("$CC_BIN" -dumpversion 2>/dev/null || echo 0)"
    log "Using C compiler: $CC_BIN ($GCC_VER)"
    if [ "$(printf '%s\n4.9' "$GCC_VER" | sort -V | head -1)" != "4.9" ]; then
        warn "gcc too old ($GCC_VER < 4.9), modern parsers need C11, compilation may fail"
        warn "RHEL6 suggestion: install devtoolset-7 under /home/yingfangong/.local/devtoolset-7"
    fi

    # Bug U fix: a runnable gcc does not guarantee compilable headers — minimal
    # images / RHEL6 often ship gcc without glibc-devel + libstdc++-devel. Probe a
    # real link so the failure is a clear message instead of N identical compile
    # errors in the parser loop below.
    CC_PROBE_OK=0
    printf '#include <stdio.h>\nint main(void){return 0;}\n' | "$CC_BIN" -x c - -o /tmp/.cc-probe 2>/dev/null && CC_PROBE_OK=1 || CC_PROBE_OK=0
    rm -f /tmp/.cc-probe
    if [ "$CC_PROBE_OK" != 1 ]; then
        warn "C compiler '$CC_BIN' cannot compile+link a program that includes <stdio.h> — the C headers are missing (libc6-dev / glibc-devel)"
        warn "Ubuntu/Debian: sudo apt-get install -y build-essential"
        warn "RHEL6: scl enable devtoolset-7 bash (provides glibc-devel/libstdc++-devel), or yum install -y glibc-devel libstdc++-devel"
    fi
    if [ -x "$CXX_BIN" ]; then
        CXX_PROBE_OK=0
        printf '#include <iostream>\nint main(){return 0;}\n' | "$CXX_BIN" -x c++ - -o /tmp/.cc-probe2 2>/dev/null && CXX_PROBE_OK=1 || CXX_PROBE_OK=0
        rm -f /tmp/.cc-probe2
        [ "$CXX_PROBE_OK" = 1 ] || warn "g++ ('$CXX_BIN') cannot compile+link a program that includes <iostream> — C++ scanners (scanner.cc) will fail; install libstdc++-devel"
    fi

    # Table-driven external tool install (tools.sh from the bundle)
    for name in $TOOLS_DOWNLOAD; do
        [ "$name" = nvim ] && continue
        safe="${name//-/_}"
        inst_var="${safe}_install"; bin_var="${safe}_binary"; out_var="${safe}_outfile"
        tinst="${!inst_var:-}"; tbin="${!bin_var:-}"; tout="${!out_var:-}"
        case "$tinst" in
            node) need "$tbin" "install_node_from_cache $tout" "mason npm packages (bash/json/yaml-lsp, prettier)" "$tbin --version";;
            bin)  need "$tbin" "install_from_cache $tout $tbin" "offline tool" "$tbin --version";;
            *)    warn "unknown install mode '$tinst' for $name";;
        esac
    done
    need rustup "" "requires an intranet mirror or manual install"
    need perl "" "requires an intranet mirror or manual install"

    # npm tools cache (bundled node_modules — offline fallback for the mason npm
    # packages: yaml-language-server, vscode-json-languageserver,
    # bash-language-server, prettier, @fsouza/prettierd). The .bin scripts call
    # `node` from PATH; on RHEL6 that must be the patched glibc-2.34 node
    # (see header notes).
    # On --update the cache is only re-extracted when its content md5 changed.
    if [ -f "$TMP/tools/npm-tools.tar.gz" ]; then
        NPM_BIN="$LOCAL_DIR/npm-tools/node_modules/.bin"
        NPM_UPDATE=1
        if [ "$MODE" = update ]; then
            OLD_MD5="$(grep -oE '^npmtools=[0-9a-f]{32}' "$LAST_MANIFEST" 2>/dev/null | cut -d= -f2 || true)"
            NEW_MD5="$(grep -oE '^npmtools=[0-9a-f]{32}' "$TMP/manifest.txt" 2>/dev/null | cut -d= -f2 || true)"
            if [ -n "$OLD_MD5" ] && [ "$OLD_MD5" = "$NEW_MD5" ] && [ -d "$NPM_BIN" ]; then
                NPM_UPDATE=0
                ok "npm tools unchanged, keeping $NPM_BIN"
            fi
        fi
        if [ "$NPM_UPDATE" = 1 ]; then
            mkdir -p "$LOCAL_DIR/npm-tools"
            if tar xzf "$TMP/tools/npm-tools.tar.gz" -C "$LOCAL_DIR/npm-tools" 2>/dev/null && [ -d "$NPM_BIN" ]; then
                export PATH="$NPM_BIN:$PATH"
                ok "npm tools extracted to $NPM_BIN"
            else
                warn "npm-tools cache present but extraction failed"
            fi
        fi
    else
        warn "No npm-tools cache in bundle — bash/json/yaml LSP + prettier need an online :MasonInstall (or use the bundle with npm tools)"
    fi

    # ---------------------------------------------------------------- Rust toolchain (optional)
    log "== Rust toolchain (optional) =="
    RUST_BIN="/home/yingfangong/rust-toolchain/stable-x86_64-unknown-linux-gnu/bin"
    if command -v rustc >/dev/null 2>&1 && rustc --version >/dev/null 2>&1; then
        ok "rustc present: $(rustc --version)"
    elif [ -x "$RUST_BIN/rustc" ] && "$RUST_BIN/rustc" --version >/dev/null 2>&1; then
        export PATH="$RUST_BIN:$PATH"
        ok "rustc from $RUST_BIN: $("$RUST_BIN/rustc" --version)"
    else
        warn "Rust toolchain not found — rustfmt/rust-analyzer unavailable"
        warn "Offline: copy ~/rust-toolchain/ (rustup stable + component rustfmt, pinned 1.97.x) from an online machine, then re-run"
    fi
    if command -v rustc >/dev/null 2>&1; then
        warn "RHEL6: build with RUSTFLAGS=\"-C linker-flavor=lld\" (binutils 2.20 lacks -plugin); keep the toolchain pinned (do NOT rustup update)"
    fi
}

# ---------------------------------------------------------------- Extract
log "== Extracting bundle =="
tar xzf "$BUNDLE" -C "$TMP"
ls "$TMP" | tr '\n' ' '; echo
[ -d "$TMP/data" ] || err "bundle is missing the data/ directory"

# Load the tool table emitted by the packager (no JSON parsing on the offline
# box — tools.sh is a plain shell companion derived from tools.json).
if [ -f "$TMP/tools.sh" ]; then
    # shellcheck disable=SC1091
    . "$TMP/tools.sh"
else
    warn "tools.sh missing in bundle — falling back to built-in tool list"
    TOOLS_DOWNLOAD="rg fd fzf pandoc ty ruff stylua"
    TOOLS_GLIBC="node pandoc clangd lua-language-server"
fi

# ---------------------------------------------------------------- Mode
MODE=full
if [ "$UPDATE_MODE" = 1 ]; then
    if [ -f "$LAST_MANIFEST" ]; then
        MODE=update
        log "Update mode: previous install state found ($STATE_DIR)"
    else
        warn "--update requested but no previous install state at $STATE_DIR — falling back to a full install"
    fi
fi

apply_tools

    # ---------------------------------------------------------------- nvim
    # Neovim's runtime resolves ../lib and ../share relative to the binary, so the
    # tree is extracted to ~/.local/nvim and a symlink is placed at ~/.local/bin/nvim
    # (overwriting any existing file/link). ~/.local/bin is prepended to PATH so the
    # bundled nvim shadows any system /usr/bin/nvim.
    install_nvim() {
        [ -f "$TMP/nvim/nvim-linux-x86_64.tar.gz" ] || { err "bundle carries no nvim binary (skipped at packaging) — install nvim manually or re-package with nvim"; return 1; }
        mkdir -p "$LOCAL_DIR" "$LOCAL_DIR/bin"
        rm -rf "$LOCAL_DIR/nvim"
        tar xzf "$TMP/nvim/nvim-linux-x86_64.tar.gz" -C "$LOCAL_DIR"
        mv "$LOCAL_DIR/nvim-linux-x86_64" "$LOCAL_DIR/nvim" 2>/dev/null || true
        ln -sf "$LOCAL_DIR/nvim/bin/nvim" "$LOCAL_DIR/bin/nvim"
        command -v nvim >/dev/null 2>&1 || { err "nvim install failed"; return 1; }
        ok "nvim installed -> $LOCAL_DIR/bin/nvim ($(nvim --version | head -1))"
    }
    if [ "$MODE" = full ]; then
        log "== Installing Neovim =="
        install_nvim
    else
        log "== Updating Neovim =="
        NEW_VER="$(grep -oE '^nvim=v[0-9]+\.[0-9]+\.[0-9]+' "$TMP/manifest.txt" 2>/dev/null | cut -d= -f2 || true)"
        NEW_VER="${NEW_VER:-}"
        if [ -z "$NEW_VER" ] && [ ! -f "$TMP/nvim/nvim-linux-x86_64.tar.gz" ]; then
            warn "bundle carries no nvim binary (skipped at packaging) — keeping existing nvim"
        elif command -v nvim >/dev/null 2>&1 && nvim --version >/dev/null 2>&1; then
            CUR_VER="$(nvim --version | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
            if [ -n "$CUR_VER" ] && [ -n "$NEW_VER" ] && [ "$CUR_VER" = "$NEW_VER" ]; then
                mkdir -p "$LOCAL_DIR/bin"
                ln -sf "$LOCAL_DIR/nvim/bin/nvim" "$LOCAL_DIR/bin/nvim"
                ok "nvim $CUR_VER unchanged, symlink ensured"
            else
                if confirm "Replace nvim ${CUR_VER:-?} with bundled ${NEW_VER:-?}? [y/N] "; then
                    install_nvim
                else
                    warn "keeping existing nvim"
                fi
            fi
        else
            install_nvim
        fi
    fi
    export PATH="$LOCAL_DIR/bin:$LOCAL_DIR/nvim/bin:$PATH"

# ---------------------------------------------------------------- Config and data
if [ "$MODE" = full ]; then
    log "== Restoring config and data =="
    if [ -d "$CONFIG_DIR" ] && confirm "Config directory $CONFIG_DIR exists, back it up and overwrite? [y/N] " y; then
        mv "$CONFIG_DIR" "$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"; ok "Old config backed up"
    fi
    if [ -d "$DATA_DIR" ] && confirm "Data directory $DATA_DIR exists, back it up and overwrite? [y/N] " y; then
        mv "$DATA_DIR" "$DATA_DIR.bak.$(date +%Y%m%d%H%M%S)"; ok "Old data backed up"
    fi
    mkdir -p "$(dirname "$CONFIG_DIR")" "$(dirname "$DATA_DIR")"
    log "copying config -> $CONFIG_DIR"
    cp -a "$TMP/config" "$CONFIG_DIR"
    log "copying data (lazy plugins) -> $DATA_DIR"
    cp -a "$TMP/data" "$DATA_DIR"
    rm -rf "$DATA_DIR/backup" "$DATA_DIR/undo" "$DATA_DIR/swap" "$DATA_DIR/view" 2>/dev/null || true
    mkdir -p "$DATA_DIR/backup" "$DATA_DIR/undo" "$DATA_DIR/swap" "$DATA_DIR/view" "$PARSER_DIR"
    ok "Config -> $CONFIG_DIR  Data -> $DATA_DIR"
else
    log "== Updating config and data =="
    # config: full replace with automatic backup (files removed upstream go away too)
    if [ -d "$CONFIG_DIR" ]; then
        mv "$CONFIG_DIR" "$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
        ok "Old config backed up"
    fi
    mkdir -p "$(dirname "$CONFIG_DIR")"
    cp -a "$TMP/config" "$CONFIG_DIR"
    ok "Config updated -> $CONFIG_DIR"
    # data: overlay-merge, preserving user data. cp -a copies the bundle's
    # tree over the local one (packager version wins) WITHOUT deleting local
    # extras — user state in backup/undo/swap/view is never touched, and
    # plugin removal is handled separately via the lazy-lock diff below.
    # (cp -au was avoided: BSD cp lacks -u and mtime comparisons across
    # machines are unreliable since tar preserves source mtimes.)
    mkdir -p "$DATA_DIR"
    for sub in lazy mason; do
        if [ -d "$TMP/data/$sub" ]; then
            mkdir -p "$DATA_DIR/$sub"
            cp -a "$TMP/data/$sub/." "$DATA_DIR/$sub/"
            ok "data/$sub overlay-copied"
        fi
    done
    # site: merge everything EXCEPT parser/ — the offline machine compiles its
    # own .so for its glibc (the online-built ones would not run on RHEL6).
    if [ -d "$TMP/data/site" ]; then
        mkdir -p "$DATA_DIR/site"
        for entry in "$TMP/data/site"/*; do
            [ -e "$entry" ] || continue
            [ "$(basename "$entry")" = "parser" ] && continue
            cp -a "$entry" "$DATA_DIR/site/"
        done
        ok "data/site overlay-copied (parser/ excluded, recompiled below)"
    fi
    # Plugin removal: drop lazy plugins that are in the previous lock but not in
    # the new one (plugins removed from the config). Anything else is kept.
    if [ -f "$LAST_LOCK" ] && [ -f "$TMP/lazy-lock.json" ]; then
        for plugin_dir in "$DATA_DIR/lazy"/*; do
            [ -d "$plugin_dir" ] || continue
            name="$(basename "$plugin_dir")"
            if grep -q "^  \"$name\":" "$LAST_LOCK" 2>/dev/null \
               && ! grep -q "^  \"$name\":" "$TMP/lazy-lock.json" 2>/dev/null; then
                rm -rf "$plugin_dir"
                warn "removed plugin no longer in lazy-lock: $name"
            fi
        done
    fi
    mkdir -p "$PARSER_DIR"
    ok "Data updated -> $DATA_DIR"
fi

# ---------------------------------------------------------------- Compile parsers
if [ "$MODE" = full ]; then
    log "== Compiling treesitter parsers (directly with gcc) =="
    # O5 fix: a stale .so from a previous run would mask compile failures below
    # (nvim loads whatever exists silently), so clear them first.
    rm -f "$PARSER_DIR"/*.so 2>/dev/null || true
    parse_ok=0; parse_fail=0
    # lookup the optional subdir `location` recorded by package.ps1 so inline
    # parsers (e.g. markdown_inline) build from the correct source dir.
    parser_location() { grep -E "^parser $1 " "$TMP/manifest.txt" 2>/dev/null | awk '{print $5}'; }
    for tgz in "$TMP/parser-sources/"*.tar.gz; do
        [ -f "$tgz" ] || continue
        lang="$(basename "$tgz" .tar.gz)"
        loc="$(parser_location "$lang")"
        if compile_parser "$tgz" "$loc"; then
            ok "  $lang compiled"; parse_ok=$((parse_ok+1))
        else
            warn "  $lang compilation failed"; parse_fail=$((parse_fail+1))
        fi
    done
    log "Parser compilation done: ok=$parse_ok  failed=$parse_fail"
else
    log "== Compiling changed treesitter parsers (directly with gcc) =="
    # Update mode: recompile only parsers whose pinned revision differs from the
    # last applied manifest (or whose .so is missing). Existing .so are kept.
    parse_ok=0; parse_fail=0; parse_skip=0
    while read -r p lang url rev loc; do
        [ "$p" = "parser" ] || continue
        [ -n "$lang" ] || continue
        tgz="$TMP/parser-sources/$lang.tar.gz"
        prev_rev="$(awk -v l="$lang" '$1=="parser" && $2==l {print $4}' "$LAST_MANIFEST" 2>/dev/null | head -1)"
        if [ -n "$prev_rev" ] && [ "$prev_rev" = "$rev" ] && [ -f "$PARSER_DIR/$lang.so" ]; then
            parse_skip=$((parse_skip+1)); continue
        fi
        if compile_parser "$tgz" "$loc"; then
            ok "  $lang compiled"; parse_ok=$((parse_ok+1))
        else
            warn "  $lang compilation failed"; parse_fail=$((parse_fail+1))
        fi
    done < <(grep '^parser ' "$TMP/manifest.txt" 2>/dev/null || true)
    # Drop stale .so for parsers removed from the config
    while read -r _ lang _; do
        [ -f "$PARSER_DIR/$lang.so" ] || continue
        if ! grep -q "^parser $lang " "$TMP/manifest.txt" 2>/dev/null; then
            rm -f "$PARSER_DIR/$lang.so"
            warn "removed stale parser: $lang.so"
        fi
    done < <(grep '^parser ' "$LAST_MANIFEST" 2>/dev/null || true)
    log "Parser compilation done: ok=$parse_ok  failed=$parse_fail  unchanged-skipped=$parse_skip"
fi

# ---------------------------------------------------------------- PATH
log "== Configuring PATH =="
export PATH="$LOCAL_DIR/nvim/bin:$LOCAL_DIR/bin:$PATH"
# Add mason binaries (lsp/formatter) to PATH
export PATH="$DATA_DIR/mason/bin:$PATH"
grep -q "$LOCAL_DIR" "$HOME/.bashrc" 2>/dev/null || cat >> "$HOME/.bashrc" <<EOF
# nvim-config (offline install)
export PATH="$LOCAL_DIR/nvim/bin:$LOCAL_DIR/bin:$LOCAL_DIR/npm-tools/node_modules/.bin:$DATA_DIR/mason/bin:\$PATH"
EOF
ok "PATH written to ~/.bashrc"

# ---------------------------------------------------------------- glibc-2.34 re-linked binaries (RHEL6)
# clangd (needs GLIBC_2.18) and lua-language-server (needs GLIBC_2.27) cannot run
# on the system glibc 2.17. Patch them in place with patchelf so they carry the
# glibc-2.34 loader + RUNPATH, then install a thin wrapper that strips
# LD_LIBRARY_PATH (RUNPATH ranks BELOW it, so a polluted shell env would
# otherwise override glibc). Same recipe as node — see header notes.
GLIBC234="/home/yingfangong/.local/glibc-2.34"
GLIBC_LIB="$GLIBC234/lib"
GLIBC_LD="$GLIBC_LIB/ld-linux-x86-64.so.2"
GCC11_LIB="/tools/gcc/gcc11/lib64"
WRAPPER_BIN="/home/yingfangong/.local/bin"

gen_glibc_wrapper() { # gen_glibc_wrapper <real-abs-path> <wrapper-name>
    local real="$1" name="$2"
    [ -x "$real" ] || { warn "  $real not found, skipping wrapper '$name'"; return 0; }
    mkdir -p "$WRAPPER_BIN"
    if [ -x "$GLIBC_LD" ]; then
        if command -v patchelf >/dev/null 2>&1; then
            if patchelf --set-interpreter "$GLIBC_LD" "$real" >/dev/null 2>&1 \
               && patchelf --set-rpath "$GLIBC_LIB:$GCC11_LIB" "$real" >/dev/null 2>&1; then
                ok "patched $name (PT_INTERP->glibc-2.34, RUNPATH)"
            else
                warn "patchelf failed on $name"
            fi
        else
            warn "patchelf not found — cannot re-link $name to glibc-2.34 (install patchelf, e.g. copy a static build to $LOCAL_DIR/bin...)"
        fi
    else
        warn "glibc-2.34 loader not found: $GLIBC_LD — install it under /home/yingfangong/.local/glibc-2.34"
    fi
    cat > "$WRAPPER_BIN/$name" <<EOF
#!/bin/bash
unset LD_LIBRARY_PATH
exec "$real" "\$@"
EOF
    chmod +x "$WRAPPER_BIN/$name"
    ok "wrapper $WRAPPER_BIN/$name -> $real"
}

# Re-link every glibc234 tool (driven by tools.sh). For `external` tools the
# realpath is the pre-installed binary; for `node`/`bin` tools it is the binary
# the installer just placed under $LOCAL_DIR.
for name in $TOOLS_GLIBC; do
    safe="${name//-/_}"
    inst_var="${safe}_install"; rp_var="${safe}_realpath"; bin_var="${safe}_binary"
    tinst="${!inst_var:-}"; trp="${!rp_var:-}"; tbin="${!bin_var:-}"
    case "$tinst" in
        external) target="$trp";;
        node)     target="$LOCAL_DIR/node/bin/node";;
        bin)      target="$LOCAL_DIR/bin/$tbin";;
        *)        warn "unknown glibc install mode for $name"; continue;;
    esac
    gen_glibc_wrapper "$target" "$name"
done

# ---------------------------------------------------------------- Verification
log "== Verification =="
# Bug U fix: en_US.UTF-8 is often not generated on fresh/minimal images;
# export the first locale that actually exists (C.UTF-8 ships everywhere).
if locale -a 2>/dev/null | grep -qix 'en_US.UTF-8'; then LANG_LOC=en_US.UTF-8
elif locale -a 2>/dev/null | grep -qix 'C.UTF-8'; then LANG_LOC=C.UTF-8
else LANG_LOC=C; fi
export LANG="$LANG_LOC" LC_ALL="$LANG_LOC"
plugins=$(ls "$DATA_DIR/lazy" 2>/dev/null | wc -l | tr -d ' ' || true)
parsers=$(ls "$PARSER_DIR"/*.so 2>/dev/null | wc -l | tr -d ' ' || true)
mason=$(ls "$DATA_DIR/mason/packages" 2>/dev/null | wc -l | tr -d ' ' || true)
# O4 fix: compare against the counts recorded on the packaging machine instead
# of raw presence (a bundle that lost parsers would otherwise "verify" fine).
EXPECTED_PARSERS="$(grep -oE '^parsers=[0-9]+' "$TMP/manifest.txt" 2>/dev/null | cut -d= -f2 || true)"
EXPECTED_MASON="$(grep -oE '^mason=[0-9]+' "$TMP/manifest.txt" 2>/dev/null | cut -d= -f2 || true)"
if [ -n "$EXPECTED_PARSERS" ] && [ "$parsers" -lt "$EXPECTED_PARSERS" ]; then
    warn "Parsers compiled: $parsers/$EXPECTED_PARSERS — the bundle shipped $EXPECTED_PARSERS, some failed or were skipped"
fi
if [ -n "$EXPECTED_MASON" ] && [ "$mason" -lt "$EXPECTED_MASON" ]; then
    warn "Mason tools: $mason/$EXPECTED_MASON — the bundle shipped $EXPECTED_MASON, install extras via :MasonInstall in nvim"
fi
# Bug I fix: check the output for real error patterns, not just the exit code
# (nvim --headless exits 0 even when the config fails to load).
# O7 fix: bounded headless run — a hung network/plugin must not block forever.
LOG="/tmp/nvim-offline-verify.log"
rm -f "$LOG"
( nvim --headless +qa >"$LOG" 2>&1 & pid=$!; n=0
  while kill -0 "$pid" 2>/dev/null; do
      if [ "$n" -ge 60 ]; then kill -9 "$pid" 2>/dev/null || true; warn "Startup verification timed out (60s), killed"; break; fi
      sleep 2; n=$((n+2))
  done
  wait "$pid" ) >/dev/null 2>&1 || true
if ! grep -qE 'E[0-9]+: |Error detected|Error in ' "$LOG"; then
    ok "Startup verification passed"
else
    warn "Startup verification reported errors, see $LOG"
    grep -aE 'E[0-9]+: |Error detected|Error in ' "$LOG" | head -3
fi

# ---------------------------------------------------------------- Save install state
log "== Saving install state =="
mkdir -p "$STATE_DIR"
cp "$TMP/manifest.txt" "$LAST_MANIFEST" 2>/dev/null || true
cp "$TMP/lazy-lock.json" "$LAST_LOCK" 2>/dev/null || true
ok "state saved to $STATE_DIR (consumed by future --update runs)"

echo
log "Installation done: mode=$MODE  plugins=$plugins  parsers=$parsers  masonTools=$mason"
log "Run: source ~/.bashrc; nvim"
warn "If mason ty is unavailable, run once online: nvim --headless +MasonInstall ty +qa"