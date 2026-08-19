<#
.nvim-config online installer (Windows, no package manager dependency)
Usage:
  powershell -ExecutionPolicy Bypass -File install.ps1 [-Proxy http://host:port]

Behavior:
  - Downloads official zip/exe directly: neovim, git, mingw(gcc), node, win32yank, tree-sitter-cli, python
  - Interactive confirmation for external tools: skip if already installed
  - Configures PATH (user level)
  - Clones config to %USERPROFILE%\AppData\Local\nvim
  - Headless install: plugins + mason tools + treesitter parsers
  - Verifies and reports results
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

# nvim on Windows prefers XDG_* env vars when set; clear them so CONFIG_DIR /
# DATA_DIR above always match the paths nvim actually reads (Bug J fix).
Remove-Item Env:XDG_CONFIG_HOME,Env:XDG_DATA_HOME,Env:XDG_CACHE_HOME -ErrorAction SilentlyContinue

if ($Proxy) { $env:http_proxy = $Proxy; $env:https_proxy = $Proxy }

function Log  { Write-Host "[install] $args" -ForegroundColor Cyan }
function Ok   { Write-Host "  [OK] $args" -ForegroundColor Green }
function Warn { Write-Host "  [!] $args" -ForegroundColor Yellow }
function Err  { Write-Host "[error] $args" -ForegroundColor Red; exit 1 }

# Report terminating errors with a clear exit instead of a bare stack trace.
trap { Write-Host "[error] $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

# Bug P fix (Windows side): install.ps1 installs Windows binaries; on WSL it
# must refuse to run — the two environments share the same filesystem and
# would corrupt each other. WSL users must run scripts/install.sh instead.
if ($env:WSL_DISTRO_NAME -or (Test-Path /proc/version -and (Select-String -Path /proc/version -Pattern "microsoft" -Quiet))) {
    Err "WSL detected - use scripts/install.sh instead; install.ps1 installs Windows binaries and would break the WSL environment"
}

# Proxy-aware web helpers (Bug D fix): WinINET-based cmdlets ignore the env proxy.
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
    Ok "Downloaded $out"
}

function Resolve-LatestReleaseUrl($owner, $repo, $assetPattern) {
    $release = Get-Json "https://api.github.com/repos/$owner/$repo/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -like $assetPattern } | Select-Object -First 1
    if (-not $asset) { return $null }
    return $asset.browser_download_url
}

function Confirm-Q($msg) {
    $ans = Read-Host $msg
    return ($ans -match '^[yY]')
}

# Bug T fix: presence on PATH is not enough - the binary must actually run.
# A non-executable Windows shim (WSL), a corrupt install, or a broken
# interpreter would pass a presence check and fail confusingly later.
# Accepts a bare name or a full path; all tools here support --version.
function Test-CmdRuns($cmd) {
    try {
        $null = & $cmd --version 2>&1
        return ($LASTEXITCODE -eq 0)
    }
    catch { return $false }
}

function Need-Command($name, [scriptblock]$install, $desc = "", $hint = "", [switch]$Fatal) {
    if ((Get-Command $name -ErrorAction SilentlyContinue) -and (Test-CmdRuns $name)) {
        Ok "$name already present: $((Get-Command $name).Source)"
        return
    }
    # Script-installed tools live under $InstallDir; those paths were added to
    # the User PATH but are not visible to this session (PATH changes only
    # affect new processes), so probe the install locations too.
    $inDir = Find-InstalledBinary $name
    if ($inDir -and (Test-CmdRuns $inDir)) {
        Add-ToUserPath (Split-Path $inDir)
        Ok "$name already present: $inDir"
        return
    }
    if ($inDir) { Warn "$name present but not runnable ($inDir), reinstalling" }
    Warn "$name not found"
    $descTxt = ""
    if ($desc) { $descTxt = " ($desc)" }
    if (-not (Confirm-Q "  Install $name$descTxt? [y/N]")) {
        Warn "$name skipped"
        return
    }
    Log "Auto-installing $name ..."
    & $install
    if ((Get-Command $name -ErrorAction SilentlyContinue) -and (Test-CmdRuns $name)) { Ok "$name installed" }
    elseif ($Fatal) {
        Err "$name install failed. $hint"
    } else {
        Warn "$name install failed or not on PATH, skipping"
    }
}

function Add-ToUserPath($dir) {
    if (-not (Test-Path $dir)) { return }
    $cur = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($cur -notlike "*$dir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$cur;$dir", "User")
        $env:PATH = "$env:PATH;$dir"
        Ok "PATH updated: $dir"
    }
}

# Script-installed tools live under $InstallDir ($BIN_DIR, nvim-win64, pandoc-*).
# Add-ToUserPath records those dirs in the User PATH, but PATH changes only
# affect newly started processes: a re-run in the same terminal session cannot
# see them via Get-Command. Probe the install locations themselves as well.
function Find-InstalledBinary($name) {
    foreach ($dir in @($BIN_DIR, "$InstallDir\nvim-win64\bin")) {
        $f = Get-ChildItem "$dir\$name*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    $p = Get-ChildItem "$InstallDir\pandoc-*\$name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { return $p.FullName }
    return $null
}

function Test-ToolReady($name) {
    if ((Get-Command $name -ErrorAction SilentlyContinue) -and (Test-CmdRuns $name)) { return $true }
    $f = Find-InstalledBinary $name
    if ($f -and (Test-CmdRuns $f)) { return $true }
    return $false
}

# Headless nvim success check (Bug I fix): nvim --headless returns 0 even when
# the config fails to load (E492/E5113), so inspect the output, not just the exit code.
# Runs in a background job with a 1500s watchdog (Bug O fix): a hung
# download must not block the script forever.
function Test-HeadlessOk {
    param([scriptblock]$Command)
    $job = Start-Job -ScriptBlock {
        param($c)
        $ErrorActionPreference = "Continue"
        $o = & $c 2>&1 | ForEach-Object { $_ | Out-String }
        [pscustomobject]@{ Out = ($o -join ""); Code = $LASTEXITCODE }
    } -ArgumentList $Command
    if (-not (Wait-Job $job -Timeout 1500)) {
        Stop-Job $job; Remove-Job $job -Force
        # nvim spawned by the job may have survived the job kill
        Get-Process nvim -ErrorAction SilentlyContinue | Stop-Process -Force
        Warn "headless nvim timed out (1500s), killed"
        return $false
    }
    $r = Receive-Job $job
    Remove-Job $job -Force
    if ($r.Code -ne 0) { return $false }
    return ($r.Out -notmatch 'E\d+: |Error detected|Error in ')
}

New-Item -ItemType Directory -Force -Path $InstallDir, $BIN_DIR | Out-Null

# ================================================================ Required tools
Log "== Checking required tools =="

# git (Bug E fix: fail hard when the silent install does not work)
Need-Command git {
    $url = Resolve-LatestReleaseUrl "git-for-windows" "git" "Git-*-64-bit.exe"
    if (-not $url) { Err "Failed to resolve git-for-windows download URL" }
    $exe = Join-Path $env:TEMP "git-setup.exe"
    Download $url $exe
    Start-Process $exe -ArgumentList "/VERYSILENT","/NORESTART","/SP-" -Wait
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Git\cmd",
        "$env:ProgramFiles\Git\cmd",
        "${env:ProgramFiles(x86)}\Git\cmd"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "git.exe")) { $env:Path = "$env:Path;$c"; break }
    }
} -Fatal "install git manually: https://git-scm.com/download/win"

# gcc (mingw-w64 winlibs; Bug H fix: PATH entry must point at the bin subdir)
Need-Command gcc {
    $url = Resolve-LatestReleaseUrl "brechtsanders" "winlibs_mingw" "winlibs-x86_64-*.zip"
    if (-not $url) { Warn "Failed to resolve winlibs URL, install gcc manually (https://winlibs.com) and retry"; return }
    $zip = Join-Path $env:TEMP "winlibs.zip"
    Download $url $zip
    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
    $mingwRoot = Get-ChildItem "$InstallDir\mingw*" -Directory | Select-Object -First 1
    if (-not $mingwRoot) { Warn "mingw extraction failed, install gcc manually"; return }
    $mingwBin = Join-Path $mingwRoot.FullName "bin"
    if (-not (Test-Path (Join-Path $mingwBin "gcc.exe"))) { Warn "gcc.exe not found under $mingwBin, install gcc manually"; return }
    Add-ToUserPath $mingwBin
} "install manually: https://winlibs.com (mingw-w64, includes gcc)"

# make (bundled with mingw; warn if missing)
if (-not (Test-CmdRuns "make")) {
    Warn "make not found (winlibs does not bundle it by default; install it if parser compilation fails later)"
}

# node (Bug B fix: resolve the latest release from the dist listing directly)
Need-Command node {
    $listing = Get-Page "https://nodejs.org/dist/latest/"
    $m = [regex]::Match($listing, 'node-v(\d+\.\d+\.\d+)-win-x64\.zip')
    if (-not $m.Success) { Warn "Failed to resolve node version, install manually: https://nodejs.org"; return }
    $ver = "v$($m.Groups[1].Value)"
    $zip = Join-Path $env:TEMP "node.zip"
    Download "https://nodejs.org/dist/latest/node-$ver-win-x64.zip" $zip
    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
    $nodeDir = Get-ChildItem "$InstallDir\node-*" -Directory | Select-Object -First 1
    Add-ToUserPath $nodeDir.FullName
} "install manually: https://nodejs.org"

# python3 (Bug A fix: pick the NEWEST version from the ftp listing, with fallback)
Need-Command python {
    $listing = Get-Page "https://www.python.org/ftp/python/"
    if (-not $listing) {
        Warn "python.org version listing unreachable via proxy, retrying direct"
        $listing = Get-Page "https://www.python.org/ftp/python/" -NoProxy
    }
    $versions = @([regex]::Matches($listing, '([0-9]+\.[0-9]+\.[0-9]+)/') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object { [version]$_ } -Descending)
    if ($versions.Count -eq 0) { Err "Failed to resolve python version, install manually: https://python.org" }
    $exe = Join-Path $env:TEMP "python-setup.exe"
    $downloaded = $false
    foreach ($pv in ($versions | Select-Object -First 5)) {
        $url = "https://www.python.org/ftp/python/$pv/python-$pv-amd64.exe"
        & curl.exe -sfI --max-time 15 $url | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "No installer for python $pv (pre-release?), trying the next version"; continue }
        Log "Downloading $url"
        $oldH = $env:http_proxy; $oldS = $env:https_proxy
        $env:http_proxy = ""; $env:https_proxy = ""
        & curl.exe -fL --retry 2 --connect-timeout 20 --max-time 600 -o $exe $url
        $env:http_proxy = $oldH; $env:https_proxy = $oldS
        if ($LASTEXITCODE -eq 0 -and (Test-Path $exe)) { $downloaded = $true; break }
        Warn "Download failed for python $pv, trying the next version"
    }
    if (-not $downloaded) { Err "Failed to download any python installer, install manually: https://python.org" }
    Start-Process $exe -ArgumentList "/quiet","InstallAllUsers=0","PrependPath=1" -Wait
    Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $env:Path = "$env:Path;$($_.FullName)" }
} "install manually: https://python.org"

# tree-sitter-cli (compiles parsers on online machines)
Need-Command tree-sitter {
    $url = Resolve-LatestReleaseUrl "tree-sitter" "tree-sitter" "tree-sitter-cli-windows-x64.*"
    if (-not $url) { Warn "Failed to resolve tree-sitter CLI URL, install manually: https://github.com/tree-sitter/tree-sitter/releases"; return }
    $zip = Join-Path $env:TEMP "tscli.zip"
    Download $url $zip
    Expand-Archive -Path $zip -DestinationPath $BIN_DIR -Force
    Add-ToUserPath $BIN_DIR
}

# win32yank (config hard dependency: clipboard)
if (-not (Test-CmdRuns "win32yank.exe")) {
    if (Test-Path "$BIN_DIR\win32yank.exe") {
        # Already installed to BIN_DIR by an earlier run; PATH may not reflect
        # it in this terminal session yet, so do not re-download.
        Add-ToUserPath $BIN_DIR
        Ok "win32yank already present: $BIN_DIR\win32yank.exe"
    } else {
        Log "Auto-installing win32yank (config clipboard dependency) ..."
        $url = Resolve-LatestReleaseUrl "equalsraf" "win32yank" "win32yank-x64.zip"
        if (-not $url) { Warn "Failed to resolve win32yank URL, install manually and add to PATH"; }
        else {
            $zip = Join-Path $env:TEMP "win32yank.zip"
            Download $url $zip
            Expand-Archive -Path $zip -DestinationPath $BIN_DIR -Force
            Add-ToUserPath $BIN_DIR
            Ok "win32yank installed"
        }
    }
} else { Ok "win32yank already present" }

# ================================================================ Optional tools
Log "== Optional tools (confirm as needed) =="
if (Test-CmdRuns "rustup") {
    Ok "rustup already present: $((Get-Command rustup).Source)"
} else {
    Need-Command rustup {
        $exe = Join-Path $env:TEMP "rustup-init.exe"
        Download "https://win.rustup.rs/x86_64" $exe
        Start-Process $exe -ArgumentList "-y","--default-toolchain","stable" -Wait
        $cargoBin = "$env:USERPROFILE\.cargo\bin"   # Bug C fix: rustup lands here, not on PATH yet
        if (Test-Path (Join-Path $cargoBin "rustup.exe")) { $env:Path = "$env:Path;$cargoBin" }
        if (Get-Command rustup -ErrorAction SilentlyContinue) {
            # 2>&1 | Out-Null instead of 2>$null: with $ErrorActionPreference=Stop,
            # PS 5.1 turns native stderr into a terminating NativeCommandError even
            # through 2>$null (observed on a real machine during component add).
            rustup component add rust-analyzer rustfmt 2>&1 | Out-Null
        }
    } "rust toolchain (rust-analyzer/rustfmt)"
}
if ((Test-ToolReady "fzf") -and (Test-ToolReady "rg") -and (Test-ToolReady "fd")) {
    Ok "fzf / rg / fd already present"
} else {
    foreach ($tool in @(@("fzf","junegunn","fzf","fzf-*-windows_amd64.zip"),
                       @("rg","BurntSushi","ripgrep","ripgrep-*-x86_64-pc-windows-msvc.zip"),
                       @("fd","sharkdp","fd","fd-*-x86_64-pc-windows-msvc.zip"))) {
        $name = $tool[0]
        if (Test-ToolReady $name) {
            $inDir = Find-InstalledBinary $name
            if ($inDir) { Add-ToUserPath (Split-Path $inDir); Ok "$name already present: $inDir" }
            else { Ok "$name already present: $((Get-Command $name).Source)" }
            continue
        }
        if (-not (Confirm-Q "  Install $name (fzf-lua search)? [y/N]")) { Warn "$name skipped"; continue }
        $url = Resolve-LatestReleaseUrl $tool[1] $tool[2] $tool[3]
        if (-not $url) { Warn "Failed to resolve $name download URL, skipping"; continue }
        $zip = Join-Path $env:TEMP "$name.zip"
        Download $url $zip
        Expand-Archive -Path $zip -DestinationPath $BIN_DIR -Force
        # promote executables from subdirectories to BIN_DIR
        Get-ChildItem $BIN_DIR -Recurse -Filter "$name*.exe" | Move-Item -Destination $BIN_DIR -Force -ErrorAction SilentlyContinue
        Add-ToUserPath $BIN_DIR
        Ok "$name installed"
    }
}
if (Test-CmdRuns "perl") {
    Ok "perl already present: $((Get-Command perl).Source)"
} else {
    Warn "On Windows install Strawberry Perl manually: https://strawberryperl.com (includes perltidy), and add it to PATH"
}
if (Test-CmdRuns "pandoc") {
    Ok "pandoc already present: $((Get-Command pandoc).Source)"
} elseif ($pd = Find-InstalledBinary "pandoc") {
    if (Test-CmdRuns $pd) {
        Add-ToUserPath (Split-Path $pd)
        Ok "pandoc already present: $pd"
    } else {
        Warn "pandoc present but not runnable ($pd), reinstalling"
        Need-Command pandoc {
            $url = Resolve-LatestReleaseUrl "jgm" "pandoc" "pandoc-*-windows-x86_64.zip"
            if (-not $url) { Warn "Failed to resolve pandoc download URL, skipping" }
            else {
                $zip = Join-Path $env:TEMP "pandoc.zip"
                Download $url $zip
                Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
                $pd = Get-ChildItem "$InstallDir\pandoc-*" -Directory | Select-Object -First 1
                if ($pd) { Add-ToUserPath $pd.FullName }
            }
        } "orgmode export"
    }
} else {
    Need-Command pandoc {
        $url = Resolve-LatestReleaseUrl "jgm" "pandoc" "pandoc-*-windows-x86_64.zip"
        if (-not $url) { Warn "Failed to resolve pandoc download URL, skipping" }
        else {
            $zip = Join-Path $env:TEMP "pandoc.zip"
            Download $url $zip
            Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
            $pd = Get-ChildItem "$InstallDir\pandoc-*" -Directory | Select-Object -First 1
            if ($pd) { Add-ToUserPath $pd.FullName }
        }
    } "orgmode export"
}

# ================================================================ Neovim
Log "== Installing Neovim =="
if ((Get-Command nvim -ErrorAction SilentlyContinue) -and (Test-CmdRuns "nvim")) {
    Ok "nvim already present: $((nvim --version | Select-Object -First 1))"
} elseif ((Test-Path "$InstallDir\nvim-win64\bin\nvim.exe") -and (Test-CmdRuns "$InstallDir\nvim-win64\bin\nvim.exe")) {
    # installed by an earlier run; PATH may not reflect it in this session yet
    Add-ToUserPath "$InstallDir\nvim-win64\bin"
    Ok "nvim already present: $InstallDir\nvim-win64\bin\nvim.exe"
} else {
    $url = Resolve-LatestReleaseUrl "neovim" "neovim" "nvim-win64.zip"
    if (-not $url) { Err "Failed to resolve nvim download URL, install manually: https://github.com/neovim/neovim/releases" }
    $ver = $url -match 'download/v([0-9.]+)/' | Out-Null; $ver = $Matches[1]
    $zip = Join-Path $env:TEMP "nvim-win64.zip"
    Download $url $zip
    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
    $nvimBin = Join-Path $InstallDir "nvim-win64\bin"
    Add-ToUserPath $nvimBin
    Ok "nvim v$ver installed"
}

# ================================================================ Config
Log "== Cloning config =="
if (Test-Path (Join-Path $CONFIG_DIR "init.lua")) {
    Log "$CONFIG_DIR already exists, skipping clone"
} else {
    # Bug F fix: check the clone result explicitly
    git clone --depth 1 $CONFIG_REPO $CONFIG_DIR
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $CONFIG_DIR "init.lua"))) {
        Err "Config clone failed; check network/proxy and retry: git clone --depth 1 $CONFIG_REPO $CONFIG_DIR"
    }
    Ok "Config cloned to $CONFIG_DIR"
}

# ================================================================ Plugins/tools/parsers
Set-Location $CONFIG_DIR
Log "== Installing plugins (Lazy) =="
$env:LANG = "en_US.UTF-8"; $env:LC_ALL = "en_US.UTF-8"
for ($attempt = 1; $attempt -le 3; $attempt++) {
    if (Test-HeadlessOk { nvim --headless "+Lazy! sync" +qa }) { break }
    Warn "Lazy sync failed (attempt $attempt), clearing lazy.nvim cache and retrying ..."
    Remove-Item -Recurse -Force "$DATA_DIR\lazy\lazy.nvim" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    if ($attempt -eq 3) { Err "Plugin install failed, check network/proxy and retry" }
}
$lazyCount = (Get-ChildItem "$DATA_DIR\lazy" -Directory -ErrorAction SilentlyContinue).Count
if ($lazyCount -eq 0) { Err "No plugins were installed by Lazy, aborting" }
Ok "Plugins installed ($lazyCount)"

Log "== Installing mason tools + treesitter parsers (ToolInstall) =="
$expectedParsers = 27
$masonCount = 0
for ($attempt = 1; $attempt -le 3; $attempt++) {
    # Bug K fix: load mason explicitly, otherwise the lazy-loaded plugin is
    # never activated headless and every tool is skipped as "unknown".
    # Keep nvim alive while the async installs finish. Sleep is in MILLISECONDS
    # ('m' suffix; bare `sleep 5000` is 5000 SECONDS and blocks for ~83 min).
    # Give fresh compiles a 5-minute window, only 10s once parsers are done.
    $curParsers = (Get-ChildItem "$DATA_DIR\site\parser\*.so" -ErrorAction SilentlyContinue).Count
    $sleepMs = if ($curParsers -lt $expectedParsers) { 300000 } else { 10000 }
    Test-HeadlessOk { nvim --headless +"lua require('mason').setup()" +ToolInstall +"sleep ${sleepMs}m" +qa } | Out-Null
    $parserCount = (Get-ChildItem "$DATA_DIR\site\parser\*.so" -ErrorAction SilentlyContinue).Count
    $masonCount  = (Get-ChildItem "$DATA_DIR\mason\packages" -Directory -ErrorAction SilentlyContinue).Count
    Write-Host "  Parsers: $parserCount/$expectedParsers  mason tools: $masonCount (attempt $attempt)" -ForegroundColor Cyan
    if ($parserCount -ge $expectedParsers) { break }
    Start-Sleep -Seconds 3
    if ($attempt -eq 3) { Warn "Parsers not fully installed ($parserCount/$expectedParsers), run :ToolInstall later" }
}
# Bug R fix: the parser loop above breaks the moment parsers are complete, so
# mason tools only ever get whatever window parsers left over (often 10s).
# Give mason its own retry loop with a fixed 5-minute window per round.
$expectedMasonTools = 10
$masonAttempt = 1
while ($masonCount -lt $expectedMasonTools -and $masonAttempt -le 3) {
    Log "Mason tools $masonCount/$expectedMasonTools — retry $masonAttempt/3 (5-min window) ..."
    Test-HeadlessOk { nvim --headless +"lua require('mason').setup()" +ToolInstall +"sleep 300000m" +qa } | Out-Null
    $masonCount = (Get-ChildItem "$DATA_DIR\mason\packages" -Directory -ErrorAction SilentlyContinue).Count
    $masonAttempt++
}
if ($masonCount -lt $expectedMasonTools) {
    Warn "Mason tools installed: $masonCount/$expectedMasonTools — run :ToolInstall once in an interactive nvim session (needs network)"
} else {
    Ok "mason tools installed ($masonCount)"
}

# ================================================================ Verification
Log "== Verification =="
$plugins = (Get-ChildItem "$DATA_DIR\lazy" -Directory -ErrorAction SilentlyContinue).Count
$parsers = (Get-ChildItem "$DATA_DIR\site\parser\*.so" -ErrorAction SilentlyContinue).Count
$mason   = (Get-ChildItem "$DATA_DIR\mason\packages" -Directory -ErrorAction SilentlyContinue).Count
$masonBin = Join-Path $DATA_DIR "mason\bin"
Add-ToUserPath $masonBin
if (Test-HeadlessOk { nvim --headless +qa }) {
    Ok "Startup verification passed"
} else {
    Warn "Startup verification reported errors, run nvim manually to inspect"
}
Write-Host ""
Write-Host "[install] Done: plugins=$plugins  parsers=$parsers  masonTools=$mason" -ForegroundColor Cyan
Write-Host "Reopen your terminal for PATH to take effect, then run nvim"