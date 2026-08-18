#!/usr/bin/env bash
#
# nvim-config packaging script (Linux only, run on an online/installed machine)
#
# Usage:
#   ./package.sh [--out DIR] [--with-tools "rg fd fzf"] [--nvim-version v0.12.4]
#
# Output: <out>/nvim-bundle-linux-x86_64-<date>.tar.gz
#   config/            config directory
#   data/              nvim data directory (lazy plugins / mason tools / site)
#   nvim/              neovim binary (old-glibc build from neovim-releases, supports RHEL6/glibc2.17)
#   parser-sources/    treesitter parser sources (incl. perl with pre-generated parser.c, systemverilog fork)
#   tools/             optional external tool binary cache (set via --with-tools)
#   lazy-lock.json
#   manifest.txt
#
set -euo pipefail

OUT_DIR="$(pwd)"
WITH_TOOLS=""
NVIM_VER="v0.12.4"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"

while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT_DIR="$2"; shift 2;;
        --with-tools) WITH_TOOLS="$2"; shift 2;;
        --nvim-version) NVIM_VER="$2"; shift 2;;
        --proxy) export http_proxy="$2" https_proxy="$2"; shift 2;;
        *) echo "Unknown argument: $1"; exit 1;;
    esac
done

log()  { printf '\033[1;34m[package]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  [OK] %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\033[1;33m  [!] %s\033[0m\n' "$*"; }

BUNDLE_ROOT="$OUT_DIR/.bundle-tmp"
rm -rf "$BUNDLE_ROOT"; mkdir -p "$BUNDLE_ROOT"
mkdir -p "$BUNDLE_ROOT/parser-sources" "$BUNDLE_ROOT/tools"
MANIFEST="$BUNDLE_ROOT/manifest.txt"
: > "$MANIFEST"

# ---------------------------------------------------------------- Preflight checks
command -v nvim >/dev/null 2>&1 || err "nvim not found, run install.sh first"
command -v tree-sitter >/dev/null 2>&1 || err "tree-sitter CLI not found (needed to pre-generate the perl parser), install it first"
[ -f "$CONFIG_DIR/init.lua" ] || err "Config directory not found: $CONFIG_DIR"
[ -d "$DATA_DIR/lazy" ] || err "Plugins not installed, run install.sh first"
log "Packaging sources: config=$CONFIG_DIR  data=$DATA_DIR"

# ---------------------------------------------------------------- config + data
log "== Copying config and data =="
cp -a "$CONFIG_DIR" "$BUNDLE_ROOT/config"
rm -rf "$BUNDLE_ROOT/config/.git" "$BUNDLE_ROOT/config/lazy-lock.json"
cp -a "$DATA_DIR" "$BUNDLE_ROOT/data"
rm -rf "$BUNDLE_ROOT/data/backup" "$BUNDLE_ROOT/data/undo" "$BUNDLE_ROOT/data/swap" \
       "$BUNDLE_ROOT/data/view" "$BUNDLE_ROOT/data/shada" 2>/dev/null || true
ok "config + data copied"

# ---------------------------------------------------------------- nvim binary
log "== Downloading Neovim (old-glibc build) =="
mkdir -p "$BUNDLE_ROOT/nvim"
# neovim/neovim-releases provides prebuilt binaries that run on old glibc (2.17)
NVIM_URL="https://github.com/neovim/neovim-releases/releases/download/${NVIM_VER}/nvim-linux-x86_64.tar.gz"
# Bug L fix: bounded timeouts so a slow/unreachable host fails instead of hanging
curl -fL --retry 3 --connect-timeout 20 --max-time 600 "$NVIM_URL" -o "$BUNDLE_ROOT/nvim/nvim-linux-x86_64.tar.gz"
ok "nvim ${NVIM_VER} downloaded ($(du -h "$BUNDLE_ROOT/nvim/nvim-linux-x86_64.tar.gz" | cut -f1))"
echo "nvim=${NVIM_VER} url=${NVIM_URL}" >> "$MANIFEST"

# ---------------------------------------------------------------- Parser sources
log "== Downloading treesitter parser sources (pinned revisions) =="
PARSERS_LUA="$DATA_DIR/lazy/nvim-treesitter/lua/nvim-treesitter/parsers.lua"
[ -f "$PARSERS_LUA" ] || err "nvim-treesitter not found: $PARSERS_LUA"

# Read language list from config.parsers (old-bash compatible, no mapfile)
LANGS=()
while IFS= read -r line; do
    LANGS+=("$line")
done < <(grep -oE '"[a-z_]+"' "$CONFIG_DIR/lua/config/parsers.lua" | tr -d '"')
[ ${#LANGS[@]} -gt 0 ] || err "Failed to read config.parsers"
log "${#LANGS[@]} parsers: ${LANGS[*]}"

get_url() { grep -A8 "^  $1 = {" "$PARSERS_LUA" | grep "url = " | head -1 | sed -E "s/.*url = '([^']*)'.*/\1/"; }
get_rev() { grep -A8 "^  $1 = {" "$PARSERS_LUA" | grep "revision = " | head -1 | sed -E "s/.*revision = '([^']*)'.*/\1/"; }
get_gen() { grep -A8 "^  $1 = {" "$PARSERS_LUA" | grep -c "generate = true" || true; }

# Download source at a given revision -> output to $1, prefer codeload tarball, fall back to git
fetch_source() { # fetch_source <out.tar.gz> <owner> <repo> <rev>
    local out="$1" owner="$2" repo="$3" rev="$4"
    if curl -fsL --retry 1 --max-time 90 -o "$out" "https://codeload.github.com/${owner}/${repo}/tar.gz/${rev}" \
        && tar tzf "$out" >/dev/null 2>&1; then
        return 0
    fi
    warn "  codeload download failed ($repo), falling back to git ..."
    local gdir="$BUNDLE_ROOT/_git_${repo}"
    rm -rf "$gdir"; mkdir -p "$gdir"
    ( cd "$gdir" \
        && git init -q && git remote add origin "https://github.com/${owner}/${repo}.git" \
        && git fetch -q --depth 1 origin "$rev" \
        && git checkout -q FETCH_HEAD ) || { rm -rf "$gdir"; return 1; }
    tar czf "$out" -C "$BUNDLE_ROOT" "$(basename "$gdir")"
    rm -rf "$gdir"
    return 0
}

for lang in "${LANGS[@]}"; do
    if [ "$lang" = systemverilog ]; then
        # Config overrides to a personal fork (treesitter.lua)
        URL="https://github.com/lwflwf1/tree-sitter-systemverilog"
        log "  $lang -> fork $URL (master HEAD)"
        git clone --depth 1 "$URL" "$BUNDLE_ROOT/_sv" >/dev/null 2>&1
        REV="$(git -C "$BUNDLE_ROOT/_sv" rev-parse HEAD)"
        tar czf "$BUNDLE_ROOT/parser-sources/$lang.tar.gz" -C "$BUNDLE_ROOT" --transform 's/^_sv/tree-sitter-systemverilog/' _sv
        rm -rf "$BUNDLE_ROOT/_sv"
    else
        URL="$(get_url "$lang")"; REV="$(get_rev "$lang")"
        if [ -z "$URL" ] || [ -z "$REV" ]; then
            warn "  Skipping $lang (no url/revision in parsers.lua)"
            continue
        fi
        TGZ="$BUNDLE_ROOT/parser-sources/$lang.tar.gz"
        log "  $lang  ${URL}  @ ${REV:0:10}"
        # Extract owner/repo from the URL
        OWNER="$(echo "$URL" | sed -E 's#https://github.com/([^/]+)/.*#\1#')"
        REPO="$(echo "$URL" | sed -E 's#https://github.com/[^/]+/([^/]+).*#\1#')"
        fetch_source "$TGZ" "$OWNER" "$REPO" "$REV" \
            || { warn "  Fetch failed, skipping $lang"; continue; }
        if [ "$(get_gen "$lang")" = yes ]; then
            log "  $lang needs tree-sitter generate, pre-generating parser.c ..."
            work="$BUNDLE_ROOT/_gen"; rm -rf "$work"; mkdir -p "$work"
            tar xzf "$TGZ" -C "$work"
            dir="$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -1)"
            ( cd "$dir" && tree-sitter generate >/dev/null 2>&1 ) || warn "  generate failed, skipping $lang"
            tar czf "$TGZ" -C "$work" "$(basename "$dir")"
            rm -rf "$work"
        fi
    fi
    echo "parser $lang $URL $REV" >> "$MANIFEST"
done
rm -f "$BUNDLE_ROOT/parser-sources/.keep" 2>/dev/null || true
PSRC_COUNT="$(ls "$BUNDLE_ROOT/parser-sources" | grep -c '\.tar\.gz')"
log "Parser source packages: ${PSRC_COUNT}"
echo "parsers=${PSRC_COUNT}" >> "$MANIFEST"

# ---------------------------------------------------------------- Optional tool cache
if [ -n "$WITH_TOOLS" ]; then
    log "== Downloading external tool cache: $WITH_TOOLS =="
    for t in $WITH_TOOLS; do
        case "$t" in
rg)
                url="$(curl -s --max-time 30 https://api.github.com/repos/BurntSushi/ripgrep/releases/latest \
                       | grep -oE 'https://[^"]*x86_64-unknown-linux-musl\.tar\.gz' | head -1)"
                [ -n "$url" ] && { curl -fL --connect-timeout 20 --max-time 300 "$url" -o "$BUNDLE_ROOT/tools/rg.tar.gz"; echo "tool rg $url" >> "$MANIFEST"; ok "rg cached"; } || warn "rg download failed";;
            fd)
                url="$(curl -s --max-time 30 https://api.github.com/repos/sharkdp/fd/releases/latest \
                       | grep -oE 'https://[^"]*x86_64-unknown-linux-musl\.tar\.gz' | head -1)"
                [ -n "$url" ] && { curl -fL --connect-timeout 20 --max-time 300 "$url" -o "$BUNDLE_ROOT/tools/fd.tar.gz"; echo "tool fd $url" >> "$MANIFEST"; ok "fd cached"; } || warn "fd download failed";;
            fzf)
                url="$(curl -s --max-time 30 https://api.github.com/repos/junegunn/fzf/releases/latest \
                       | grep -oE 'https://[^"]*linux_amd64\.tar\.gz' | head -1)"
                [ -n "$url" ] && { curl -fL --connect-timeout 20 --max-time 300 "$url" -o "$BUNDLE_ROOT/tools/fzf.tar.gz"; echo "tool fzf $url" >> "$MANIFEST"; ok "fzf cached"; } || warn "fzf download failed";;
            tree-sitter-cli)
                url="https://github.com/tree-sitter/tree-sitter/releases/download/v0.26.12/tree-sitter-cli-linux-x64.gz"
                curl -fL --connect-timeout 20 --max-time 300 "$url" -o "$BUNDLE_ROOT/tools/tree-sitter-cli.gz"
                echo "tool tree-sitter-cli $url" >> "$MANIFEST"; ok "tree-sitter-cli cached";;
            *) warn "Unknown tool: $t";;
        esac
    done
fi

# ---------------------------------------------------------------- Packaging
log "== Generating bundle =="
cp "$CONFIG_DIR/lazy-lock.json" "$BUNDLE_ROOT/lazy-lock.json" 2>/dev/null || true
DATE="$(date +%Y%m%d)"
OUT="$OUT_DIR/nvim-bundle-linux-x86_64-$DATE.tar.gz"
tar czf "$OUT" -C "$BUNDLE_ROOT" . 2>/dev/null
rm -rf "$BUNDLE_ROOT"
ls -lh "$OUT"
ok "Packaging done: $OUT"
echo "Usage: copy $OUT to an intranet machine and run scripts/install-offline.sh <bundle-path>"