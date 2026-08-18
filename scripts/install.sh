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
PROXY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --proxy) PROXY="${2:-}"; shift 2;;
        -*) echo "Unknown argument: $1"; exit 1;;
        *) PROXY="$1"; shift;;
    esac
done
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
    eval "$install_fn" || true   # set -e safety: failures are handled below (warn)
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
# Asset names differ from uname -m: aarch64 -> arm64 (nvim/rg/fd), armv7l (fzf)
case "$ARCH" in
    x86_64)       NVIM_ARCH="x86_64"; GH_ARCH="x86_64"; FZF_ARCH="linux_amd64"; NODE_ARCH="linux-x64"; TSCLI_ARCH="x64"; PANDOC_ARCH="amd64";;
    aarch64|arm64) NVIM_ARCH="arm64"; GH_ARCH="aarch64"; FZF_ARCH="linux_arm64"; NODE_ARCH="linux-arm64"; TSCLI_ARCH="arm64"; PANDOC_ARCH="arm64";;
    armv7l)       NVIM_ARCH="armv7l"; GH_ARCH="arm"; FZF_ARCH="linux_armv7"; NODE_ARCH="linux-armv7l"; TSCLI_ARCH="arm"; PANDOC_ARCH="";;
    *)            NVIM_ARCH="$ARCH"; GH_ARCH="$ARCH"; FZF_ARCH="linux_$ARCH"; NODE_ARCH="linux-$ARCH"; TSCLI_ARCH="$ARCH"; PANDOC_ARCH="";;
esac
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

# ---------------------------------------------------------------- Privilege detection
# Without admin rights (or a usable package manager) the tools are downloaded
# manually and installed under the user's home directory instead.
USER_MODE=0
USER_DIR="$HOME/.local"
if [ "$(id -u)" = 0 ]; then
    log "Running as root; system-wide installs possible"
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    log "sudo available; system-wide installs possible"
elif command -v sudo >/dev/null 2>&1; then
    log "sudo present (may prompt for a password)"
else
    warn "No admin rights (no sudo); falling back to user-local installs under $USER_DIR"
    USER_MODE=1
fi
if [ "$PLATFORM" = linux ] && [ "$PKG" = none ]; then
    warn "No package manager detected; falling back to user-local installs"
    USER_MODE=1
fi
if [ "$USER_MODE" = 1 ]; then
    log "USER MODE: tools will be downloaded and installed under $USER_DIR"
fi

# ---------------------------------------------------------------- Package manager helpers
pkg_install() { # pkg_install pkg1 pkg2 ...
    if [ "$USER_MODE" = 1 ]; then
        warn "No admin rights; skipping package-manager install: $*"
        return 1
    fi
    case "$PLATFORM:$PKG" in
        macos:*)  brew install "$@" ;;
        linux:apk) if [ "$(id -u)" = 0 ]; then apk add --no-cache "$@"; else sudo apk add --no-cache "$@"; fi ;;
        linux:apt) if [ "$(id -u)" = 0 ]; then apt-get update -qq && apt-get install -y "$@"; else sudo apt-get update -qq && sudo apt-get install -y "$@"; fi ;;
        linux:dnf) if [ "$(id -u)" = 0 ]; then dnf install -y "$@"; else sudo dnf install -y "$@"; fi ;;
        linux:yum) if [ "$(id -u)" = 0 ]; then yum install -y "$@"; else sudo yum install -y "$@"; fi ;;
        *) err "Cannot auto-install: $*"; return 1;;
    esac
}

# User-local installs (no admin rights / no usable package manager): download
# the official binaries and install them under $USER_DIR (~/.local).
#   ~/.local/bin/      single-file tools (tree-sitter, fzf, rg, fd)
#   ~/.local/node/     node (bin/ inside)
#   ~/.local/pandoc/   pandoc (bin/ inside)
#   ~/.local/nvim/     neovim (bin/ inside)

user_install_node() {
    local ver url dir
    ver="$(curl -fsSL --max-time 30 https://nodejs.org/dist/latest/ \
        | grep -oE "node-v[0-9]+\.[0-9]+\.[0-9]+-${NODE_ARCH}\.tar\.xz" | head -1 || true)"
    [ -n "$ver" ] || { warn "  failed to resolve node version"; return 1; }
    url="https://nodejs.org/dist/latest/$ver"
    echo "  Downloading $url"
    curl -fL --connect-timeout 20 --max-time 600 "$url" -o /tmp/node.tar.xz || { warn "  node download failed"; return 1; }
    mkdir -p "$USER_DIR"
    tar xf /tmp/node.tar.xz -C "$USER_DIR"
    dir="${ver%.tar.xz}"
    rm -rf "$USER_DIR/node"
    mv "$USER_DIR/$dir" "$USER_DIR/node"
    export PATH="$USER_DIR/node/bin:$PATH"
    ok "node installed to $USER_DIR/node"
}

user_install_tree_sitter() {
    local url bin
    url="$(curl -fsSL --max-time 30 "https://api.github.com/repos/tree-sitter/tree-sitter/releases/latest" \
        | grep -oE '"browser_download_url": *"[^"]*tree-sitter-cli-linux-'"${TSCLI_ARCH}"'\.(zip|gz)"' \
        | grep -oE 'https://[^"]*' | head -1 || true)"
    [ -n "$url" ] || { warn "  failed to resolve tree-sitter CLI URL"; return 1; }
    echo "  Downloading $url"
    curl -fL --connect-timeout 20 --max-time 300 "$url" -o /tmp/tscli.dl || { warn "  tree-sitter download failed"; return 1; }
    mkdir -p "$USER_DIR/bin" /tmp/tscli
    case "$url" in
        *.zip)
            if command -v unzip >/dev/null 2>&1; then
                unzip -oq /tmp/tscli.dl -d /tmp/tscli
            else
                python3 -m zipfile -e /tmp/tscli.dl /tmp/tscli
            fi;;
        *) gunzip -c /tmp/tscli.dl > /tmp/tscli/tree-sitter;;
    esac
    bin="$(find /tmp/tscli -name tree-sitter -type f | head -1)"
    [ -n "$bin" ] || { warn "  tree-sitter binary not found in archive"; return 1; }
    mv -f "$bin" "$USER_DIR/bin/tree-sitter" && chmod +x "$USER_DIR/bin/tree-sitter"
    export PATH="$USER_DIR/bin:$PATH"
    ok "tree-sitter installed to $USER_DIR/bin"
}

user_install_gh_bin() { # user_install_gh_bin <owner/repo> <asset-regex> <binary-name>
    local repo="$1" pat="$2" bin="$3" url found
    url="$(curl -fsSL --max-time 30 "https://api.github.com/repos/$repo/releases/latest" \
        | grep -oE '"browser_download_url": *"[^"]*' | grep -oE 'https://[^"]*' \
        | grep -E "$pat" | head -1 || true)"
    [ -n "$url" ] || { warn "  failed to resolve $bin download URL"; return 1; }
    echo "  Downloading $url"
    curl -fL --connect-timeout 20 --max-time 300 "$url" -o /tmp/tool.tar.gz || { warn "  $bin download failed"; return 1; }
    mkdir -p "$USER_DIR/bin"
    tar xzf /tmp/tool.tar.gz -C "$USER_DIR/bin" 2>/dev/null || gunzip -c /tmp/tool.tar.gz > "$USER_DIR/bin/$bin"
    found="$(find "$USER_DIR/bin" -name "$bin" -type f | head -1)"
    [ -n "$found" ] || { warn "  $bin not found in the archive"; return 1; }
    chmod +x "$found"
    [ "$found" != "$USER_DIR/bin/$bin" ] && mv -f "$found" "$USER_DIR/bin/$bin"
    export PATH="$USER_DIR/bin:$PATH"
    ok "$bin installed to $USER_DIR/bin"
}

user_install_pandoc() {
    local ver url
    [ -n "$PANDOC_ARCH" ] || { warn "  no pandoc binary for $ARCH"; return 1; }
    ver="$(curl -fsSL --max-time 30 "https://api.github.com/repos/jgm/pandoc/releases/latest" \
        | grep -oE '"tag_name": *"[^"]*"' | grep -oE '[0-9.]+' | head -1 || true)"
    [ -n "$ver" ] || { warn "  failed to resolve pandoc version"; return 1; }
    url="https://github.com/jgm/pandoc/releases/download/${ver}/pandoc-${ver}-linux-${PANDOC_ARCH}.tar.gz"
    echo "  Downloading $url"
    curl -fL --connect-timeout 20 --max-time 600 "$url" -o /tmp/pandoc.tar.gz || { warn "  pandoc download failed"; return 1; }
    tar xzf /tmp/pandoc.tar.gz -C "$USER_DIR"
    rm -rf "$USER_DIR/pandoc"
    mv "$USER_DIR/pandoc-${ver}" "$USER_DIR/pandoc"
    export PATH="$USER_DIR/pandoc/bin:$PATH"
    ok "pandoc installed to $USER_DIR/pandoc"
}

user_install_nvim() { # Linux only (macOS uses brew)
    local latest url
    latest="$(curl -s --max-time 30 https://api.github.com/repos/neovim/neovim/releases/latest \
        | grep -oE '"tag_name": *"v[^"]+"' | head -1 | grep -oE 'v[0-9.]+' || true)"
    [ -z "$latest" ] && latest="v0.12.4"
    url="https://github.com/neovim/neovim/releases/download/${latest}/nvim-linux-${NVIM_ARCH}.tar.gz"
    log "Downloading $url"
    curl -fL --connect-timeout 20 --max-time 600 "$url" -o /tmp/nvim.tar.gz || { warn "  nvim download failed"; return 1; }
    mkdir -p "$USER_DIR"
    tar xzf /tmp/nvim.tar.gz -C "$USER_DIR"
    rm -rf "$USER_DIR/nvim"
    mv "$USER_DIR/nvim-linux-${NVIM_ARCH}" "$USER_DIR/nvim"
    export PATH="$USER_DIR/nvim/bin:$PATH"
    ok "nvim ${latest} installed to $USER_DIR/nvim"
}

# ---------------------------------------------------------------- Required tools
log "== Checking required tools =="
ask_tool git   "pkg_install git"
ask_tool gcc   "pkg_install gcc make"
ask_tool make  "pkg_install make"
ask_tool node  "pkg_install nodejs npm || user_install_node"
ask_tool npm   "pkg_install npm"
ask_tool python3 "pkg_install python3"
if [ "$PLATFORM" = macos ]; then
    ask_tool tree-sitter "brew install tree-sitter-cli"
else
    ask_tool tree-sitter "pkg_install tree-sitter-cli || user_install_tree_sitter"
fi

# Bug E fix: required tools must be present or the install is aborted with a
# clear message (previously the script silently continued and failed later
# with a confusing error). In USER MODE only node/tree-sitter can be
# auto-installed (official binaries); the rest need admin rights or manual
# installation.
for t in git gcc make node npm python3 tree-sitter; do
    if ! command -v "$t" >/dev/null 2>&1; then
        if [ "$USER_MODE" = 1 ]; then
            err "Required tool '$t' could not be auto-installed without admin rights; install it manually (e.g. into $USER_DIR/bin) and re-run. Note: gcc/make are needed to compile the treesitter parsers."
        else
            err "Required tool '$t' is missing after the install attempt; install it manually and re-run (see the messages above)"
        fi
        exit 1
    fi
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
    ask_tool fzf "pkg_install fzf || user_install_gh_bin junegunn/fzf 'fzf-.*-${FZF_ARCH}\\.tar\\.gz' fzf"
    ask_tool rg  "pkg_install ripgrep || user_install_gh_bin BurntSushi/ripgrep '.*${GH_ARCH}-unknown-linux-musl.*\\.tar\\.gz' rg"
    ask_tool fd  "pkg_install fd-find || user_install_gh_bin sharkdp/fd '.*${GH_ARCH}-unknown-linux-musl.*\\.tar\\.gz' fd"
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
    ask_tool pandoc "pkg_install pandoc || user_install_pandoc"
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
    elif [ "$USER_MODE" = 1 ]; then
        user_install_nvim
        command -v nvim >/dev/null 2>&1 || { err "nvim install to $USER_DIR/nvim failed; install it manually"; exit 1; }
    else
        # Download official latest release tarball
        latest="$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep -oE '"tag_name": *"v[^"]+"' | head -1 | grep -oE 'v[0-9.]+' || true)"
        [ -z "$latest" ] && latest="v0.12.4"
        url="https://github.com/neovim/neovim/releases/download/${latest}/nvim-linux-${NVIM_ARCH}.tar.gz"
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
# Keep nvim alive while the async installs finish. Sleep is in MILLISECONDS
# ('m' suffix; bare `sleep 240` is 240 SECONDS). Give fresh compiles a
# 5-minute window, only 10s once parsers are all present.
for attempt in 1 2 3; do
    cnt_now="$(count_parsers)"
    if [ "$cnt_now" -ge "$EXPECTED_PARSERS" ]; then sleep_ms=10000; else sleep_ms=300000; fi
    run_headless 1500 nvim --headless +"lua require('mason').setup()" +ToolInstall +"sleep ${sleep_ms}m" +qa \
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
if [ "$USER_MODE" = 1 ]; then
    export PATH="$USER_DIR/nvim/bin:$USER_DIR/node/bin:$USER_DIR/pandoc/bin:$USER_DIR/bin:$PATH"
fi
RC=""
case "${SHELL:-}" in
    *zsh)  RC="$HOME/.zshrc";;
    *bash) RC="$HOME/.bashrc";;
    *tcsh) RC="$HOME/.cshrc";;
    *)     RC="$HOME/.profile";;
esac
if [ -n "$RC" ]; then
    if [ "$USER_MODE" = 1 ]; then
        grep -q "nvim-config: user-local" "$RC" 2>/dev/null || cat >> "$RC" <<EOF

# nvim-config: user-local tools (installed without admin rights)
export PATH="$USER_DIR/nvim/bin:$USER_DIR/node/bin:$USER_DIR/pandoc/bin:$USER_DIR/bin:\$PATH"
EOF
        ok "user-local tool dirs added to PATH ($RC), takes effect in new terminals"
    fi
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
if [ "$USER_MODE" = 1 ]; then
    log "User-local install mode: tools live under $USER_DIR (PATH updated in $RC)"
fi
log "Run nvim to get started."