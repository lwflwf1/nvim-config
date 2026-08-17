#!/usr/bin/env bash
#
# nvim-config 打包脚本 (仅 Linux, 在有网/已安装好的机器上运行)
#
# 用法:
#   ./package.sh [--out DIR] [--with-tools "rg fd fzf"] [--nvim-version v0.12.4]
#
# 产出: <out>/nvim-bundle-linux-x86_64-<日期>.tar.gz
#   config/            配置目录
#   data/              nvim 数据目录 (lazy 插件 / mason 工具 / site)
#   nvim/              neovim 二进制 (neovim-releases 老 glibc 构建, 支持 RHEL6/glibc2.17)
#   parser-sources/    treesitter 解析器源码 (含 perl 已预生成 parser.c, systemverilog fork)
#   tools/             可选外部工具二进制缓存 (--with-tools 指定)
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
        *) echo "未知参数: $1"; exit 1;;
    esac
done

log()  { printf '\033[1;34m[package]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\033[1;33m  ⚠ %s\033[0m\n' "$*"; }

BUNDLE_ROOT="$OUT_DIR/.bundle-tmp"
rm -rf "$BUNDLE_ROOT"; mkdir -p "$BUNDLE_ROOT"
mkdir -p "$BUNDLE_ROOT/parser-sources" "$BUNDLE_ROOT/tools"
MANIFEST="$BUNDLE_ROOT/manifest.txt"
: > "$MANIFEST"

# ---------------------------------------------------------------- 前置校验
command -v nvim >/dev/null 2>&1 || err "未找到 nvim, 请先运行 install.sh"
command -v tree-sitter >/dev/null 2>&1 || err "未找到 tree-sitter CLI (perl 解析器需要预生成), 请先安装"
[ -f "$CONFIG_DIR/init.lua" ] || err "配置目录不存在: $CONFIG_DIR"
[ -d "$DATA_DIR/lazy" ] || err "插件未安装, 请先运行 install.sh"
log "打包源: config=$CONFIG_DIR  data=$DATA_DIR"

# ---------------------------------------------------------------- config + data
log "== 复制配置与数据 =="
cp -a "$CONFIG_DIR" "$BUNDLE_ROOT/config"
rm -rf "$BUNDLE_ROOT/config/.git" "$BUNDLE_ROOT/config/lazy-lock.json"
cp -a "$DATA_DIR" "$BUNDLE_ROOT/data"
rm -rf "$BUNDLE_ROOT/data/backup" "$BUNDLE_ROOT/data/undo" "$BUNDLE_ROOT/data/swap" \
       "$BUNDLE_ROOT/data/view" "$BUNDLE_ROOT/data/shada" 2>/dev/null || true
ok "config + data 已复制"

# ---------------------------------------------------------------- nvim 二进制
log "== 下载 Neovim (老 glibc 构建) =="
mkdir -p "$BUNDLE_ROOT/nvim"
# neovim/neovim-releases 提供可在旧 glibc (2.17) 上运行的预编译版
NVIM_URL="https://github.com/neovim/neovim-releases/releases/download/${NVIM_VER}/nvim-linux-x86_64.tar.gz"
curl -fL --retry 3 "$NVIM_URL" -o "$BUNDLE_ROOT/nvim/nvim-linux-x86_64.tar.gz"
ok "nvim ${NVIM_VER} 已下载 ($(du -h "$BUNDLE_ROOT/nvim/nvim-linux-x86_64.tar.gz" | cut -f1))"
echo "nvim=${NVIM_VER} url=${NVIM_URL}" >> "$MANIFEST"

# ---------------------------------------------------------------- 解析器源码
log "== 下载 treesitter 解析器源码 (按精确 revision) =="
PARSERS_LUA="$DATA_DIR/lazy/nvim-treesitter/lua/nvim-treesitter/parsers.lua"
[ -f "$PARSERS_LUA" ] || err "未找到 nvim-treesitter: $PARSERS_LUA"

# 读取 config.parsers 的语言列表 (兼容老 bash, 不用 mapfile)
LANGS=()
while IFS= read -r line; do
    LANGS+=("$line")
done < <(grep -oE '"[a-z_]+"' "$CONFIG_DIR/lua/config/parsers.lua" | tr -d '"')
[ ${#LANGS[@]} -gt 0 ] || err "无法读取 config.parsers"
log "共 ${#LANGS[@]} 个解析器: ${LANGS[*]}"

get_url() { grep -A8 "^  $1 = {" "$PARSERS_LUA" | grep "url = " | head -1 | sed -E "s/.*url = '([^']*)'.*/\1/"; }
get_rev() { grep -A8 "^  $1 = {" "$PARSERS_LUA" | grep "revision = " | head -1 | sed -E "s/.*revision = '([^']*)'.*/\1/"; }
get_gen() { grep -A8 "^  $1 = {" "$PARSERS_LUA" | grep -c "generate = true" || true; }

# 下载某仓库某 revision 的源码 -> 输出到 $1, 优先 codeload tarball, 失败回退 git
fetch_source() { # fetch_source <out.tar.gz> <owner> <repo> <rev>
    local out="$1" owner="$2" repo="$3" rev="$4"
    if curl -fsL --retry 1 --max-time 90 -o "$out" "https://codeload.github.com/${owner}/${repo}/tar.gz/${rev}" \
        && tar tzf "$out" >/dev/null 2>&1; then
        return 0
    fi
    warn "  codeload 下载失败($repo), 回退 git ..."
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
        # 配置里覆盖为个人 fork (treesitter.lua)
        URL="https://github.com/lwflwf1/tree-sitter-systemverilog"
        log "  $lang -> fork $URL (master HEAD)"
        git clone --depth 1 "$URL" "$BUNDLE_ROOT/_sv" >/dev/null 2>&1
        REV="$(git -C "$BUNDLE_ROOT/_sv" rev-parse HEAD)"
        tar czf "$BUNDLE_ROOT/parser-sources/$lang.tar.gz" -C "$BUNDLE_ROOT" --transform 's/^_sv/tree-sitter-systemverilog/' _sv
        rm -rf "$BUNDLE_ROOT/_sv"
    else
        URL="$(get_url "$lang")"; REV="$(get_rev "$lang")"
        if [ -z "$URL" ] || [ -z "$REV" ]; then
            warn "  跳过 $lang (parsers.lua 中无 url/revision)"
            continue
        fi
        TGZ="$BUNDLE_ROOT/parser-sources/$lang.tar.gz"
        log "  $lang  ${URL}  @ ${REV:0:10}"
        # owner/repo 从 URL 提取
        OWNER="$(echo "$URL" | sed -E 's#https://github.com/([^/]+)/.*#\1#')"
        REPO="$(echo "$URL" | sed -E 's#https://github.com/[^/]+/([^/]+).*#\1#')"
        fetch_source "$TGZ" "$OWNER" "$REPO" "$REV" \
            || { warn "  获取失败, 跳过 $lang"; continue; }
        if [ "$(get_gen "$lang")" = yes ]; then
            log "  $lang 需要 tree-sitter generate, 预生成 parser.c ..."
            work="$BUNDLE_ROOT/_gen"; rm -rf "$work"; mkdir -p "$work"
            tar xzf "$TGZ" -C "$work"
            dir="$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -1)"
            ( cd "$dir" && tree-sitter generate >/dev/null 2>&1 ) || warn "  generate 失败, 跳过 $lang"
            tar czf "$TGZ" -C "$work" "$(basename "$dir")"
            rm -rf "$work"
        fi
    fi
    echo "parser $lang $URL $REV" >> "$MANIFEST"
done
rm -f "$BUNDLE_ROOT/parser-sources/.keep" 2>/dev/null || true
PSRC_COUNT="$(ls "$BUNDLE_ROOT/parser-sources" | grep -c '\.tar\.gz')"
log "解析器源码包: ${PSRC_COUNT} 个"
echo "parsers=${PSRC_COUNT}" >> "$MANIFEST"

# ---------------------------------------------------------------- 可选工具缓存
if [ -n "$WITH_TOOLS" ]; then
    log "== 下载外部工具缓存: $WITH_TOOLS =="
    for t in $WITH_TOOLS; do
        case "$t" in
            rg)
                url="$(curl -s https://api.github.com/repos/BurntSushi/ripgrep/releases/latest \
                       | grep -oE 'https://[^"]*x86_64-unknown-linux-musl\.tar\.gz' | head -1)"
                [ -n "$url" ] && { curl -fL "$url" -o "$BUNDLE_ROOT/tools/rg.tar.gz"; echo "tool rg $url" >> "$MANIFEST"; ok "rg 已缓存"; } || warn "rg 下载失败";;
            fd)
                url="$(curl -s https://api.github.com/repos/sharkdp/fd/releases/latest \
                       | grep -oE 'https://[^"]*x86_64-unknown-linux-musl\.tar\.gz' | head -1)"
                [ -n "$url" ] && { curl -fL "$url" -o "$BUNDLE_ROOT/tools/fd.tar.gz"; echo "tool fd $url" >> "$MANIFEST"; ok "fd 已缓存"; } || warn "fd 下载失败";;
            fzf)
                url="$(curl -s https://api.github.com/repos/junegunn/fzf/releases/latest \
                       | grep -oE 'https://[^"]*linux_amd64\.tar\.gz' | head -1)"
                [ -n "$url" ] && { curl -fL "$url" -o "$BUNDLE_ROOT/tools/fzf.tar.gz"; echo "tool fzf $url" >> "$MANIFEST"; ok "fzf 已缓存"; } || warn "fzf 下载失败";;
            tree-sitter-cli)
                url="https://github.com/tree-sitter/tree-sitter/releases/download/v0.26.12/tree-sitter-cli-linux-x64.gz"
                curl -fL "$url" -o "$BUNDLE_ROOT/tools/tree-sitter-cli.gz" || warn "tree-sitter-cli 下载失败"
                echo "tool tree-sitter-cli $url" >> "$MANIFEST"; ok "tree-sitter-cli 已缓存";;
            *) warn "未知工具: $t";;
        esac
    done
fi

# ---------------------------------------------------------------- 打包
log "== 生成 bundle =="
cp "$CONFIG_DIR/lazy-lock.json" "$BUNDLE_ROOT/lazy-lock.json" 2>/dev/null || true
DATE="$(date +%Y%m%d)"
OUT="$OUT_DIR/nvim-bundle-linux-x86_64-$DATE.tar.gz"
tar czf "$OUT" -C "$BUNDLE_ROOT" . 2>/dev/null
rm -rf "$BUNDLE_ROOT"
ls -lh "$OUT"
ok "打包完成: $OUT"
echo "使用方式: 将 $OUT 拷贝到内网机器, 运行 scripts/install-offline.sh <bundle路径>"