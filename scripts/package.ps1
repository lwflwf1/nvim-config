<#
.nvim-config packaging script (PowerShell port of package.sh)
Usage:
  powershell -ExecutionPolicy Bypass -File package.ps1 [-Out DIR] [-NvimVersion v0.12.4] [-Proxy http://host:port]
                                              [-ConfigRepo URL] [-ConfigRev REF]

Every download group is confirmed interactively (default answer: download).
Piped answers are honored; a closed stdin (CI/background) auto-accepts.

NOTE: the produced bundle targets LINUX x86_64 offline machines (the nvim
old-glibc build and all tool caches are the linux assets). The config/ directory
is CLONED from a git remote (default https://github.com/lwflwf1/nvim-config.git,
override with -ConfigRepo/-ConfigRev) so the bundle is reproducible and free of
local working-tree junk. data/ carries only the local plugin cache (lazy/); the
Windows-specific mason/ and site/ trees are NOT bundled - the offline installer
supplies the Linux tool binaries from tools/ + npm-tools + glibc-2.34 wrappers.

Output: <out>/nvim-bundle-linux-x86_64-<date>.tar.gz
  config/            config directory (git clone of the remote)
  data/              nvim data directory (lazy plugins only)
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
    [string]$Proxy = "",
    [string]$ToolsFile = "",
    [string]$ConfigRepo = "https://github.com/lwflwf1/nvim-config.git",
    [string]$ConfigRev = ""
)

$ErrorActionPreference = "Stop"
$script:ConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "nvim" } else { Join-Path $env:LOCALAPPDATA "nvim" }
$script:DataDir   = if ($env:XDG_DATA_HOME)   { Join-Path $env:XDG_DATA_HOME "nvim" }   else { Join-Path $env:LOCALAPPDATA "nvim-data" }
if (-not $Out) { $Out = (Get-Location).Path }

if ($Proxy) {
    $env:http_proxy = $Proxy; $env:https_proxy = $Proxy
    $env:HTTP_PROXY = $Proxy; $env:HTTPS_PROXY = $Proxy
    # git/libcurl can ignore lower/upper-case proxy env quirks; set it explicitly
    # so the systemverilog fork clone and codeload git fallback work behind a proxy.
    try { & git.exe config --global http.proxy $Proxy; & git.exe config --global https.proxy $Proxy } catch {}
}

# Default tools.json lives next to this script (it is the single source of truth
# for every downloadable asset: source, owner/repo, asset glob, pin, glibc mark).
if (-not $ToolsFile) { $ToolsFile = Join-Path $PSScriptRoot "tools.json" }

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

function Get-FileSizeMB($path) {
    $len = (Get-Item $path).Length
    return ("{0:N1}MB" -f ($len / 1MB))
}

$script:ManifestPath = ""
function Manifest([string]$line) {
    [System.IO.File]::AppendAllText($script:ManifestPath, $line + "`n", [System.Text.Encoding]::ASCII)
}

# ---------------------------------------------------------------- Bundle root
$BundleRoot = Join-Path $Out ".bundle-tmp"
if (Test-Path $BundleRoot) { Remove-Item -Recurse -Force $BundleRoot }
New-Item -ItemType Directory -Force -Path $BundleRoot | Out-Null
$ToolsDir = Join-Path $BundleRoot "tools"
$ParserSrcDir = Join-Path $BundleRoot "parser-sources"
New-Item -ItemType Directory -Force -Path $ToolsDir, $ParserSrcDir | Out-Null
$script:ManifestPath = Join-Path $BundleRoot "manifest.txt"
[System.IO.File]::WriteAllText($script:ManifestPath, "format=2`n", [System.Text.Encoding]::ASCII)

# ---------------------------------------------------------------- tools.json (single asset table)
if (-not (Test-Path $ToolsFile)) { Err "tools.json not found: $ToolsFile" }
try { $script:ToolsDef = Get-Content $ToolsFile -Raw | ConvertFrom-Json }
catch { Err "Failed to parse tools.json: $_" }

# Persistent download cache, keyed by resolved version (so a pinned-bump or a
# latest bump never reuses a stale tarball). versions.json records name -> version.
$script:CacheDir = Join-Path $Out ".nvim-tool-cache"
$script:VersionsFile = Join-Path $script:CacheDir "versions.json"
if (-not (Test-Path $script:CacheDir)) { New-Item -ItemType Directory -Force -Path $script:CacheDir | Out-Null }
$script:Versions = $null
if (Test-Path $script:VersionsFile) {
    try { $script:Versions = Get-Content $script:VersionsFile -Raw | ConvertFrom-Json } catch { $script:Versions = $null }
}
if (-not $script:Versions) { $script:Versions = New-Object PSObject }

$script:DlList   = [System.Collections.Generic.List[string]]::new()
$script:GlList   = [System.Collections.Generic.List[string]]::new()
$script:ToolsSh  = [System.Collections.Generic.List[string]]::new()

function Get-VersionCache([string]$name) {
    if ($script:Versions -and ($script:Versions.PSObject.Properties.Name -contains $name)) { return $script:Versions.$name }
    return ""
}
function Set-VersionCache([string]$name, [string]$ver) {
    if ($script:Versions.PSObject.Properties.Name -contains $name) { $script:Versions.$name = $ver }
    else { $script:Versions | Add-Member -NotePropertyName $name -NotePropertyValue $ver }
}

# Resolve a tool entry to @{ version; url }. Empty version = follow latest.
function Resolve-ToolUrl($e) {
    if ($e.version) {
        if ($e.source -eq "nodejs") {
            return @{ version = $e.version; url = ($e.url_template -replace "\{version\}", $e.version) }
        }
        $rel = Get-Json "https://api.github.com/repos/$($e.owner)/$($e.repo)/releases/tags/$($e.version)"
        if (-not $rel) { return $null }
        $asset = $rel.assets | Where-Object { $_.name -like $e.asset_glob } | Select-Object -First 1
        if (-not $asset) { return $null }
        return @{ version = $e.version; url = $asset.browser_download_url }
    }
    if ($e.source -eq "nodejs") {
        $idx = Get-Json $e.latest_url
        if (-not $idx) { return $null }
        $ver = $idx[0].version
        return @{ version = $ver; url = ($e.url_template -replace "\{version\}", $ver) }
    }
    $rel = Get-Json "https://api.github.com/repos/$($e.owner)/$($e.repo)/releases/latest"
    if (-not $rel) { return $null }
    $ver = $rel.tag_name
    $asset = $rel.assets | Where-Object { $_.name -like $e.asset_glob } | Select-Object -First 1
    if (-not $asset) { return $null }
    return @{ version = $ver; url = $asset.browser_download_url }
}

# Download (or reuse cached) a tool's asset into the bundle. Records manifest lines.
function Process-Tool($e, [string]$Prompt = "", $resolved = $null) {
    if (-not $resolved) { $resolved = Resolve-ToolUrl $e }
    if (-not $resolved) { Warn "$($e.name) resolution failed"; return }
    $ver = $resolved.version; $url = $resolved.url
    if (-not $Prompt) { $Prompt = "  Download and bundle $($e.name) $ver? [Y/n] " }
    $ext = ($e.out_file -split '\.', 2)[1]
    $cacheName = "$($e.name)-$ver.$ext"
    $cachePath = Join-Path $script:CacheDir $cacheName
    $dest = if ($e.install -eq "nvim-dir") { Join-Path $BundleRoot "nvim\nvim-linux-x86_64.tar.gz" }
            else { Join-Path $ToolsDir $e.out_file }
    $cached = Get-VersionCache $e.name
    if (($cached -eq $ver) -and (Test-Path (Join-Path $script:CacheDir $cacheName))) {
        Copy-Item $cachePath $dest -Force
        Ok "$($e.name) $ver (cached, skipped download)"
    } else {
        if (-not (Confirm-Download $Prompt)) { Warn "$($e.name) skipped"; return }
        Download $url $cachePath
        Set-VersionCache $e.name $ver
        ConvertTo-Json $script:Versions -Compress | Set-Content $script:VersionsFile -Encoding ascii
        Copy-Item $cachePath $dest -Force
        Ok "$($e.name) $ver cached"
    }
    Manifest "tool $($e.name) $ver $url"
    if ($e.glibc234) { Manifest "glibc234 $($e.name)" }
}

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
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Err "git not found, needed to clone the config repository"
}
if (-not (Test-Path (Join-Path $script:DataDir "lazy"))) {
    Err "Plugins not installed, run install.ps1 first"
}
Log "Packaging sources: config=$script:ConfigRepo (rev=$($script:ConfigRev))  data=$script:DataDir"

# ---------------------------------------------------------------- config (clone) + data (lazy only)
Log "== Cloning config from $($script:ConfigRepo) =="
$cfgCopy = Join-Path $BundleRoot "config"
$cloneArgs = @("clone", "--depth", "1")
if ($script:ConfigRev) { $cloneArgs += @("--branch", $script:ConfigRev) }
$cloneArgs += @($script:ConfigRepo, $cfgCopy)
try { & git.exe @cloneArgs *> $null } catch { Warn "git stderr captured: $_" }
if (-not (Test-Path (Join-Path $cfgCopy ".git"))) {
    Err "config clone failed from $($script:ConfigRepo) (check proxy/network/auth)"
}
Remove-Item -Recurse -Force (Join-Path $cfgCopy ".git") -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $cfgCopy "lazy-lock.json") -ErrorAction SilentlyContinue
# Point the rest of the script (parsers.lua, lazy-lock.json) at the CLONE, not
# the local working tree, so the bundle is reproducible.
$script:ConfigDir = $cfgCopy
Log "== Copying data (lazy plugins only) =="
$dataCopy = Join-Path $BundleRoot "data"
New-Item -ItemType Directory -Force -Path $dataCopy | Out-Null
Copy-Item -Recurse -Force (Join-Path $script:DataDir "lazy") (Join-Path $dataCopy "lazy")
# Belt-and-suspenders: drop any Windows binaries that may have slipped into
# plugin trees (plugins are Lua, but be safe). mason/ and site/ are intentionally
# NOT bundled - the offline installer provides the Linux tool binaries.
foreach ($ext in @("*.exe","*.dll","*.cmd","*.bat")) {
    Get-ChildItem -Path (Join-Path $dataCopy "lazy") -Recurse -Force -Include $ext -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
Ok "config + data copied"
# No mason/ packages are bundled (Linux tools come from tools/ + npm-tools).
Manifest "mason=0"

# ---------------------------------------------------------------- nvim binary (driven by tools.json)
Log "== Neovim binary (old-glibc build, from tools.json) =="
$nvimEntry = $script:ToolsDef.tools | Where-Object { $_.name -eq "nvim" } | Select-Object -First 1
if (-not $nvimEntry) { Err "tools.json is missing the 'nvim' entry" }
if ($NvimVersion) { $nvimEntry.version = $NvimVersion }
$nv = Resolve-ToolUrl $nvimEntry
if (-not $nv) { Err "Failed to resolve nvim version from tools.json" }
New-Item -ItemType Directory -Force -Path (Join-Path $BundleRoot "nvim") | Out-Null
Process-Tool $nvimEntry ("Download and bundle neovim $($nv.version) (old-glibc build for offline machines)? [Y/n] ") $nv

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
        & git.exe init -q 2>$null
        & git.exe remote add origin "https://github.com/$owner/$repo.git" 2>$null
        & git.exe fetch -q --depth 1 origin $rev 2>$null
        if ($LASTEXITCODE -eq 0) { & git.exe checkout -q FETCH_HEAD 2>$null }
        $ok = ($LASTEXITCODE -eq 0)
    } catch { $ok = $false }
    finally { Pop-Location }
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
            # git prints "Cloning into ..." to stderr; under ErrorActionPreference=Stop
            # that would be treated as a terminating error, so wrap it.
            try { & git.exe clone --depth 1 $url $svDir *> $null }
            catch { Warn "  git stderr captured: $_" }
            if (-not (Test-Path (Join-Path $svDir ".git"))) {
                Warn "  $lang clone failed, skipping"; continue
            }
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
                    try { & tree-sitter generate *> $null; $genOk = ($LASTEXITCODE -eq 0) }
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
        # Record the optional `location` subdir (e.g. markdown_inline lives in
        # tree-sitter-markdown-inline inside the same repo) so install-offline.sh
        # compiles the parser from the correct source dir.
        $loc = Get-ParserField $lang "location"
        Manifest "parser $lang $url $rev $loc"
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

# ---------------------------------------------------------------- Optional tool cache (driven by tools.json)
# tree-sitter-cli is intentionally NOT cached: offline machines compile parsers
# directly with gcc (see install-offline.sh header), so shipping its binary is
# dead weight. It is only needed on the online packaging machine.
$DownloadTools = $script:ToolsDef.tools | Where-Object { $_.source -ne "external" -and $_.name -ne "nvim" }
Log "== External tool cache (from tools.json: $($DownloadTools.name -join ' ')) =="
if (Confirm-Download "Process external tool cache for offline install? [Y/n] ") {
    foreach ($e in $DownloadTools) {
        $hint = ""
        if (Get-Command $e.binary -ErrorAction SilentlyContinue) { $hint = "  (local: present)" }
        Process-Tool $e ("  Download and bundle $($e.name)?$hint [Y/n] ")
    }
} else {
    Warn "External tool cache skipped"
}

# ---------------------------------------------------------------- npm tools cache (offline mason fallback)
Log "== npm tools cache (offline fallback for mason npm packages) =="
$NpmTools = $script:ToolsDef.npm
if (Confirm-Download "Bundle npm tools ($NpmTools)? [Y/n] ") {
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $np = Join-Path $BundleRoot "npmtools"
        New-Item -ItemType Directory -Force -Path $np | Out-Null
        Push-Location $np
        try {
            & npm.cmd install --no-audit --no-fund --loglevel=error $NpmTools *> $null
            $npmOk = ($LASTEXITCODE -eq 0) -and (Test-Path (Join-Path $np "node_modules"))
        } catch { $npmOk = $false }
        finally { Pop-Location }
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

# ---------------------------------------------------------------- Emit tools.sh companion + copy tools.json
# install-offline.sh sources tools.sh (derived from tools.json) to drive install
# and glibc-2.34 wrapper generation — no JSON parsing needed on the offline box.
foreach ($e in $script:ToolsDef.tools) {
    $glibc = if ($e.glibc234) { "1" } else { "0" }
    $realpath = if ($e.realpath) { $e.realpath } else { "" }
    $safeName = $e.name -replace '-', '_'
    $script:ToolsSh.Add("$($safeName)_install=`"$($e.install)`"")
    $script:ToolsSh.Add("$($safeName)_binary=`"$($e.binary)`"")
    $script:ToolsSh.Add("$($safeName)_outfile=`"$($e.out_file)`"")
    $script:ToolsSh.Add("$($safeName)_glibc234=`"$glibc`"")
    $script:ToolsSh.Add("$($safeName)_realpath=`"$realpath`"")
    if ($e.source -ne "external") { $script:DlList.Add($e.name) }
    if ($e.glibc234) { $script:GlList.Add($e.name) }
}
$npmJoined = if ($script:ToolsDef.npm) { $script:ToolsDef.npm -join ' ' } else { "" }
$header = @("# GENERATED from tools.json - do not edit",
             "TOOLS_DOWNLOAD=`"$($script:DlList -join ' ')`"",
             "TOOLS_GLIBC=`"$($script:GlList -join ' ')`"",
             "NPM_PACKAGES=`"$npmJoined`"")
$all = $header + $script:ToolsSh
[System.IO.File]::WriteAllText((Join-Path $BundleRoot "tools.sh"), ($all -join "`n") + "`n", [System.Text.Encoding]::ASCII)
Copy-Item $ToolsFile (Join-Path $BundleRoot "tools.json") -Force
Log "tools.sh + tools.json emitted for the installer"

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