#!/usr/bin/env bash
#
# nvim-config packaging script (Linux only, run on an online/installed machine)
#
# Usage:
#   ./package.sh [--out DIR] [--nvim-version v0.12.4]
#               [--config-repo URL] [--config-rev REF]
#   Every download group is confirmed interactively (default answer: download).
#   Piped answers are honored; a closed stdin (CI/background) auto-accepts.
#
# Output: <out>/nvim-bundle-linux-x86_64-<date>.tar.gz
#   config/            config directory (git clone of the remote, default
#                      https://github.com/lwflwf1/nvim-config.git)
#   data/              nvim data directory (lazy plugins only)
#   nvim/              neovim binary (old-glibc build from neovim-releases, supports RHEL6/glibc2.17)
#   parser-sources/    treesitter parser sources (incl. perl with pre-generated parser.c, systemverilog fork)
#   tools/             optional external tool binary cache (selected interactively)
#   lazy-lock.json
#   manifest.txt
#
set -euo pipefail

OUT_DIR="$(pwd)"
NVIM_VER=""
CONFIG_REPO="https://github.com/lwflwf1/nvim-config.git"
CONFIG_REV=""
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_JSON="$SCRIPT_DIR/tools.json"

while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT_DIR="$2"; shift 2;;
        --nvim-version) NVIM_VER="$2"; shift 2;;
        --tools-file) TOOLS_JSON="$2"; shift 2;;
        --config-repo) CONFIG_REPO="$2"; shift 2;;
        --config-rev) CONFIG_REV="$2"; shift 2;;
        --proxy) export http_proxy="$2" https_proxy="$2"; shift 2;;
        *) echo "Unknown argument: $1"; exit 1;;
    esac
done

# tools.json is the single source of truth for every downloadable asset. The
# packaging machine has python3 (needed for npm install anyway), so we use it to
# resolve versions/URLs, read/write the version cache, and emit the installer's
# tools.sh companion. The offline installer itself never parses JSON.
run_py() { python3 - "$@" <<'PYEOF'
import json, sys, os, fnmatch, urllib.request

def get_json(u):
    try:
        with urllib.request.urlopen(u, timeout=30) as r:
            return json.load(r)
    except Exception:
        return None

def resolve_entry(e):
    src = e.get("source")
    if src == "nodejs":
        ver = e.get("version") or (get_json(e["latest_url"]) or [{}])[0].get("version")
        if not ver:
            return None, None
        return ver, e["url_template"].replace("{version}", ver)
    owner, repo, glob = e["owner"], e["repo"], e["asset_glob"]
    tag = e.get("version")
    rel = get_json("https://api.github.com/repos/%s/%s/releases/tags/%s" % (owner, repo, tag)) if tag \
          else get_json("https://api.github.com/repos/%s/%s/releases/latest" % (owner, repo))
    if not rel:
        return None, None
    if not tag:
        tag = rel.get("tag_name")
    for a in rel.get("assets", []):
        if fnmatch.fnmatch(a["name"], glob):
            return tag, a["browser_download_url"]
    return None, None

cmd, jp = sys.argv[1], sys.argv[2]
data = json.load(open(jp))
tools = {t["name"]: t for t in data["tools"]}

if cmd == "resolve":
    name = sys.argv[3]
    e = dict(tools[name])
    if len(sys.argv) > 4 and sys.argv[4]:
        e["version"] = sys.argv[4]   # pin override (e.g. --nvim-version)
    ver, url = resolve_entry(e)
    out = e.get("out_file", "")
    ext = out.split(".", 1)[1] if "." in out else ""
    cache_dir = sys.argv[5] if len(sys.argv) > 5 else ""
    cache_name = "%s-%s.%s" % (name, ver, ext) if ver else ""
    hit = 0
    if cache_dir and ver and os.path.exists(os.path.join(cache_dir, "versions.json")):
        try:
            vj = json.load(open(os.path.join(cache_dir, "versions.json")))
            if vj.get(name) == ver and os.path.exists(os.path.join(cache_dir, cache_name)):
                hit = 1
        except Exception:
            pass
    print("\t".join([str(ver or ""), str(url or ""), cache_name, str(hit),
                     out, e.get("binary", ""), e.get("install", "bin"),
                     "1" if e.get("glibc234") else "0", e.get("realpath", "")]))
elif cmd == "cache_set":
    name, ver, cache_dir = sys.argv[3], sys.argv[4], sys.argv[5]
    vf = os.path.join(cache_dir, "versions.json")
    vj = {}
    if os.path.exists(vf):
        try:
            vj = json.load(open(vf))
        except Exception:
            vj = {}
    vj[name] = ver
    json.dump(vj, open(vf, "w"))
elif cmd == "emit_sh":
    dl = [t["name"] for t in data["tools"] if t.get("source") != "external"]
    gl = [t["name"] for t in data["tools"] if t.get("glibc234")]
    lines = ["# GENERATED from tools.json - do not edit",
             'TOOLS_DOWNLOAD="%s"' % " ".join(dl),
             'TOOLS_GLIBC="%s"' % " ".join(gl)]
    for t in data["tools"]:
        nm = t["name"]
        lines.append('%s_install="%s"' % (nm, t.get("install", "bin")))
        lines.append('%s_binary="%s"' % (nm, t.get("binary", "")))
        lines.append('%s_outfile="%s"' % (nm, t.get("out_file", "")))
        lines.append('%s_glibc234="%s"' % (nm, "1" if t.get("glibc234") else "0"))
        lines.append('%s_realpath="%s"' % (nm, t.get("realpath", "")))
    sys.stdout.write("\n".join(lines) + "\n")
elif cmd == "npm_list":
    print(" ".join(data.get("npm", [])))
PYEOF
}

# --nvim-version overrides the pinned version for nvim; empty = follow latest
# (resolved later from tools.json). Kept separate from the old pre-resolution so
# we don't burn an extra API call before the download prompt.

log()  { printf '\033[1;34m[package]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  [OK] %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\033[1;33m  [!] %s\033[0m\n' "$*"; }

# Interactive download confirmation. Default answer is YES (download).
# Non-TTY stdin: piped answers are honored; no input at all (CI/background,
# closed stdin) falls back to YES after a short timeout instead of hanging.
confirm_download() { # confirm_download <prompt> -> 0 = download
    local ans
    if [ -t 0 ]; then
        read -r -p "$1" ans
    else
        read -r -t 30 -p "$1" ans 2>/dev/null || return 0
    fi
    case "${ans:-y}" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

# P1 fix: on WSL the Windows-interop paths (/mnt/c/...) sit at the END of PATH
# and can shadow Linux tools with non-executable Windows shims (tree-sitter
# would resolve to node.exe and every download/parse would fail).
if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
    log "WSL detected (${WSL_DISTRO_NAME:-unknown}), stripping Windows-interop paths from PATH"
    export PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd ':' -)"
fi

# P6 fix: bounded git transfers (codeload fallback path)
export GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=30

# P7 fix: report a clear non-zero exit instead of a silent rc=1
trap 'rc=$?; if [ "$rc" -ne 0 ]; then printf "\033[1;31m[error]\033[0m script exited with rc=$rc\n" >&2; fi' EXIT

BUNDLE_ROOT="$OUT_DIR/.bundle-tmp"
rm -rf "$BUNDLE_ROOT"; mkdir -p "$BUNDLE_ROOT"
mkdir -p "$BUNDLE_ROOT/parser-sources" "$BUNDLE_ROOT/tools"
MANIFEST="$BUNDLE_ROOT/manifest.txt"
: > "$MANIFEST"
echo "format=2" >> "$MANIFEST"

# ---------------------------------------------------------------- Preflight checks
# P5 fix: this script only knows how to build x86_64 bundles
[ "$(uname -m)" = "x86_64" ] || err "package.sh only builds x86_64 bundles (host is $(uname -m))"
# P2 fix: smoke-test the binaries, not just their presence (a Windows shim or a
# non-executable binary would pass `command -v` and fail confusingly later)
command -v nvim >/dev/null 2>&1 && nvim --version >/dev/null 2>&1 \
    || err "nvim not found or not runnable, run install.sh first"
command -v tree-sitter >/dev/null 2>&1 && tree-sitter --version >/dev/null 2>&1 \
    || err "tree-sitter CLI missing or not runnable (needed to pre-generate the perl parser), install it first"
command -v git >/dev/null 2>&1 || err "git not found, needed to clone the config repository"
[ -d "$DATA_DIR/lazy" ] || err "Plugins not installed, run install.sh first"
log "Packaging sources: config=$CONFIG_REPO (rev=$CONFIG_REV)  data=$DATA_DIR"

# ---------------------------------------------------------------- config (clone) + data (lazy only)
log "== Cloning config from $CONFIG_REPO =="
git clone --depth 1 ${CONFIG_REV:+--branch "$CONFIG_REV"} "$CONFIG_REPO" "$BUNDLE_ROOT/config" \
    || err "config clone failed from $CONFIG_REPO (check proxy/network/auth)"
rm -rf "$BUNDLE_ROOT/config/.git" "$BUNDLE_ROOT/config/lazy-lock.json"
# Point downstream reads (parsers.lua, lazy-lock.json) at the CLONE.
CONFIG_DIR="$BUNDLE_ROOT/config"
log "== Copying data (lazy plugins only) =="
mkdir -p "$BUNDLE_ROOT/data"
cp -a "$DATA_DIR/lazy" "$BUNDLE_ROOT/data/lazy"
# Belt-and-suspenders: drop Windows binaries that may have slipped into plugins.
find "$BUNDLE_ROOT/data" -type f \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.cmd' -o -iname '*.bat' \) -delete 2>/dev/null || true
ok "config + data copied"
# No mason/ packages are bundled (Linux tools come from tools/ + npm-tools).
echo "mason=0" >> "$MANIFEST"

# ---------------------------------------------------------------- nvim binary (driven by tools.json)
log "== Neovim binary (old-glibc build, from tools.json) =="
NVIM_CACHE="$OUT_DIR/.nvim-tool-cache"; mkdir -p "$NVIM_CACHE"
IFS=$'\t' read -r NVIM_VER NVIM_URL NVIM_CACHE_NAME NVIM_HIT NVIM_OUTFILE NVIM_BIN NVIM_INST NVIM_GL NVIM_RP \
    < <(run_py resolve nvim "$TOOLS_JSON" "$NVIM_VER" "$NVIM_CACHE")
[ -n "$NVIM_URL" ] || err "Failed to resolve nvim version from tools.json"
if command -v nvim >/dev/null 2>&1 && nvim --version >/dev/null 2>&1; then
    warn "local nvim: $(nvim --version | head -1) (bundle carries its own old-glibc build)"
fi
if confirm_download "Download and bundle neovim ${NVIM_VER} (old-glibc build for offline machines)? [Y/n] "; then
    mkdir -p "$BUNDLE_ROOT/nvim"
    if [ "$NVIM_HIT" = "1" ]; then
        cp "$NVIM_CACHE/$NVIM_CACHE_NAME" "$BUNDLE_ROOT/nvim/nvim-linux-x86_64.tar.gz"
        ok "nvim ${NVIM_VER} (cached)"
    else
        # Bug L fix: bounded timeouts so a slow/unreachable host fails instead of hanging
        curl -fL --retry 3 --connect-timeout 20 --max-time 600 "$NVIM_URL" -o "$BUNDLE_ROOT/nvim/nvim-linux-x86_64.tar.gz"
        cp "$BUNDLE_ROOT/nvim/nvim-linux-x86_64.tar.gz" "$NVIM_CACHE/$NVIM_CACHE_NAME"
        run_py cache_set nvim "$NVIM_VER" "$NVIM_CACHE"
        ok "nvim ${NVIM_VER} downloaded ($(du -h "$BUNDLE_ROOT/nvim/nvim-linux-x86_64.tar.gz" | cut -f1))"
    fi
    echo "nvim=${NVIM_VER} url=${NVIM_URL}" >> "$MANIFEST"
else
    warn "nvim binary skipped — offline machines keep their existing nvim"
fi

# ---------------------------------------------------------------- Parser sources
log "== Treesitter parser sources (pinned revisions) =="
PARSERS_LUA="$DATA_DIR/lazy/nvim-treesitter/lua/nvim-treesitter/parsers.lua"
[ -f "$PARSERS_LUA" ] || err "nvim-treesitter not found: $PARSERS_LUA"

# Read language list from config.parsers (old-bash compatible, no mapfile)
LANGS=()
while IFS= read -r line; do
    LANGS+=("$line")
done < <(grep -oE '"[a-z_]+"' "$CONFIG_DIR/lua/config/parsers.lua" | tr -d '"')
[ ${#LANGS[@]} -gt 0 ] || err "Failed to read config.parsers"
log "${#LANGS[@]} parsers: ${LANGS[*]}"

if confirm_download "Download sources for ${#LANGS[@]} treesitter parsers (needed to compile new parsers offline)? [Y/n] "; then

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

GEN_FAILED=""
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
        # P3 fix: get_gen returns a COUNT (grep -c), not "yes" — the old test
        # never matched, so perl (generate = true) was never pre-generated and
        # the bundle header line was a lie. Fail loud if generation fails.
        if [ "$(get_gen "$lang")" -gt 0 ]; then
            log "  $lang needs tree-sitter generate, pre-generating parser.c ..."
            work="$BUNDLE_ROOT/_gen"; rm -rf "$work"; mkdir -p "$work"
            tar xzf "$TGZ" -C "$work"
            dir="$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -1)"
            if ( cd "$dir" && tree-sitter generate >/dev/null 2>&1 ); then
                ok "  $lang parser.c generated"
            else
                GEN_FAILED="$GEN_FAILED $lang"
                warn "  generate failed for $lang (bundle will lack parser.c)"
            fi
            tar czf "$TGZ" -C "$work" "$(basename "$dir")"
            rm -rf "$work"
        fi
    fi
    echo "parser $lang $URL $REV" >> "$MANIFEST"
done
[ -z "$GEN_FAILED" ] || err "tree-sitter generate failed for:$GEN_FAILED — fix the parser sources before packaging"
rm -f "$BUNDLE_ROOT/parser-sources/.keep" 2>/dev/null || true
PSRC_COUNT="$(ls "$BUNDLE_ROOT/parser-sources" | grep -c '\.tar\.gz')"
log "Parser source packages: ${PSRC_COUNT}"
else
    warn "Parser sources skipped — offline machines keep their existing compiled parsers"
    PSRC_COUNT=0
fi
echo "parsers=${PSRC_COUNT}" >> "$MANIFEST"

# ---------------------------------------------------------------- Optional tool cache (driven by tools.json)
TOOLS_JSON_PATH="$TOOLS_JSON"
CACHE_DIR="$OUT_DIR/.nvim-tool-cache"; mkdir -p "$CACHE_DIR"
# Emit tools.sh companion for install-offline.sh + copy tools.json into the bundle
run_py emit_sh "$TOOLS_JSON" > "$BUNDLE_ROOT/tools.sh"
cp "$TOOLS_JSON" "$BUNDLE_ROOT/tools.json"
source "$BUNDLE_ROOT/tools.sh"
# Downloadable tools = everything in TOOLS_DOWNLOAD except nvim (handled above)
DL_TOOLS=""
for t in $TOOLS_DOWNLOAD; do
    [ "$t" = nvim ] && continue
    DL_TOOLS="$DL_TOOLS $t"
done
DL_TOOLS="${DL_TOOLS# }"
log "== External tool cache (from tools.json:${DL_TOOLS}) =="
if confirm_download "Process external tool cache for offline install? [Y/n] "; then
    for t in $DL_TOOLS; do
        IFS=$'\t' read -r TVER TURL TCACHE THIT TOUT TBIN TINST TGL TRP \
            < <(run_py resolve "$t" "$TOOLS_JSON" "" "$CACHE_DIR")
        [ -n "$TURL" ] || { warn "$t resolution failed"; continue; }
        local_hint=""
        if command -v "$TBIN" >/dev/null 2>&1 && "$TBIN" --version >/dev/null 2>&1; then
            local_hint="  (local: $("$TBIN" --version 2>/dev/null | head -1))"
        fi
        if ! confirm_download "  Download and bundle $t $TVER?$local_hint [Y/n] "; then
            warn "  $t skipped"
            continue
        fi
        if [ "$THIT" = "1" ]; then
            cp "$CACHE_DIR/$TCACHE" "$BUNDLE_ROOT/tools/$TOUT"
            ok "$t $TVER (cached, skipped download)"
        else
            curl -fL --retry 3 --connect-timeout 20 --max-time 600 "$TURL" -o "$BUNDLE_ROOT/tools/$TOUT"
            cp "$BUNDLE_ROOT/tools/$TOUT" "$CACHE_DIR/$TCACHE"
            run_py cache_set "$t" "$TVER" "$CACHE_DIR"
            ok "$t $TVER cached"
        fi
        echo "tool $t $TVER $TURL" >> "$MANIFEST"
        [ "$TGL" = "1" ] && echo "glibc234 $t" >> "$MANIFEST"
    done
else
    warn "External tool cache skipped"
fi

# ---------------------------------------------------------------- npm tools cache (offline mason fallback)
log "== npm tools cache (offline fallback for mason npm packages) =="
NPM_TOOLS="$(run_py npm_list "$TOOLS_JSON")"
if confirm_download "Bundle npm tools ($NPM_TOOLS)? [Y/n] "; then
    if command -v npm >/dev/null 2>&1 && npm --version >/dev/null 2>&1; then
        NP="$BUNDLE_ROOT/npmtools"
        mkdir -p "$NP"
        if ( cd "$NP" && npm install --no-audit --no-fund --loglevel=error $NPM_TOOLS >/dev/null 2>&1 ) \
           && [ -d "$NP/node_modules" ]; then
            tar czf "$BUNDLE_ROOT/tools/npm-tools.tar.gz" -C "$NP" node_modules
            echo "npmtools=$(md5sum "$BUNDLE_ROOT/tools/npm-tools.tar.gz" | cut -d' ' -f1)" >> "$MANIFEST"
            ok "npm tools cached: $NPM_TOOLS"
        else
            warn "npm install failed, npm-tools cache skipped (tools will need an online :MasonInstall)"
        fi
        rm -rf "$NP"
    else
        warn "npm not found, npm-tools cache skipped"
    fi
else
    warn "npm tools cache skipped"
fi

# ---------------------------------------------------------------- Packaging
log "== Generating bundle =="
cp "$CONFIG_DIR/lazy-lock.json" "$BUNDLE_ROOT/lazy-lock.json" 2>/dev/null || true
echo "lazylock=$(md5sum "$BUNDLE_ROOT/lazy-lock.json" 2>/dev/null | cut -d' ' -f1 || true)" >> "$MANIFEST"
DATE="$(date +%Y%m%d)"
OUT="$OUT_DIR/nvim-bundle-linux-x86_64-$DATE.tar.gz"
tar czf "$OUT" -C "$BUNDLE_ROOT" . 2>/dev/null
rm -rf "$BUNDLE_ROOT"
ls -lh "$OUT"
ok "Packaging done: $OUT"
echo "Usage: copy $OUT to an intranet machine and run scripts/install-offline.sh <bundle-path> [--update]"