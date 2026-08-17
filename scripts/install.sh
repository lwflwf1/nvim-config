#!/usr/bin/env bash
#
# nvim-config 在线安装脚本 (macOS + Linux / WSL)
#
# 用法:
#   ./install.sh [--proxy http://host:port]
#
# 行为:
#   - 检测操作系统 / 发行版
#   - 交互式确认外部工具: 已安装则跳过, 否则按包管理器安装
#   - 安装 neovim + git + gcc + tree-sitter-cli + node + python3 (必需)
#   - 可选: rustup / fzf / rg / fd / perl / pandoc / verible
#   - 克隆配置到 ~/.config/nvim
#   - headless 安装插件 (Lazy) + mason 工具 + treesitter 解析器
#   - 校验并输出结果
#
set -euo pipefail

CONFIG_REPO="https://github.com/lwflwf1/nvim-config.git"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
PROXY="${1:-}"
if [ -n "$PROXY" ]; then
    export http_proxy="$PROXY" https_proxy="$PROXY"
fi

# ---------------------------------------------------------------- 基础工具
log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ⚠ %s\033[0m\n' "$*"; }

confirm() { # $1=提示  $2=默认(y/N)
    local d="${2:-n}"
    read -r -p "$1" ans
    case "${ans:-$d}" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

# 交互式工具检查: ask_tool <name> <install命令>
# 找到 → 跳过; 未找到 → 询问是否已手动安装 → 否则执行 install命令
ask_tool() {
    local name="$1" install_fn="$2"
    if command -v "$name" >/dev/null 2>&1; then
        ok "$name ($(command -v "$name"))"
        return 0
    fi
    warn "$name 未找到"
    if confirm "  $name 是否已手动安装? [y/N] "; then
        if command -v "$name" >/dev/null 2>&1; then ok "$name 确认可用"; return 0; fi
        warn "$name 仍未找到, 跳过"
        return 1
    fi
    echo "  自动安装 $name ..."
    eval "$install_fn"
    if command -v "$name" >/dev/null 2>&1; then ok "$name 安装完成"; return 0; fi
    warn "$name 安装失败或不在 PATH, 跳过"
    return 1
}

# ---------------------------------------------------------------- OS 检测
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
    Darwin)
        PLATFORM="macos"
        if ! command -v brew >/dev/null 2>&1; then
            err "需要 Homebrew, 请先安装: https://brew.sh"; exit 1
        fi
        ;;
    Linux)
        PLATFORM="linux"
        if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
            log "检测到 WSL ($WSL_DISTRO_NAME)"
        fi
        if command -v apk >/dev/null 2>&1; then PKG=apk
        elif command -v apt-get >/dev/null 2>&1; then PKG=apt
        elif command -v dnf >/dev/null 2>&1; then PKG=dnf
        elif command -v yum >/dev/null 2>&1; then PKG=yum
        else PKG=none; fi
        log "Linux 发行版包管理器: $PKG"
        ;;
    *) err "不支持的系统: $OS (仅支持 macOS/Linux)"; exit 1;;
esac

log "平台: $PLATFORM / $ARCH"

# ---------------------------------------------------------------- 包管理器辅助
pkg_install() { # pkg_install pkg1 pkg2 ...
    case "$PLATFORM:$PKG" in
        macos:*)  brew install "$@" ;;
        linux:apk) sudo apk add --no-cache "$@" ;;
        linux:apt) sudo apt-get update -qq && sudo apt-get install -y "$@" ;;
        linux:dnf) sudo dnf install -y "$@" ;;
        linux:yum) sudo yum install -y "$@" ;;
        *) err "无法自动安装: $*"; return 1;;
    esac
}

# ---------------------------------------------------------------- 必需工具
log "== 检查必需工具 =="
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

# ---------------------------------------------------------------- 可选工具
log "== 可选工具 (按需确认) =="
if confirm "安装 rust 工具链 (rustup, 提供 rust-analyzer/rustfmt)? [y/N] "; then
    ask_tool rustup 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
    if command -v rustup >/dev/null 2>&1; then
        rustup component add rust-analyzer rustfmt 2>/dev/null || true
        ok "rust 工具链就绪"
    fi
fi
if confirm "安装 fzf / rg / fd (fzf-lua 搜索)? [y/N] "; then
    ask_tool fzf "pkg_install fzf"
    ask_tool rg  "pkg_install ripgrep"
    ask_tool fd  "pkg_install fd-find"
fi
if confirm "安装 perl + perltidy (perl LSP)? [y/N] "; then
    if [ "$PLATFORM" = macos ]; then ask_tool perl "brew install perl perltidy"
    elif [ "$PKG" = apt ]; then ask_tool perl "pkg_install perl libperl-dev perltidy"
    elif [ "$PKG" = apk ]; then ask_tool perl "pkg_install perl perl-tidy"
    else ask_tool perl "pkg_install perl"; fi
fi
if confirm "安装 pandoc + xelatex (orgmode 导出)? [y/N] "; then
    ask_tool pandoc "pkg_install pandoc"
    ask_tool xelatex "pkg_install texlive-xetex"
fi

# ---------------------------------------------------------------- Neovim
log "== 安装 Neovim =="
if command -v nvim >/dev/null 2>&1; then
    ok "nvim $(nvim --version | head -1)"
    if [ "$(nvim --version | grep -oE 'v?0\.1[12]\.[0-9]+' | head -1)" = "" ]; then
        warn "nvim 版本可能过旧 (配置需要 >= 0.11, 建议 0.12)"
    fi
else
    if [ "$PLATFORM" = macos ]; then
        brew install neovim
    else
        # 下载官方最新 release tarball
        latest="$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep -oE '"tag_name": *"v[^"]+"' | head -1 | grep -oE 'v[0-9.]+' || true)"
        [ -z "$latest" ] && latest="v0.12.4"
        url="https://github.com/neovim/neovim/releases/download/${latest}/nvim-linux-${ARCH}.tar.gz"
        log "下载 $url"
        curl -fL "$url" -o /tmp/nvim.tar.gz
        sudo tar xzf /tmp/nvim.tar.gz -C /usr/local --strip-components=1
        ok "nvim ${latest} 安装完成"
    fi
fi

# ---------------------------------------------------------------- 配置
log "== 克隆配置 =="
if [ -f "$CONFIG_DIR/init.lua" ]; then
    log "$CONFIG_DIR 已存在, 跳过克隆 (如需重新安装请先删除)"
else
    git clone --depth 1 "$CONFIG_REPO" "$CONFIG_DIR"
    ok "配置已克隆到 $CONFIG_DIR"
fi

# ---------------------------------------------------------------- 安装插件/工具/解析器
cd "$CONFIG_DIR"
log "== 安装插件 (Lazy) =="
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
nvim --headless "+Lazy! sync" +qa || { err "插件安装失败, 请检查网络/代理"; exit 1; }
ok "插件安装完成"

log "== 安装 mason 工具 + treesitter 解析器 (ToolInstall) =="
nvim --headless +ToolInstall +"sleep 120" +qa || { err "ToolInstall 失败"; exit 1; }
ok "mason 工具 + 解析器安装完成"

# ---------------------------------------------------------------- 校验
log "== 校验 =="
plugins=$(ls "$DATA_DIR/lazy" 2>/dev/null | wc -l | tr -d ' ')
parsers=$(find "$DATA_DIR/site/parser" -name '*.so' 2>/dev/null | wc -l | tr -d ' ')
mason=$(ls "$DATA_DIR/mason/packages" 2>/dev/null | wc -l | tr -d ' ')
if nvim --headless +qa 2>/tmp/nvim-install-verify.log && ! grep -qE 'E5113|Error' /tmp/nvim-install-verify.log; then
    ok "启动验证通过"
else
    warn "启动验证有报错, 查看 /tmp/nvim-install-verify.log"
fi
echo
log "安装完成: 插件=$plugins  解析器=$parsers  mason工具=$mason"
log "运行 nvim 即可使用。"