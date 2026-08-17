<#
.nvim-config 在线安装脚本 (Windows, 无包管理器依赖)
用法:
  powershell -ExecutionPolicy Bypass -File install.ps1 [-Proxy http://host:port]

行为:
  - 直接下载官方 zip/exe: neovim, git, mingw(gcc), node, win32yank, tree-sitter-cli, python
  - 交互式确认外部工具: 已安装则跳过
  - 配置 PATH (用户级)
  - 克隆配置到 %USERPROFILE%\AppData\Local\nvim
  - headless 安装插件 + mason 工具 + treesitter 解析器
#>
[CmdletBinding()]
param(
    [string]$Proxy = "",
    [string]$InstallDir = "$env:USERPROFILE\local"
)

$ErrorActionPreference = "Stop"
$CONFIG_REPO = "https://github.com/lwflwf1/nvim-config.git"
$CONFIG_DIR  = Join-Path $env:LOCALAPPDATA "nvim"
$DATA_DIR    = Join-Path $env:LOCALAPPDATA "nvim-data"
$BIN_DIR     = Join-Path $InstallDir "bin"
$NVIM_VER    = "v0.12.4"
$TSCLI_VER   = "v0.26.12"

if ($Proxy) { $env:http_proxy = $Proxy; $env:https_proxy = $Proxy }

function Log  { Write-Host "[install] $args" -ForegroundColor Cyan }
function Ok   { Write-Host "  [OK] $args" -ForegroundColor Green }
function Warn { Write-Host "  [!] $args" -ForegroundColor Yellow }
function Err  { Write-Host "[error] $args" -ForegroundColor Red; exit 1 }

# curl.exe (Win10+ 自带) 下载, 更快且支持代理
function Download($url, $out) {
    Log "下载 $url"
    & curl.exe -fL --retry 3 --connect-timeout 20 -o $out $url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { Err "下载失败: $url" }
    Ok "已下载 $out"
}

function Resolve-LatestReleaseUrl($owner, $repo, $assetPattern) {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -like $assetPattern } | Select-Object -First 1
    if (-not $asset) { return $null }
    return $asset.browser_download_url
}

function Confirm-Q($msg) {
    $ans = Read-Host $msg
    return ($ans -match '^[yY]')
}

function Need-Command($name, [scriptblock]$install, $hint = "") {
    if (Get-Command $name -ErrorAction SilentlyContinue) {
        Ok "$name 已存在: $((Get-Command $name).Source)"
        return
    }
    Warn "$name 未找到"
    if (Confirm-Q "  $name 是否已手动安装? [y/N]") {
        if (Get-Command $name -ErrorAction SilentlyContinue) { Ok "$name 确认可用"; return }
        Warn "$name 仍未找到, 跳过"
        return
    }
    Log "自动安装 $name ..."
    & $install
    if (Get-Command $name -ErrorAction SilentlyContinue) { Ok "$name 安装完成" }
    else { Warn "$name 安装失败或不在 PATH, 跳过" }
}

function Add-ToUserPath($dir) {
    if (-not (Test-Path $dir)) { return }
    $cur = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($cur -notlike "*$dir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$cur;$dir", "User")
        $env:PATH = "$env:PATH;$dir"
        Ok "PATH 已添加: $dir"
    }
}

New-Item -ItemType Directory -Force -Path $InstallDir, $BIN_DIR | Out-Null

# ================================================================ 必需工具
Log "== 检查必需工具 =="

# git
Need-Command git {
    $url = Resolve-LatestReleaseUrl "git-for-windows" "git" "Git-*-64-bit.exe"
    if (-not $url) { Err "无法解析 git-for-windows 下载地址" }
    $exe = Join-Path $env:TEMP "git-setup.exe"
    Download $url $exe
    Start-Process $exe -ArgumentList "/VERYSILENT","/NORESTART","/SP-" -Wait
    $env:Path = "$env:Path;$env:ProgramFiles\Git\cmd"
} "需要手动安装: https://git-scm.com/download/win"

# gcc (mingw-w64 winlibs)
Need-Command gcc {
    $url = Resolve-LatestReleaseUrl "brechtsanders" "winlibs_mingw" "winlibs-x86_64-*.zip"
    if (-not $url) { Warn "无法解析 winlibs 地址, 请手动安装 gcc (https://winlibs.com) 后重试"; return }
    $zip = Join-Path $env:TEMP "winlibs.zip"
    Download $url $zip
    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
    $mingwBin = Get-ChildItem "$InstallDir\mingw*" -Directory | Select-Object -First 1
    if (-not $mingwBin) { Warn "mingw 解压异常, 请手动安装 gcc"; return }
    Add-ToUserPath $mingwBin.FullName
} "需要手动安装: https://winlibs.com (mingw-w64, 含 gcc)"

# make (随 mingw 提供, 若无则提示)
if (-not (Get-Command make -ErrorAction SilentlyContinue)) {
    Warn "make 未找到 (gcc 安装时通常自带 make, 若后续解析器编译失败请确认)"
}

# node
Need-Command node {
    $nodeUrl = "https://nodejs.org/dist/latest/"
    $ver = (Invoke-RestMethod -Uri $nodeUrl).dist.index 2>$null
    if (-not $ver) {
        $listing = (Invoke-WebRequest -UseBasicParsing -Uri $nodeUrl).Content
        $m = [regex]::Match($listing, 'v(\d+)\.(\d+)\.(\d+)/"')
        if (-not $m.Success) { Warn "无法解析 node 版本, 请手动安装: https://nodejs.org"; return }
        $ver = "v$($m.Groups[1]).$($m.Groups[2]).$($m.Groups[3])"
    } else {
        $latest = $ver | Sort-Object { [version]$_.version.TrimStart('v') } -Descending | Select-Object -First 1
        $ver = $latest.version
    }
    $zip = Join-Path $env:TEMP "node.zip"
    Download "https://nodejs.org/dist/$ver/node-$ver-win-x64.zip" $zip
    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
    $nodeDir = Get-ChildItem "$InstallDir\node-*" -Directory | Select-Object -First 1
    Add-ToUserPath $nodeDir.FullName
} "需要手动安装: https://nodejs.org"

# python3 (pyrefly/mason venv 需要)
Need-Command python {
    $listing = (Invoke-WebRequest -UseBasicParsing -Uri "https://www.python.org/ftp/python/").Content
    $m = [regex]::Match($listing, '([0-9]+\.[0-9]+\.[0-9]+)')
    if (-not $m.Success) { Warn "无法解析 python 版本, 请手动安装: https://python.org"; return }
    $pv = $m.Groups[1].Value
    $exe = Join-Path $env:TEMP "python-setup.exe"
    Download "https://www.python.org/ftp/python/$pv/python-$pv-amd64.exe" $exe
    Start-Process $exe -ArgumentList "/quiet","InstallAllUsers=0","PrependPath=1" -Wait
} "需要手动安装: https://python.org"

# tree-sitter-cli (在线机编译解析器用)
Need-Command tree-sitter {
    $zip = Join-Path $env:TEMP "tscli.zip"
    Download "https://github.com/tree-sitter/tree-sitter/releases/download/$TSCLI_VER/tree-sitter-cli-windows-x64.zip" $zip
    Expand-Archive -Path $zip -DestinationPath $BIN_DIR -Force
    Add-ToUserPath $BIN_DIR
}

# win32yank (配置硬依赖: 剪贴板)
if (-not (Get-Command win32yank.exe -ErrorAction SilentlyContinue)) {
    Log "自动安装 win32yank (配置剪贴板依赖) ..."
    $url = Resolve-LatestReleaseUrl "equalsraf" "win32yank" "win32yank-x64.zip"
    if (-not $url) { Warn "无法解析 win32yank 地址, 请手动安装后加入 PATH"; }
    else {
        $zip = Join-Path $env:TEMP "win32yank.zip"
        Download $url $zip
        Expand-Archive -Path $zip -DestinationPath $BIN_DIR -Force
        Add-ToUserPath $BIN_DIR
        Ok "win32yank 安装完成"
    }
} else { Ok "win32yank 已存在" }

# ================================================================ 可选工具
Log "== 可选工具 (按需确认) =="
if (Confirm-Q "安装 rust 工具链 (rustup, rust-analyzer/rustfmt)? [y/N]") {
    $exe = Join-Path $env:TEMP "rustup-init.exe"
    Download "https://win.rustup.rs/x86_64" $exe
    Start-Process $exe -ArgumentList "-y","--default-toolchain","stable" -Wait
    rustup component add rust-analyzer rustfmt 2>$null
    Ok "rust 工具链就绪"
}
if (Confirm-Q "安装 fzf / rg / fd (fzf-lua 搜索)? [y/N]") {
    foreach ($tool in @(@("fzf","junegunn","fzf","fzf-*-windows_amd64.zip"),
                       @("rg","BurntSushi","ripgrep","ripgrep-*-x86_64-pc-windows-msvc.zip"),
                       @("fd","sharkdp","fd","fd-*-x86_64-pc-windows-msvc.zip"))) {
        $name = $tool[0]
        if (Get-Command $name -ErrorAction SilentlyContinue) { Ok "$name 已存在"; continue }
        $url = Resolve-LatestReleaseUrl $tool[1] $tool[2] $tool[3]
        if (-not $url) { Warn "无法解析 $name 下载地址, 跳过"; continue }
        $zip = Join-Path $env:TEMP "$name.zip"
        Download $url $zip
        Expand-Archive -Path $zip -DestinationPath $BIN_DIR -Force
        # 把子目录里的可执行文件提升到 BIN_DIR
        Get-ChildItem $BIN_DIR -Recurse -Filter "$name*.exe" | Move-Item -Destination $BIN_DIR -Force -ErrorAction SilentlyContinue
        Add-ToUserPath $BIN_DIR
        Ok "$name 安装完成"
    }
}
if (Confirm-Q "安装 perl + perltidy (perl LSP)? [y/N]") {
    Warn "Windows 请手动安装 Strawberry Perl: https://strawberryperl.com (含 perltidy), 并加入 PATH"
}
if (Confirm-Q "安装 pandoc (orgmode 导出)? [y/N]") {
    $url = Resolve-LatestReleaseUrl "jgm" "pandoc" "pandoc-*-windows-x86_64.zip"
    if (-not $url) { Warn "无法解析 pandoc 下载地址, 跳过" }
    else {
        $zip = Join-Path $env:TEMP "pandoc.zip"
        Download $url $zip
        Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
        $pd = Get-ChildItem "$InstallDir\pandoc-*" -Directory | Select-Object -First 1
        if ($pd) { Add-ToUserPath $pd.FullName }
    }
}

# ================================================================ Neovim
Log "== 安装 Neovim =="
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Ok "nvim 已存在: $((nvim --version | Select-Object -First 1))"
} else {
    $zip = Join-Path $env:TEMP "nvim-win64.zip"
    Download "https://github.com/neovim/neovim/releases/download/$NVIM_VER/nvim-win64.zip" $zip
    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
    $nvimBin = Join-Path $InstallDir "nvim-win64\bin"
    Add-ToUserPath $nvimBin
    Ok "nvim $NVIM_VER 安装完成"
}

# ================================================================ 配置
Log "== 克隆配置 =="
if (Test-Path (Join-Path $CONFIG_DIR "init.lua")) {
    Log "$CONFIG_DIR 已存在, 跳过克隆"
} else {
    git clone --depth 1 $CONFIG_REPO $CONFIG_DIR
    Ok "配置已克隆到 $CONFIG_DIR"
}

# ================================================================ 安装插件/工具/解析器
Set-Location $CONFIG_DIR
Log "== 安装插件 (Lazy) =="
$env:LANG = "en_US.UTF-8"; $env:LC_ALL = "en_US.UTF-8"
for ($attempt = 1; $attempt -le 3; $attempt++) {
    nvim --headless "+Lazy! sync" +qa
    if ($LASTEXITCODE -eq 0) { break }
    Warn "Lazy sync 失败 (第 $attempt 次), 清理 lazy.nvim 缓存后重试 ..."
    Remove-Item -Recurse -Force "$DATA_DIR\lazy\lazy.nvim" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    if ($attempt -eq 3) { Err "插件安装失败, 请检查网络/代理后重试" }
}
Ok "插件安装完成"

Log "== 安装 mason 工具 + treesitter 解析器 (ToolInstall) =="
$expectedParsers = 27
for ($attempt = 1; $attempt -le 3; $attempt++) {
    nvim --headless +ToolInstall +"sleep 300" +qa
    $parserCount = (Get-ChildItem "$DATA_DIR\site\parser\*.so" -ErrorAction SilentlyContinue).Count
    Write-Host "  解析器已就绪: $parserCount/$expectedParsers (第 $attempt 次)" -ForegroundColor Cyan
    if ($parserCount -ge $expectedParsers) { break }
    Start-Sleep -Seconds 3
    if ($attempt -eq 3) { Warn "解析器未完全安装 ($parserCount/$expectedParsers), 可稍后运行 :ToolInstall" }
}
Ok "mason 工具 + 解析器安装完成"

# ================================================================ 校验
Log "== 校验 =="
$plugins = (Get-ChildItem "$DATA_DIR\lazy" -Directory -ErrorAction SilentlyContinue).Count
$parsers = (Get-ChildItem "$DATA_DIR\site\parser\*.so" -ErrorAction SilentlyContinue).Count
$mason   = (Get-ChildItem "$DATA_DIR\mason\packages" -Directory -ErrorAction SilentlyContinue).Count
$masonBin = Join-Path $DATA_DIR "mason\bin"
Add-ToUserPath $masonBin
nvim --headless +qa 2>$null
Ok "启动验证完成"
Write-Host ""
Write-Host "[install] 完成: 插件=$plugins  解析器=$parsers  mason工具=$mason" -ForegroundColor Cyan
Write-Host "请重新打开终端使 PATH 生效, 然后运行 nvim"