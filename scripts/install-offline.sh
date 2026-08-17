#!/usr/bin/env bash
#
# nvim-config 离线安装脚本 (仅 Linux / 内网, 无需网络)
#
# 用法:
#   ./install-offline.sh <nvim-bundle-linux-x86_64-*.tar.gz> [--no-interactive]
#
# 行为:
#   - 解压 bundle (config / data / nvim / parser-sources / tools / lazy-lock)
#   - 交互式确认外部工具: 已装则跳过, 否则从 tools/ 缓存或系统包安装
#   - 安装 neovim (bundle 内老 glibc 构建, 支持 RHEL6/glibc2.17)
#   - 还原配置与数据目录
#   - 用 gcc 直接编译 treesitter 解析器 -> ~/.local/share/nvim/site/parser/ (无需 tree-sitter CLI)
#   - 校验
#
set -euo

BUNDLE="${1:-}"
NO_INTERACTIVE="${2:-}"
[ -n "$BUNDLE" ] || { echo "用法: $0 <bundle.tar.gz> [--no-interactive]"; exit 1; }
[ -f "$BUNDLE" ] || { echo "bundle 不存在: $BUNDLE"; exit 1; }

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
PARSER_DIR="$DATA_DIR/site/parser"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log()  { printf '\033[1;34m[offline]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ⚠ %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
    [ -n "$NO_INTERACTIVE" ] && return 1
    local d="${2:-n}"
    read -r -p "$1" ans
    case "${ans:-$d}" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

need() { # need <name> [安装命令] [描述]
    local name="$1" inst="$2" desc="${3:-}"
    if command -v "$name" >/dev/null 2>&1; then ok "$name ($(command -v "$name"))"; return 0; fi
    warn "$name 未找到${desc:+ ($desc)}"
    if confirm "  $name 是否已手动安装? [y/N] "; then
        command -v "$name" >/dev/null 2>&1 && { ok "$name 确认可用"; return 0; }
        warn "$name 仍未找到"; return 1
    fi
    if [ -n "$inst" ]; then
        echo "  安装 $name ..."
        eval "$inst" && command -v "$name" >/dev/null 2>&1 && { ok "$name 安装完成"; return 0; }
    fi
    warn "$name 未安装 (跳过)"
    return 1
}

# ---------------------------------------------------------------- 解压
log "== 解压 bundle =="
tar xzf "$BUNDLE" -C "$TMP"
ls "$TMP" | tr '\n' ' '; echo
[ -d "$TMP/data" ] || err "bundle 缺少 data/ 目录"

# ---------------------------------------------------------------- 外部工具
log "== 外部工具确认 =="
# 工具缓存安装函数
install_from_cache() { # install_from_cache <tools/*.tar.gz> <二进制名>
    local cache="$TMP/tools/$1" name="$2"
    [ -f "$cache" ] || return 1
    mkdir -p "$HOME/local/bin"
    case "$cache" in
        *.gz) tar xzf "$cache" -C "$HOME/local" 2>/dev/null || gunzip -c "$cache" > "$HOME/local/bin/$name";;
    esac
    find "$HOME/local" -name "$name" -type f -exec chmod +x {} \; 2>/dev/null || true
    export PATH="$HOME/local/bin:$PATH"
    command -v "$name" >/dev/null 2>&1
}

need git   "" "lazy 插件仓库操作需要"
need gcc   "" "编译 treesitter 解析器必需"
need make  "" "编译辅助"
need node  "install_from_cache node.tar.gz node 2>/dev/null || true" "mason 的 npm 包 (bash/json/yaml-lsp, prettier)"
need python3 "" "pyrefly 需要"

# gcc 版本检查 (解析器需要 C11, gcc >= 5 建议, 7.x 最佳)
CC_BIN="${CC:-gcc}"
GCC_VER="$("$CC_BIN" -dumpversion 2>/dev/null || echo 0)"
if [ "$(printf '%s\n4.9' "$GCC_VER" | sort -V | head -1)" != "4.9" ]; then
    # 尝试 devtoolset (RHEL6 SCL 提供 gcc 7)
    for ds in /opt/rh/devtoolset-*/root/usr/bin/gcc; do
        [ -x "$ds" ] || continue
        CC_BIN="$ds"; GCC_VER="$("$CC_BIN" -dumpversion)"; break
    done
fi
GCC_VER="$("$CC_BIN" -dumpversion 2>/dev/null || echo 0)"
log "使用 C 编译器: $CC_BIN ($GCC_VER)"
if [ "$(printf '%s\n4.9' "$GCC_VER" | sort -V | head -1)" != "4.9" ]; then
    warn "gcc 版本过旧 ($GCC_VER < 4.9), 现代解析器需要 C11, 编译可能失败"
    warn "RHEL6 建议: scl enable devtoolset-7 bash 后重试, 或设置 CC=/opt/rh/devtoolset-7/root/usr/bin/gcc"
fi
CXX_BIN="${CXX:-$(dirname "$CC_BIN")/g++}"

if confirm "安装 fzf / rg / fd (fzf-lua 搜索)? [y/N] "; then
    need fzf "install_from_cache fzf.tar.gz fzf"
    need rg  "install_from_cache rg.tar.gz rg"
    need fd  "install_from_cache fd.tar.gz fd"
fi
if confirm "安装 rust 工具链 (rustup, rust-analyzer)? [y/N] "; then
    need rustup "" "需内网镜像或手动安装"
fi
if confirm "安装 perl + perltidy (perl LSP)? [y/N] "; then
    need perl "" "需内网镜像或手动安装"
fi
if confirm "安装 pandoc (orgmode 导出)? [y/N] "; then
    need pandoc "install_from_cache pandoc.tar.gz pandoc"
fi

# ---------------------------------------------------------------- nvim
log "== 安装 Neovim =="
if command -v nvim >/dev/null 2>&1; then
    ok "nvim 已存在: $(nvim --version | head -1)"
else
    mkdir -p "$HOME/local"
    tar xzf "$TMP/nvim/nvim-linux-x86_64.tar.gz" -C "$HOME/local"
    mv "$HOME/local/nvim-linux-x86_64" "$HOME/local/nvim" 2>/dev/null || true
    export PATH="$HOME/local/nvim/bin:$PATH"
    command -v nvim >/dev/null 2>&1 || err "nvim 安装失败"
    ok "nvim 安装到 $HOME/local/nvim ($(nvim --version | head -1))"
fi
case ":$PATH:" in *":$HOME/local/nvim/bin:"*) ;; *) export PATH="$HOME/local/nvim/bin:$PATH";; esac

# ---------------------------------------------------------------- 配置与数据
log "== 还原配置与数据 =="
if [ -d "$CONFIG_DIR" ] && confirm "配置目录 $CONFIG_DIR 已存在, 备份并覆盖? [y/N] " y; then
    mv "$CONFIG_DIR" "$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"; ok "旧配置已备份"
fi
if [ -d "$DATA_DIR" ] && confirm "数据目录 $DATA_DIR 已存在, 备份并覆盖? [y/N] " y; then
    mv "$DATA_DIR" "$DATA_DIR.bak.$(date +%Y%m%d%H%M%S)"; ok "旧数据已备份"
fi
mkdir -p "$(dirname "$CONFIG_DIR")" "$(dirname "$DATA_DIR")"
cp -a "$TMP/config" "$CONFIG_DIR"
cp -a "$TMP/data" "$DATA_DIR"
rm -rf "$DATA_DIR/backup" "$DATA_DIR/undo" "$DATA_DIR/swap" "$DATA_DIR/view" 2>/dev/null || true
mkdir -p "$DATA_DIR/backup" "$DATA_DIR/undo" "$DATA_DIR/swap" "$DATA_DIR/view" "$PARSER_DIR"
ok "配置 -> $CONFIG_DIR  数据 -> $DATA_DIR"

# ---------------------------------------------------------------- 编译解析器
log "== 编译 treesitter 解析器 (gcc 直接编译) =="
parse_ok=0; parse_fail=0
for tgz in "$TMP/parser-sources/"*.tar.gz; do
    [ -f "$tgz" ] || continue
    lang="$(basename "$tgz" .tar.gz)"
    work="$TMP/pbuild"; rm -rf "$work"; mkdir -p "$work"
    if ! tar xzf "$tgz" -C "$work" 2>/dev/null; then warn "  $lang 解压失败"; continue; fi
    # 定位源码目录: 兼容有无顶层目录两种 tar 结构
    dir="$work"
    if [ ! -d "$dir/src" ]; then
        d="$(find "$work" -mindepth 2 -maxdepth 3 -name src -type d | head -1)"
        [ -n "$d" ] && dir="$(dirname "$d")"
    fi
    src="$dir/src"
    if [ ! -f "$src/parser.c" ]; then warn "  $lang 缺少 src/parser.c, 跳过"; parse_fail=$((parse_fail+1)); continue; fi
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
    if [ -f "$out" ]; then ok "  $lang 编译成功"; parse_ok=$((parse_ok+1)); else warn "  $lang 编译失败"; parse_fail=$((parse_fail+1)); fi
done
log "解析器编译完成: 成功=$parse_ok  失败=$parse_fail"

# ---------------------------------------------------------------- PATH
log "== 配置 PATH =="
export PATH="$HOME/local/nvim/bin:$HOME/local/bin:$PATH"
# mason 二进制 (lsp/formatter) 加入 PATH
export PATH="$DATA_DIR/mason/bin:$PATH"
grep -q "$HOME/local" "$HOME/.bashrc" 2>/dev/null || cat >> "$HOME/.bashrc" <<EOF
# nvim-config (offline install)
export PATH="$HOME/local/nvim/bin:$HOME/local/bin:$DATA_DIR/mason/bin:\$PATH"
EOF
ok "PATH 已写入 ~/.bashrc"

# ---------------------------------------------------------------- 校验
log "== 校验 =="
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
plugins=$(ls "$DATA_DIR/lazy" 2>/dev/null | wc -l | tr -d ' ') || true
parsers=$(ls "$PARSER_DIR"/*.so 2>/dev/null | wc -l | tr -d ' ') || true
mason=$(ls "$DATA_DIR/mason/packages" 2>/dev/null | wc -l | tr -d ' ') || true
if nvim --headless +qa 2>/tmp/nvim-offline-verify.log && ! grep -qE 'E5113|Error' /tmp/nvim-offline-verify.log; then
    ok "启动验证通过"
else
    warn "启动验证有报错, 查看 /tmp/nvim-offline-verify.log"
    grep -aE 'E5113|Error' /tmp/nvim-offline-verify.log | head -3
fi
echo
log "安装完成: 插件=$plugins  解析器=$parsers  mason工具=$mason"
log "请执行: source ~/.bashrc; nvim"
warn "若 mason 的 pyrefly (python venv) 不可用, 可在联网后运行: nvim --headless +MasonInstall pyrefly +qa"