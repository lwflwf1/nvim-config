<#
.SYNOPSIS
    Replay a wakatime-cli offline queue (copied from the air-gapped RHEL6 box)
    into the self-hosted wakapi backend.

.DESCRIPTION
    scripts/wakatime-export.sh (run on RHEL6) copies ~/.wakatime/offline_
    heartbeats.bdb out. This uploads it from a machine that can reach the
    backend, using wakatime-cli's own sync path -- no hand-rolled JSON, no auth
    header, and the queue is drained on success so the copy is disposable.

    Credentials come from the normal ~/.wakatime.cfg (written by
    box.wakatime.ensure_config), so the api key never appears in this script.
    Re-uploading the same file is harmless: wakapi hashes every heartbeat into a
    UNIQUE index (models.Heartbeat.Hashed) and dedupes on insert.

.PARAMETER QueueFile
    The copied .bdb to replay. Default: newest wakatime-*.bdb in the current
    directory.

.PARAMETER Cli
    wakatime-cli executable. Default: ~/.wakatime/wakatime-cli.exe, then PATH.

.PARAMETER Keep
    Keep the queue file even after a successful sync (for debugging).

.EXAMPLE
    pwsh -File scripts/wakatime-sync.ps1
    pwsh -File scripts/wakatime-sync.ps1 -QueueFile D:\tmp\wakatime-20261012.bdb
#>
[CmdletBinding()]
param(
    [string]$QueueFile,
    [string]$Cli,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'

function Say  { param([string]$m) Write-Host "[wakatime] $m" }
function Die  { param([string]$m) Write-Host "[wakatime] ERROR: $m" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- locate the queue
if (-not $QueueFile) {
    $QueueFile = Get-ChildItem -Path (Get-Location) -Filter 'wakatime-*.bdb' -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $QueueFile) { Die "no queue file given and none named wakatime-*.bdb found in $(Get-Location)" }
if (-not (Test-Path -LiteralPath $QueueFile)) { Die "queue file not found: $QueueFile" }

# ---------------------------------------------------------------- locate the CLI
if (-not $Cli) {
    $managed = Join-Path $HOME '.wakatime\wakatime-cli.exe'
    if (Test-Path -LiteralPath $managed) { $Cli = $managed }
    else { $Cli = 'wakatime-cli' }
}
$resolved = (Get-Command $Cli -ErrorAction SilentlyContinue).Source
if (-not $resolved) { Die "wakatime-cli not found (looked for '$Cli')" }
Say "cli: $resolved"

# ---------------------------------------------------------------- credentials
$cfg = Join-Path $HOME '.wakatime.cfg'
if (-not (Test-Path -LiteralPath $cfg)) { Die "missing $cfg - open nvim once so box.wakatime can create it" }
$cfgText = Get-Content -LiteralPath $cfg -Raw
foreach ($setting in 'api_key', 'api_url') {
    if ($cfgText -notmatch "(?m)^\s*$setting\s*=\s*\S") {
        Die "$setting missing from $cfg - run :WakaTimeApiKey in nvim, or set WAKATIME_API_URL"
    }
}
if ($cfgText -match '(?m)^\s*api_url\s*=\s*(\S+)') { Say "api_url: $($Matches[1])" }
if ($cfgText -match '(?m)^\s*api_url\s*=\s*https?://127\.0\.0\.1:1') {
    Die "api_url is the air-gapped placeholder - point it at the real backend first"
}

# ---------------------------------------------------------------- pre-flight count
$before = (& $resolved --offline-queue-file $QueueFile --offline-count 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { Die "cannot read the queue (torn copy?): $before" }
if ($before -notmatch '^\d+$') { Die "unexpected --offline-count output: $before" }
if ([int]$before -eq 0) { Die "queue is empty - nothing to sync" }
Say "queued heartbeats: $before"

# ---------------------------------------------------------------- replay
# --sync-offline-activity 0 == "sync all" (default is 1000). cmd/run.go dispatches
# this before any --entity handling, so no heartbeat of our own is generated.
Say "uploading..."
$out = (& $resolved --offline-queue-file $QueueFile --sync-offline-activity 0 --verbose 2>&1 | Out-String)
$code = $LASTEXITCODE

# ---------------------------------------------------------------- verify
$after = (& $resolved --offline-queue-file $QueueFile --offline-count 2>&1 | Out-String).Trim()

if ($out -match 'API key not valid|Unauthorized|401') {
    Write-Host $out
    Die "backend rejected the api key"
}
if ($code -ne 0 -or $after -ne '0') {
    Write-Host $out
    Die "sync incomplete (exit $code, $after heartbeats still queued) - keep the file and retry; re-uploading is idempotent"
}

Say "done - $before heartbeats uploaded, queue drained"
if (-not $Keep) {
    Remove-Item -LiteralPath $QueueFile -Force
    Say "removed $QueueFile (use -Keep to retain it)"
}
