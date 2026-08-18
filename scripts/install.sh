#!/usr/bin/env bash
#
# nvim-config online installer (macOS + Linux / WSL)
#
# Usage:
#   ./install.sh [--proxy http://host:port]
#
# Behavior:
#   - Detects OS / distribution
#   - Interactive confirmation for external tools: skip if installed, otherwise install via package manager
#   - Installs neovim + git + gcc + tree-sitter-cli + node + python3 (required)
#   - Optional: rustup / fzf / rg / fd / perl / pandoc / verible
#   - Clones config to ~/.config/nvim
#   - Headless install: plugins (Lazy) + mason tools + treesitter parsers
#   - Verifies and reports results
#
set -euo pipefail

CONFIG_REPO="https://github.com/lwflwf1/nvim-config.git"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
PROXY="${1:-}"
if [ -n "$PROXY" ]; then
    export http_proxy="$PROXY" https_proxy="$PROXY"
fi

# ---------------------------------------------------------------- Basic utilities
log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m  [OK] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  [!] %s\033[0m\n' "$*"; }

confirm() { # $1=prompt  $2=default (y/N)
    local d="${2:-n}"
    read -r -p "$1" ans
    case "${ans:-$d}" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

# Interactive tool check: ask_tool <name> <install-command>
# Found -> skip; missing -> ask if manually installed -> otherwise run install command
ask_tool() {
    local name="$1" install_fn="$2"
    if command -v "$name" >/dev/null 2>&1; then
        ok "$name ($(command -v "$name"))"
        return 0
    fi
    warn "$name not found"
    if confirm "  Is $name already installed manually? [y/N] "; then
        if command -v "$name" >/dev/null 2>&1; then ok "$name confirmed available"; return 0; fi
        warn "$name still not found, skipping"
        return 1
    fi
    echo "  Auto-installing $name ..."
    eval "$install_fn"
    if command -v "$name" >/dev/null 2>&1; then ok "$name installed"; return 0; fi
    warn "$name install failed or not on PATH, skipping"
    return 1
}

# Run nvim headless with timeout, capture output, and require BOTH a clean exit
# code AND no error output. Bug I fix: nvim --headless exits 0 even when the
# config fails to load (E492/E5113), so the output must be inspected too.
# Returns 124 on timeout, 0 on success, nonzero otherwise.
run_headless() {
    local secs="$1"; shift
    local logf n rc pid
    logf="$(mktemp)"
    "$@" >"$logf" 2>&1 & pid=$!
    n=0; rc=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$n" -ge "$secs" ]; then
            kill -9 "$pid" 2>/dev/null || true
            warn "Timed out (${secs}s), killed: $*"
            rm -f "$logf"
            return 124
        fi
        sleep 2; n=$((n+2))
    done
    wait "$pid" || rc=$?
    if [ "$rc" -ne 0 ]; then rm -f "$logf"; return "$rc"; fi
    if grep -qE 'E[0-9]+: |Error detected|Error in ' "$logf"; then rm -f "$logf"; return 1; fi
    rm -f "$logf"
    return 0
}

count_parsers() { ls "$DATA_DIR/site/parser"/*.so 2>/dev/null | wc -l | tr -d ' '; }
EXPECTED_PARSERS=27

# ---------------------------------------------------------------- OS detection
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
    Darwin)
        PLATFORM="macos"
        if ! command -v brew >/dev/null 2>&1; then
            err "Homebrew required, install first: https://brew.sh"; exit 1
        fi
        ;;
    Linux)
        PLATFORM="linux"
        if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
            log "WSL detected ($WSL_DISTRO_NAME)"
        fi
        if command -v apk >/dev/null 2>&1; then PKG=apk
        elif command -v apt-get >/dev/null 2>&1; then PKG=apt
        elif command -v dnf >/dev/null 2>&1; then PKG=dnf
        elif command -v yum >/dev/null 2>&1; then PKG=yum
        else PKG=none; fi
        log "Linux package manager: $PKG"
        ;;
    *) err "Unsupported system: $OS (only macOS/Linux supported)"; exit 1;;
esac

log "Platform: $PLATFORM / $ARCH"

# ---------------------------------------------------------------- Package manager helpers
pkg_install() { # pkg_install pkg1 pkg2 ...
    case "$PLATFORM:$PKG" in
        macos:*)  brew install "$@" ;;
        linux:apk) sudo apk add --no-cache "$@" ;;
        linux:apt) sudo apt-get update -qq && sudo apt-get install -y "$@" ;;
        linux:dnf) sudo dnf install -y "$@" ;;
        linux:yum) sudo yum install -y "$@" ;;
        *) err "Cannot auto-install: $*"; return 1;;
    esac
}

# ---------------------------------------------------------------- Required tools
log "== Checking required tools =="
ask_tool git   "pkg_install git"
ask_tool gcc   "pkg_install gcc make"
ask_tool make  "pkg_install make"
ask_tool node  "pkg_install nodejs npm"
ask_tool npm   "pkg_install npm"
ask_tool python3 "pkg_install python3"
if [ "$PLATFORM" = macos ]; then
    ask_tool tree-sitter "brew install tree-sitter-cli"
else
    ask_tool tree-sitter "pkg_install tree-sitter-cli"
fi

# Bug E fix: required tools must be present or the install is aborted with a
# clear message (previously the script silently continued and failed later
# with a confusing error).
for t in git gcc make node npm python3 tree-sitter; do
    command -v "$t" >/dev/null 2>&1 || { err "Required tool '$t' is missing after the install attempt; install it manually and re-run (see the messages above)"; exit 1; }
done

# ---------------------------------------------------------------- Optional tools
log "== Optional tools (confirm as needed) =="
if command -v rustup >/dev/null 2>&1; then
    ok "rustup already present: $(command -v rustup)"
elif confirm "Install rust toolchain (rustup, provides rust-analyzer/rustfmt)? [y/N] "; then
    ask_tool rustup 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
    # Bug C fix: rustup only adds ~/.cargo/bin to PATH for new shells; make it
    # available in this session so the component check/add below works.
    export PATH="$HOME/.cargo/bin:$PATH"
    if command -v rustup >/dev/null 2>&1; then
        rustup component add rust-analyzer rustfmt 2>/dev/null || true
        ok "rust toolchain ready"
    fi
fi
if command -v fzf >/dev/null 2>&1 && command -v rg >/dev/null 2>&1 && command -v fd >/dev/null 2>&1; then
    ok "fzf / rg / fd already present"
elif confirm "Install fzf / rg / fd (fzf-lua search)? [y/N] "; then
    ask_tool fzf "pkg_install fzf"
    ask_tool rg  "pkg_install ripgrep"
    ask_tool fd  "pkg_install fd-find"
fi
if command -v perl >/dev/null 2>&1; then
    ok "perl already present: $(command -v perl)"
elif confirm "Install perl + perltidy (perltidy formatter)? [y/N] "; then
    if [ "$PLATFORM" = macos ]; then ask_tool perl "brew install perl perltidy"
    elif [ "$PKG" = apt ]; then ask_tool perl "pkg_install perl libperl-dev perltidy"
    elif [ "$PKG" = apk ]; then ask_tool perl "pkg_install perl perl-tidy"
    else ask_tool perl "pkg_install perl"; fi
fi
if command -v pandoc >/dev/null 2>&1 && command -v xelatex >/dev/null 2>&1; then
    ok "pandoc + xelatex already present"
elif confirm "Install pandoc + xelatex (orgmode export)? [y/N] "; then
    ask_tool pandoc "pkg_install pandoc"
    ask_tool xelatex "pkg_install texlive-xetex"
fi

# ---------------------------------------------------------------- Neovim
log "== Installing Neovim =="
if command -v nvim >/dev/null 2>&1; then
    ok "nvim $(nvim --version | head -1)"
    if [ "$(nvim --version | grep -oE 'v?0\.1[12]\.[0-9]+' | head -1)" = "" ]; then
        warn "nvim version may be too old (config requires >= 0.11, 0.12 recommended)"
    fi
else
    if [ "$PLATFORM" = macos ]; then
        brew install neovim
    else
        # Download official latest release tarball
        latest="$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep -oE '"tag_name": *"v[^"]+"' | head -1 | grep -oE 'v[0-9.]+' || true)"
        [ -z "$latest" ] && latest="v0.12.4"
        url="https://github.com/neovim/neovim/releases/download/${latest}/nvim-linux-${ARCH}.tar.gz"
        log "Downloading $url"
        curl -fL "$url" -o /tmp/nvim.tar.gz
        sudo tar xzf /tmp/nvim.tar.gz -C /usr/local --strip-components=1
        ok "nvim ${latest} installed"
    fi
fi

# ---------------------------------------------------------------- Config
log "== Cloning config =="
if [ -f "$CONFIG_DIR/init.lua" ]; then
    log "$CONFIG_DIR already exists, skipping clone (delete it first to reinstall)"
else
    # Bug F fix: check the clone result explicitly instead of relying on set -e.
    if ! git clone --depth 1 "$CONFIG_REPO" "$CONFIG_DIR"; then
        err "Config clone failed (check network/proxy). Retry with: git clone --depth 1 $CONFIG_REPO $CONFIG_DIR"
        exit 1
    fi
    [ -f "$CONFIG_DIR/init.lua" ] || { err "Config clone succeeded but init.lua is missing; re-run the installer"; exit 1; }
    ok "Config cloned to $CONFIG_DIR"
fi

# ---------------------------------------------------------------- Install plugins/tools/parsers
cd "$CONFIG_DIR"
log "== Installing plugins (Lazy) =="
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
for attempt in 1 2 3; do
    if run_headless 1500 nvim --headless "+Lazy! sync" +qa; then
        break
    fi
    warn "Lazy sync failed (attempt $attempt), clearing lazy.nvim cache and retrying ..."
    rm -rf "$DATA_DIR/lazy/lazy.nvim"
    sleep 3
    [ "$attempt" = 3 ] && { err "Plugin install failed, check network/proxy and retry"; exit 1; }
done
ok "Plugins installed"

log "== Installing mason tools + treesitter parsers (ToolInstall) =="
# Bug K fix: load mason explicitly first. It is lazy-loaded in the config, so
# headless nvim never activates it and every tool would be skipped as "unknown".
for attempt in 1 2 3; do
    run_headless 1500 nvim --headless +"lua require('mason').setup()" +ToolInstall +"sleep 240" +qa \
        || warn "ToolInstall attempt $attempt exited abnormally"
    cnt="$(count_parsers)"
    log "Parsers ready: $cnt/$EXPECTED_PARSERS (attempt $attempt)"
    [ "$cnt" -ge "$EXPECTED_PARSERS" ] && break
    sleep 3
    [ "$attempt" = 3 ] && warn "Parsers not fully installed ($cnt/$EXPECTED_PARSERS), run :ToolInstall later"
done
mason_count="$(ls "$DATA_DIR/mason/packages" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$mason_count" = 0 ]; then
    warn "No mason tools were installed headless; run :ToolInstall once in an interactive nvim session (needs network)"
else
    ok "mason tools installed ($mason_count)"
fi

# ---------------------------------------------------------------- PATH
log "== Configuring PATH (mason tools) =="
export PATH="$DATA_DIR/mason/bin:$PATH"
RC=""
case "${SHELL:-}" in
    *zsh)  RC="$HOME/.zshrc";;
    *bash) RC="$HOME/.bashrc";;
    *)     RC="$HOME/.profile";;
esac
if [ -n "$RC" ]; then
    grep -q "nvim/mason/bin" "$RC" 2>/dev/null || cat >> "$RC" <<EOF

# nvim-config: add mason tools (LSP / formatter) to PATH
export PATH="$DATA_DIR/mason/bin:\$PATH"
EOF
    ok "mason bin added to PATH ($RC), takes effect in new terminals"
fi

# ---------------------------------------------------------------- Verification
log "== Verification =="
plugins=$(ls "$DATA_DIR/lazy" 2>/dev/null | wc -l | tr -d ' ')
parsers=$(find "$DATA_DIR/site/parser" -name '*.so' 2>/dev/null | wc -l | tr -d ' ')
mason=$(ls "$DATA_DIR/mason/packages" 2>/dev/null | wc -l | tr -d ' ')
if run_headless 60 nvim --headless +qa; then
    ok "Startup verification passed"
else
    warn "Startup verification reported errors, run nvim manually to inspect"
fi
echo
log "Installation done: plugins=$plugins  parsers=$parsers  masonTools=$mason"
log "Run nvim to get started."