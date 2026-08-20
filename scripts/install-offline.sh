#!/usr/bin/env bash
#
# nvim-config offline installer (Linux only / intranet, no network needed)
#
# Usage:
#   ./install-offline.sh <nvim-bundle-linux-x86_64-*.tar.gz> [--no-interactive]
#
# Behavior:
#   - Extracts bundle (config / data / nvim / parser-sources / tools / lazy-lock)
#   - Interactive confirmation for external tools: skip if installed, otherwise install from tools/ cache or system packages
#   - Installs neovim (old-glibc build bundled in the archive, supports RHEL6/glibc2.17)
#   - Restores config and data directories
#   - Compiles treesitter parsers directly with gcc -> ~/.local/share/nvim/site/parser/ (no tree-sitter CLI needed)
#   - Verifies
#
set -euo pipefail

BUNDLE="${1:-}"
NO_INTERACTIVE="${2:-}"
[ -n "$BUNDLE" ] || { echo "Usage: $0 <bundle.tar.gz> [--no-interactive]"; exit 1; }
[ -f "$BUNDLE" ] || { echo "bundle not found: $BUNDLE"; exit 1; }

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
PARSER_DIR="$DATA_DIR/site/parser"
# User-local install root for all tools (no admin rights needed)
LOCAL_DIR="$HOME/.local"
TMP="$(mktemp -d)"
# O7 fix: report a clear non-zero exit instead of a silent rc=1
trap 'rc=$?; if [ "$rc" -ne 0 ]; then printf "\033[1;31m[error]\033[0m script exited with rc=$rc\n" >&2; fi; rm -rf "$TMP"' EXIT

log()  { printf '\033[1;34m[offline]\033[0m %s\n' "$*"; }
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
    # O6 fix: non-interactive runs default to YES for safety — the config/data
    # backup prompts then back up before overwriting (instead of silently
    # destroying the old setup), and cached tools get installed automatically.
    # Missing caches still fail safely: the install command returns 1 -> warn.
    [ -n "$NO_INTERACTIVE" ] && return 0
    local d="${2:-n}"
    read -r -p "$1" ans
    case "${ans:-$d}" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

need() { # need <name> [install-command] [description] [probe]
    local name="$1" inst="$2" desc="${3:-}" probe="${4:-}"
    # O2 fix: smoke-test the binary (--version) — "present on PATH" is not
    # enough (a non-executable binary would pass `command -v` and fail later).
    if command -v "$name" >/dev/null 2>&1 \
       && { [ -z "$probe" ] || "$probe" >/dev/null 2>&1; }; then
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
            && { [ -z "$probe" ] || "$probe" >/dev/null 2>&1; } \
            && { ok "$name installed"; return 0; }
    fi
    warn "$name not installed (skipped)"
    return 0
}

# ---------------------------------------------------------------- Extract
log "== Extracting bundle =="
tar xzf "$BUNDLE" -C "$TMP"
ls "$TMP" | tr '\n' ' '; echo
[ -d "$TMP/data" ] || err "bundle is missing the data/ directory"

# ---------------------------------------------------------------- External tools
log "== External tool confirmation =="
# Tool cache install helper
install_from_cache() { # install_from_cache <tools/*.tar.gz|*.xz|*.zip> <binary name>
    local cache="$TMP/tools/$1" name="$2" found
    [ -f "$cache" ] || return 1
    mkdir -p "$LOCAL_DIR/bin"
    case "$cache" in
        *.gz) tar xzf "$cache" -C "$LOCAL_DIR" 2>/dev/null || gunzip -c "$cache" > "$LOCAL_DIR/bin/$name";;
        *.xz) tar xJf "$cache" -C "$LOCAL_DIR" 2>/dev/null || return 1;;
        *.zip)
            # O8 fix: unzip may be absent on minimal machines; python3 (required) can unpack zip
            if command -v unzip >/dev/null 2>&1; then unzip -oq "$cache" -d "$LOCAL_DIR/bin"
            else python3 -m zipfile -e "$cache" "$LOCAL_DIR/bin" 2>/dev/null || return 1; fi;;
    esac
    found="$(find "$LOCAL_DIR" -name "$name" -type f | head -1)"
    [ -n "$found" ] || return 1
    [ "$found" != "$LOCAL_DIR/bin/$name" ] && mv -f "$found" "$LOCAL_DIR/bin/$name"
    chmod +x "$LOCAL_DIR/bin/$name"
    # O8 fix: ripgrep extracts to ripgrep-*, which the ${name}-* pattern missed
    rm -rf "$LOCAL_DIR/${name}-"* "$LOCAL_DIR/ripgrep-"* 2>/dev/null || true
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

need git   "" "required for lazy plugin repositories" "git --version"
need gcc   "" "required to compile treesitter parsers" "gcc --version"
need make  "" "compile helper" "make --version"
need node  "install_node_from_cache node.tar.xz || install_from_cache node.tar.gz node" "mason npm packages (bash/json/yaml-lsp, prettier)" "node --version"
need python3 "" "required by pyrefly" "python3 --version"

# Required tools must be present and RUNNABLE or the install is aborted with a
# clear message (declining a need() above only warns, so enforce it here).
for t in git gcc make node python3; do
    if ! command -v "$t" >/dev/null 2>&1 || ! "$t" --version >/dev/null 2>&1; then
        err "Required tool '$t' is missing or not runnable; install it manually (e.g. into $LOCAL_DIR/bin) and re-run"
        exit 1
    fi
done

# gcc version check (parsers need C11, gcc >= 5 recommended, 7.x best)
CC_BIN="${CC:-gcc}"
GCC_VER="$("$CC_BIN" -dumpversion 2>/dev/null || echo 0)"
if [ "$(printf '%s\n4.9' "$GCC_VER" | sort -V | head -1)" != "4.9" ]; then
    # Try devtoolset (RHEL6 SCL provides gcc 7)
    for ds in /opt/rh/devtoolset-*/root/usr/bin/gcc; do
        [ -x "$ds" ] || continue
        CC_BIN="$ds"; GCC_VER="$("$CC_BIN" -dumpversion)"; break
    done
fi
GCC_VER="$("$CC_BIN" -dumpversion 2>/dev/null || echo 0)"
log "Using C compiler: $CC_BIN ($GCC_VER)"
if [ "$(printf '%s\n4.9' "$GCC_VER" | sort -V | head -1)" != "4.9" ]; then
    warn "gcc too old ($GCC_VER < 4.9), modern parsers need C11, compilation may fail"
    warn "RHEL6 suggestion: run 'scl enable devtoolset-7 bash' and retry, or set CC=/opt/rh/devtoolset-7/root/usr/bin/gcc"
fi
CXX_BIN="${CXX:-$(dirname "$CC_BIN")/g++}"

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

need fzf "install_from_cache fzf.tar.gz fzf" "fzf-lua search" "fzf --version"
need rg  "install_from_cache rg.tar.gz rg" "fzf-lua search" "rg --version"
need fd  "install_from_cache fd.tar.gz fd" "fzf-lua search" "fd --version"
need rustup "" "requires an intranet mirror or manual install"
need perl "" "requires an intranet mirror or manual install"
need pandoc "install_from_cache pandoc.tar.gz pandoc" "orgmode export" "pandoc --version"

# ---------------------------------------------------------------- nvim
log "== Installing Neovim =="
if command -v nvim >/dev/null 2>&1; then
    ok "nvim already present: $(nvim --version | head -1)"
else
    mkdir -p "$LOCAL_DIR"
    tar xzf "$TMP/nvim/nvim-linux-x86_64.tar.gz" -C "$LOCAL_DIR"
    mv "$LOCAL_DIR/nvim-linux-x86_64" "$LOCAL_DIR/nvim" 2>/dev/null || true
    export PATH="$LOCAL_DIR/nvim/bin:$PATH"
    command -v nvim >/dev/null 2>&1 || err "nvim install failed"
    ok "nvim installed to $LOCAL_DIR/nvim ($(nvim --version | head -1))"
fi
case ":$PATH:" in *":$LOCAL_DIR/nvim/bin:"*) ;; *) export PATH="$LOCAL_DIR/nvim/bin:$PATH";; esac

# ---------------------------------------------------------------- Config and data
log "== Restoring config and data =="
if [ -d "$CONFIG_DIR" ] && confirm "Config directory $CONFIG_DIR exists, back it up and overwrite? [y/N] " y; then
    mv "$CONFIG_DIR" "$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"; ok "Old config backed up"
fi
if [ -d "$DATA_DIR" ] && confirm "Data directory $DATA_DIR exists, back it up and overwrite? [y/N] " y; then
    mv "$DATA_DIR" "$DATA_DIR.bak.$(date +%Y%m%d%H%M%S)"; ok "Old data backed up"
fi
mkdir -p "$(dirname "$CONFIG_DIR")" "$(dirname "$DATA_DIR")"
cp -a "$TMP/config" "$CONFIG_DIR"
cp -a "$TMP/data" "$DATA_DIR"
rm -rf "$DATA_DIR/backup" "$DATA_DIR/undo" "$DATA_DIR/swap" "$DATA_DIR/view" 2>/dev/null || true
mkdir -p "$DATA_DIR/backup" "$DATA_DIR/undo" "$DATA_DIR/swap" "$DATA_DIR/view" "$PARSER_DIR"
ok "Config -> $CONFIG_DIR  Data -> $DATA_DIR"

# ---------------------------------------------------------------- Compile parsers
log "== Compiling treesitter parsers (directly with gcc) =="
# O5 fix: a stale .so from a previous run would mask compile failures below
# (nvim loads whatever exists silently), so clear them first.
rm -f "$PARSER_DIR"/*.so 2>/dev/null || true
parse_ok=0; parse_fail=0
for tgz in "$TMP/parser-sources/"*.tar.gz; do
    [ -f "$tgz" ] || continue
    lang="$(basename "$tgz" .tar.gz)"
    work="$TMP/pbuild"; rm -rf "$work"; mkdir -p "$work"
    if ! tar xzf "$tgz" -C "$work" 2>/dev/null; then warn "  $lang extraction failed"; continue; fi
    # Locate source dir: handle both tar layouts (with/without top-level dir)
    dir="$work"
    if [ ! -d "$dir/src" ]; then
        d="$(find "$work" -mindepth 2 -maxdepth 3 -name src -type d | head -1)"
        [ -n "$d" ] && dir="$(dirname "$d")"
    fi
    src="$dir/src"
    if [ ! -f "$src/parser.c" ]; then warn "  $lang missing src/parser.c, skipping"; parse_fail=$((parse_fail+1)); continue; fi
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
    if [ -f "$out" ]; then ok "  $lang compiled"; parse_ok=$((parse_ok+1)); else warn "  $lang compilation failed"; parse_fail=$((parse_fail+1)); fi
done
log "Parser compilation done: ok=$parse_ok  failed=$parse_fail"

# ---------------------------------------------------------------- PATH
log "== Configuring PATH =="
export PATH="$LOCAL_DIR/nvim/bin:$LOCAL_DIR/bin:$PATH"
# Add mason binaries (lsp/formatter) to PATH
export PATH="$DATA_DIR/mason/bin:$PATH"
grep -q "$LOCAL_DIR" "$HOME/.bashrc" 2>/dev/null || cat >> "$HOME/.bashrc" <<EOF
# nvim-config (offline install)
export PATH="$LOCAL_DIR/nvim/bin:$LOCAL_DIR/bin:$DATA_DIR/mason/bin:\$PATH"
EOF
ok "PATH written to ~/.bashrc"

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
echo
log "Installation done: plugins=$plugins  parsers=$parsers  masonTools=$mason"
log "Run: source ~/.bashrc; nvim"
warn "If mason pyrefly (python venv) is unavailable, run once online: nvim --headless +MasonInstall pyrefly +qa"