<#
.nvim-config packaging script (PowerShell port of package.sh)
Usage:
  powershell -ExecutionPolicy Bypass -File package.ps1 [-Out DIR] [-NvimVersion v0.12.4] [-Proxy http://host:port]

Every download group is confirmed interactively (default answer: download).
Piped answers are honored; a closed stdin (CI/background) auto-accepts.

NOTE: the produced bundle targets LINUX x86_64 offline machines (the nvim
old-glibc build and all tool caches are the linux assets). data/ (lazy plugins,
mason tools, site) is copied as-is from the LOCAL nvim install, so for a fully
consistent Linux bundle run this on the Linux/WSL online machine; on Windows
the mason/site contents reflect the local platform.

Output: <out>/nvim-bundle-linux-x86_64-<date>.tar.gz
  config/            config directory
  data/              nvim data directory (lazy plugins / mason tools / site)
  nvim/              neovim binary (old-glibc build from neovim-releases, supports RHEL6/glibc2.17)
  parser-sources/    treesitter parser sources (incl. perl with pre-generated parser.c, systemverilog fork)
  tools/             optional external tool binary cache (selected interactively)
  lazy-lock.json
  manifest.txt
#>
[CmdletBinding()]
param(
    [string]$Out = "",
    [string]$NvimVersion = "",
    [string]$Proxy = ""
)

$ErrorActionPreference = "Stop"
$script:ConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "nvim" } else { Join-Path $env:LOCALAPPDATA "nvim" }
$script:DataDir   = if ($env:XDG_DATA_HOME)   { Join-Path $env:XDG_DATA_HOME "nvim" }   else { Join-Path $env:LOCALAPPDATA "nvim-data" }
if (-not $Out) { $Out = (Get-Location).Path }

if ($Proxy) { $env:http_proxy = $Proxy; $env:https_proxy = $Proxy }

function Log  { Write-Host "[package] $args" -ForegroundColor Cyan }
function Ok   { Write-Host "  [OK] $args" -ForegroundColor Green }
function Warn { Write-Host "  [!] $args" -ForegroundColor Yellow }
function Err  { Write-Host "[error] $args" -ForegroundColor Red; exit 1 }
trap { Write-Host "[error] $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    Err "tar.exe not found (Windows 10 1803+ ships it) - install bsdtar/libarchive and re-run"
}

# Interactive download confirmation. Default answer is YES (download).
# Piped answers are honored; closed stdin (CI/background) falls back to YES.
function Confirm-Download([string]$Prompt) {
    try {
        Write-Host -NoNewline $Prompt
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { return $true }                    # closed stdin
        if ([string]::IsNullOrWhiteSpace($line)) { return $true } # empty -> default YES
        return ($line -match '^[yY]')
    } catch { return $true }
}

# Proxy-aware web helpers (same pattern as install.ps1): WinINET cmdlets
# ignore the env proxy, so use the -Proxy parameter explicitly.
function Get-Page($url, [switch]$NoProxy) {
    try {
        if ($NoProxy) {
            $oldH = $env:http_proxy; $oldS = $env:https_proxy
            $env:http_proxy = ""; $env:https_proxy = ""
        }
        try {
            if ($Proxy -and -not $NoProxy) { return (Invoke-WebRequest -UseBasicParsing -Proxy $Proxy -Uri $url -TimeoutSec 30).Content }
            return (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 30).Content
        }
        finally {
            if ($NoProxy) { $env:http_proxy = $oldH; $env:https_proxy = $oldS }
        }
    }
    catch { return "" }
}
function Get-Json($url, [switch]$NoProxy) {
    try {
        if ($NoProxy) {
            $oldH = $env:http_proxy; $oldS = $env:https_proxy
            $env:http_proxy = ""; $env:https_proxy = ""
        }
        try {
            if ($Proxy -and -not $NoProxy) { return Invoke-RestMethod -Proxy $Proxy -Uri $url -TimeoutSec 30 }
            return Invoke-RestMethod -Uri $url -TimeoutSec 30
        }
        finally {
            if ($NoProxy) { $env:http_proxy = $oldH; $env:https_proxy = $oldS }
        }
    }
    catch { return $null }
}

# curl.exe (built into Win10+) for downloads: faster and proxy-aware
function Download($url, $out) {
    Log "Downloading $url"
    & curl.exe -fL --retry 3 --connect-timeout 20 --max-time 600 -o $out $url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { Err "Download failed: $url" }
}

function Resolve-LatestReleaseUrl($owner, $repo, $assetPattern) {
    $release = Get-Json "https://api.github.com/repos/$owner/$repo/releases/latest"
    if (-not $release) { return $null }
    $asset = $release.assets | Where-Object { $_.name -like $assetPattern } | Select-Object -First 1
    if (-not $asset) { return $null }
    return $asset.browser_download_url
}

function Get-FileSizeMB($path) {
    $len = (Get-Item $path).Length
    return ("{0:N1}MB" -f ($len / 1MB))
}

# Resolve the latest release from neovim/neovim-releases (its old-glibc builds
# track the main neovim repo). -NvimVersion overrides for pinning.
function Get-NvimVersion {
    if ($NvimVersion) { return $NvimVersion }
    $rel = Get-Json "https://api.github.com/repos/neovim/neovim-releases/releases/latest"
    if ($rel -and $rel.tag_name -match '^v') { return $rel.tag_name }
    return "v0.12.4"
}

$script:ManifestPath = ""
function Manifest([string]$line) {
    Add-Content -Path $script:ManifestPath -Value $line -Encoding ascii
}

# ---------------------------------------------------------------- Bundle root
$BundleRoot = Join-Path $Out ".bundle-tmp"
if (Test-Path $BundleRoot) { Remove-Item -Recurse -Force $BundleRoot }
New-Item -ItemType Directory -Force -Path $BundleRoot | Out-Null
$ToolsDir = Join-Path $BundleRoot "tools"
$ParserSrcDir = Join-Path $BundleRoot "parser-sources"
New-Item -ItemType Directory -Force -Path $ToolsDir, $ParserSrcDir | Out-Null
$script:ManifestPath = Join-Path $BundleRoot "manifest.txt"
Set-Content -Path $script:ManifestPath -Value "format=2" -Encoding ascii

# ---------------------------------------------------------------- Preflight checks
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    $nvimOut = nvim --version 2>&1 | Select-Object -First 1
    if ($LASTEXITCODE -eq 0) { Log "local nvim: $nvimOut (bundle carries its own old-glibc build)" }
    else { Err "nvim present but not runnable, run install.ps1 first" }
} else {
    Err "nvim not found, run install.ps1 first"
}
if (-not (Get-Command tree-sitter -ErrorAction SilentlyContinue)) {
    Err "tree-sitter CLI missing (needed to pre-generate the perl parser), install it first"
}
$null = tree-sitter --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Err "tree-sitter present but not runnable, install it first"
}
if (-not (Test-Path (Join-Path $script:ConfigDir "init.lua"))) {
    Err "Config directory not found: $script:ConfigDir"
}
if (-not (Test-Path (Join-Path $script:DataDir "lazy"))) {
    Err "Plugins not installed, run install.ps1 first"
}
Log "Packaging sources: config=$script:ConfigDir  data=$script:DataDir"

# ---------------------------------------------------------------- config + data
Log "== Copying config and data =="
$cfgCopy = Join-Path $BundleRoot "config"
Copy-Item -Recurse -Force $script:ConfigDir $cfgCopy
Remove-Item -Recurse -Force (Join-Path $cfgCopy ".git") -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $cfgCopy "lazy-lock.json") -ErrorAction SilentlyContinue
$dataCopy = Join-Path $BundleRoot "data"
Copy-Item -Recurse -Force $script:DataDir $dataCopy
foreach ($sub in @("backup","undo","swap","view","shada")) {
    Remove-Item -Recurse -Force (Join-Path $dataCopy $sub) -ErrorAction SilentlyContinue
}
Ok "config + data copied"
# Record the tool counts for the offline installer's verification thresholds
$masonCount = (Get-ChildItem (Join-Path $script:DataDir "mason\packages") -Force -ErrorAction SilentlyContinue).Count
Manifest "mason=$masonCount"

# ---------------------------------------------------------------- nvim binary
Log "== Neovim binary (old-glibc build) =="
$nvimVer = Get-NvimVersion
if (Confirm-Download "Download and bundle neovim $nvimVer (old-glibc build for offline machines)? [Y/n] ") {
    $nvimDir = Join-Path $BundleRoot "nvim"
    New-Item -ItemType Directory -Force -Path $nvimDir | Out-Null
    # neovim/neovim-releases provides prebuilt binaries that run on old glibc (2.17)
    $nvimUrl = "https://github.com/neovim/neovim-releases/releases/download/$nvimVer/nvim-linux-x86_64.tar.gz"
    $nvimTgz = Join-Path $nvimDir "nvim-linux-x86_64.tar.gz"
    Download $nvimUrl $nvimTgz
    Ok "nvim $nvimVer downloaded ($(Get-FileSizeMB $nvimTgz))"
    Manifest "nvim=$nvimVer url=$nvimUrl"
} else {
    Warn "nvim binary skipped - offline machines keep their existing nvim"
}

# ---------------------------------------------------------------- Parser sources
Log "== Treesitter parser sources (pinned revisions) =="
$parsersLuaPath = Join-Path $script:DataDir "lazy\nvim-treesitter\lua\nvim-treesitter\parsers.lua"
if (-not (Test-Path $parsersLuaPath)) { Err "nvim-treesitter not found: $parsersLuaPath" }
$script:parsersLua = Get-Content $parsersLuaPath -Raw
$cfgParsers = Get-Content (Join-Path $script:ConfigDir "lua\config\parsers.lua") -Raw
$langs = @([regex]::Matches($cfgParsers, '"([a-z_]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
if ($langs.Count -eq 0) { Err "Failed to read config.parsers" }
Log "$($langs.Count) parsers: $($langs -join ' ')"

# Extract url/revision/generate-flag for one language from nvim-treesitter's parsers.lua
function Get-ParserField([string]$lang, [string]$field) {
    $m = [regex]::Match($script:parsersLua, "(?ms)^  $([regex]::Escape($lang)) = \{.*?^  \},")
    if (-not $m.Success) { return "" }
    $f = [regex]::Match($m.Value, "(?m)^\s*$([regex]::Escape($field)) = '([^']*)'")
    if ($f.Success) { return $f.Groups[1].Value }
    return ""
}
function Test-ParserGenerate([string]$lang) {
    $m = [regex]::Match($script:parsersLua, "(?ms)^  $([regex]::Escape($lang)) = \{.*?^  \},")
    if (-not $m.Success) { return $false }
    return ($m.Value -match 'generate = true')
}

# Download source at a given revision -> output to $out, prefer codeload
# tarball, fall back to git
function Fetch-Source($out, $owner, $repo, $rev) {
    $url = "https://codeload.github.com/$owner/$repo/tar.gz/$rev"
    & curl.exe -fsL --retry 1 --max-time 90 -o $out $url 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $out)) {
        & tar.exe tzf $out *> $null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    Warn "  codeload download failed ($repo), falling back to git ..."
    $gdir = Join-Path $BundleRoot "_git_$repo"
    if (Test-Path $gdir) { Remove-Item -Recurse -Force $gdir }
    New-Item -ItemType Directory -Force -Path $gdir | Out-Null
    $ok = $false
    Push-Location $gdir
    try {
        & git.exe init -q
        & git.exe remote add origin "https://github.com/$owner/$repo.git"
        & git.exe fetch -q --depth 1 origin $rev
        if ($LASTEXITCODE -eq 0) { & git.exe checkout -q FETCH_HEAD }
        $ok = ($LASTEXITCODE -eq 0)
    } finally { Pop-Location }
    if (-not $ok) {
        Remove-Item -Recurse -Force $gdir -ErrorAction SilentlyContinue
        return $false
    }
    & tar.exe czf $out -C (Split-Path $gdir) (Split-Path $gdir -Leaf)
    Remove-Item -Recurse -Force $gdir
    return $true
}

if (Confirm-Download "Download sources for $($langs.Count) treesitter parsers (needed to compile new parsers offline)? [Y/n] ") {
    $genFailed = @()
    foreach ($lang in $langs) {
        if ($lang -eq "systemverilog") {
            # Config overrides to a personal fork (treesitter.lua)
            $url = "https://github.com/lwflwf1/tree-sitter-systemverilog"
            Log "  $lang -> fork $url (master HEAD)"
            $svDir = Join-Path $BundleRoot "_sv"
            if (Test-Path $svDir) { Remove-Item -Recurse -Force $svDir }
            & git.exe clone --depth 1 $url $svDir *> $null
            if ($LASTEXITCODE -ne 0) { Warn "  $lang clone failed, skipping"; continue }
            $rev = (git.exe -C $svDir rev-parse HEAD).Trim()
            # Move-Item with an absolute target (Rename-Item's -NewName is
            # relative to the CWD; bsdtar's --transform is absent on old
            # Windows tar.exe, so rename the directory instead)
            $renamed = Join-Path $BundleRoot "tree-sitter-systemverilog"
            Remove-Item -Recurse -Force $renamed -ErrorAction SilentlyContinue
            Move-Item $svDir $renamed
            & tar.exe czf (Join-Path $ParserSrcDir "$lang.tar.gz") -C $BundleRoot "tree-sitter-systemverilog"
            Remove-Item -Recurse -Force $renamed -ErrorAction SilentlyContinue
        } else {
            $url = Get-ParserField $lang "url"
            $rev = Get-ParserField $lang "revision"
            if (-not $url -or -not $rev) {
                Warn "  Skipping $lang (no url/revision in parsers.lua)"
                continue
            }
            $tgz = Join-Path $ParserSrcDir "$lang.tar.gz"
            Log "  $lang  $url  @ $($rev.Substring(0, [Math]::Min(10, $rev.Length)))"
            # Extract owner/repo from the URL
            $m = [regex]::Match($url, '^https://github\.com/([^/]+)/([^/]+)')
            if (-not $m.Success) { Warn "  Cannot parse URL for $lang, skipping"; continue }
            $owner = $m.Groups[1].Value; $repo = $m.Groups[2].Value
            if (-not (Fetch-Source $tgz $owner $repo $rev)) {
                Warn "  Fetch failed, skipping $lang"; continue
            }
            # perl (generate = true) needs parser.c pre-generated so offline
            # machines can compile without the tree-sitter CLI. Fail loud.
            if (Test-ParserGenerate $lang) {
                Log "  $lang needs tree-sitter generate, pre-generating parser.c ..."
                $work = Join-Path $BundleRoot "_gen"
                if (Test-Path $work) { Remove-Item -Recurse -Force $work }
                New-Item -ItemType Directory -Force -Path $work | Out-Null
                & tar.exe xzf $tgz -C $work
                $dir = Get-ChildItem $work -Directory | Select-Object -First 1
                if ($dir) {
                    Push-Location $dir.FullName
                    try { & tree-sitter.exe generate *> $null; $genOk = ($LASTEXITCODE -eq 0) }
                    finally { Pop-Location }
                    if ($genOk) { Ok "  $lang parser.c generated" }
                    else { $genFailed += $lang; Warn "  generate failed for $lang (bundle will lack parser.c)" }
                    & tar.exe czf $tgz -C $work (Split-Path $dir.FullName -Leaf)
                } else {
                    $genFailed += $lang; Warn "  extraction of $lang failed"
                }
                Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
            }
        }
        Manifest "parser $lang $url $rev"
    }
    if ($genFailed.Count -gt 0) {
        Err "tree-sitter generate failed for: $($genFailed -join ' ') - fix the parser sources before packaging"
    }
    Remove-Item -Force (Join-Path $ParserSrcDir ".keep") -ErrorAction SilentlyContinue
    $psrcCount = (Get-ChildItem $ParserSrcDir -Filter *.tar.gz).Count
    Log "Parser source packages: $psrcCount"
} else {
    Warn "Parser sources skipped - offline machines keep their existing compiled parsers"
    $psrcCount = 0
}
Manifest "parsers=$psrcCount"

# ---------------------------------------------------------------- Optional tool cache
$Tools = @("rg","fd","fzf","tree-sitter-cli","node","pandoc")
Log "== External tool cache (options: $($Tools -join ' ')) =="
if (Confirm-Download "Process external tool cache for offline install? [Y/n] ") {
    foreach ($t in $Tools) {
        $hint = ""
        if (Get-Command $t -ErrorAction SilentlyContinue) { $hint = "  (local: present)" }
        if (-not (Confirm-Download "  Download and bundle $t?$hint [Y/n] ")) {
            Warn "  $t skipped"; continue
        }
        $url = $null; $outFile = ""
        switch ($t) {
            "rg" {
                $url = Resolve-LatestReleaseUrl "BurntSushi" "ripgrep" "*x86_64-unknown-linux-musl.tar.gz"
                $outFile = "rg.tar.gz"
            }
            "fd" {
                $url = Resolve-LatestReleaseUrl "sharkdp" "fd" "*x86_64-unknown-linux-musl.tar.gz"
                $outFile = "fd.tar.gz"
            }
            "fzf" {
                $url = Resolve-LatestReleaseUrl "junegunn" "fzf" "fzf-*-linux_amd64.tar.gz"
                $outFile = "fzf.tar.gz"
            }
            "tree-sitter-cli" {
                $url = Resolve-LatestReleaseUrl "tree-sitter" "tree-sitter" "tree-sitter-cli-linux-x64.*"
                $outFile = if ($url -like "*.gz") { "tree-sitter-cli.gz" } else { "tree-sitter-cli.zip" }
            }
            "node" {
                # node.tar.xz so offline machines can install npm tools without
                # their own copy (consumed by install-offline.sh)
                $listing = Get-Page "https://nodejs.org/dist/latest-v24.x/"
                $m = [regex]::Match($listing, 'node-v[0-9]+\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz')
                if ($m.Success) {
                    $url = "https://nodejs.org/dist/latest-v24.x/$($m.Value)"
                    $outFile = "node.tar.xz"
                }
            }
            "pandoc" {
                # pandoc.tar.gz consumed by install-offline.sh
                $release = Get-Json "https://api.github.com/repos/jgm/pandoc/releases/latest"
                if ($release -and $release.tag_name) {
                    $ver = ($release.tag_name -replace '^v','')
                    $url = "https://github.com/jgm/pandoc/releases/download/$ver/pandoc-$ver-linux-amd64.tar.gz"
                    $outFile = "pandoc.tar.gz"
                }
            }
        }
        if ($url -and $outFile) {
            Download $url (Join-Path $ToolsDir $outFile)
            Manifest "tool $t $url"
            Ok "$t cached"
        } else {
            Warn "$t download failed"
        }
    }
} else {
    Warn "External tool cache skipped"
}

# ---------------------------------------------------------------- npm tools cache (offline mason fallback)
Log "== npm tools cache (offline fallback for mason npm packages) =="
$NpmTools = @("yaml-language-server","json-lsp","bash-language-server","prettier","prettierd")
if (Confirm-Download "Bundle npm tools ($NpmTools)? [Y/n] ") {
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $np = Join-Path $BundleRoot "npmtools"
        New-Item -ItemType Directory -Force -Path $np | Out-Null
        Push-Location $np
        try {
            & npm.cmd install --no-audit --no-fund --loglevel=error $NpmTools *> $null
            $npmOk = ($LASTEXITCODE -eq 0) -and (Test-Path (Join-Path $np "node_modules"))
        } finally { Pop-Location }
        if ($npmOk) {
            $npmTgz = Join-Path $ToolsDir "npm-tools.tar.gz"
            & tar.exe czf $npmTgz -C $np node_modules
            $md5 = (Get-FileHash -Algorithm MD5 $npmTgz).Hash.ToLower()
            Manifest "npmtools=$md5"
            Ok "npm tools cached: $NpmTools"
        } else {
            Warn "npm install failed, npm-tools cache skipped (tools will need an online :MasonInstall)"
        }
        Remove-Item -Recurse -Force $np -ErrorAction SilentlyContinue
    } else {
        Warn "npm not found, npm-tools cache skipped"
    }
} else {
    Warn "npm tools cache skipped"
}

# ---------------------------------------------------------------- Packaging
Log "== Generating bundle =="
$lockSrc = Join-Path $script:ConfigDir "lazy-lock.json"
$lockDst = Join-Path $BundleRoot "lazy-lock.json"
if (Test-Path $lockSrc) {
    Copy-Item $lockSrc $lockDst -Force
    $lockMd5 = (Get-FileHash -Algorithm MD5 $lockDst).Hash.ToLower()
} else { $lockMd5 = "" }
Manifest "lazylock=$lockMd5"
$date = Get-Date -Format "yyyyMMdd"
$outFile = Join-Path $Out "nvim-bundle-linux-x86_64-$date.tar.gz"
& tar.exe czf $outFile -C $BundleRoot .
if ($LASTEXITCODE -ne 0) { Err "tar failed while creating the bundle" }
Remove-Item -Recurse -Force $BundleRoot
Write-Host "  $((Get-Item $outFile).Length / 1KB) KB -> $outFile" -ForegroundColor Cyan
Ok "Packaging done: $outFile"
Write-Host "Usage: copy $outFile to an intranet machine and run scripts/install-offline.sh <bundle-path> [--update]" -ForegroundColor Cyan