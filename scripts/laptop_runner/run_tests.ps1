# ============================================================================
# IMS Patrol Test Runner -- Tera P60 (Windows)
#
# Pulls the latest Patrol APK pair from GitHub Actions (workflow build.yml,
# job build-patrol-test-apk), installs them on the connected device, and
# runs the JUnit instrumentation directly via 'adb shell am instrument'.
#
# Why no Patrol CLI / Flutter SDK / repo checkout: the androidTest APK
# already contains pl.leancode.patrol.PatrolJUnitRunner and the compiled
# Dart test bundle. The integration tests use only patrol_finders, no
# native automator calls, so no host-side automator is required.
#
# Self-update: on each run, before the test orchestration, we fetch the
# canonical copy of this script from compleat-mobile/scripts/laptop_runner
# and replace ourselves on disk if remote $SCRIPT_VERSION is newer. Joe
# downloads the zip exactly once; everything after that is automatic.
# Pass -NoSelfUpdate to skip the check (we use it to avoid relaunch loops).
#
# Target: Windows PowerShell 5.1 (powershell.exe). File is pure ASCII --
# no smart quotes, em/en dashes, or other Unicode. PS 5.1 reads BOM-less
# files as the system codepage, and curly quotes from misdecoded dashes
# would close strings early, so we keep this file 100% ASCII.
# ============================================================================

param(
    [switch]$NoSelfUpdate
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# GitHub requires TLS 1.2+. PS 5.1 defaults vary -- force it on.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# --- paths -------------------------------------------------------------------
$scriptDir   = $PSScriptRoot
$configPath  = Join-Path $scriptDir 'config.txt'
$logDir      = Join-Path $scriptDir 'logs'
$downloadDir = Join-Path $scriptDir 'downloads'

New-Item -ItemType Directory -Force -Path $logDir      | Out-Null
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile   = Join-Path $logDir "run_$timestamp.log"

# Tee everything to file. Start-Transcript captures Write-Host + native cmd output.
Start-Transcript -Path $logFile -Append | Out-Null

# Script version. Bump on every Claude Code edit. The self-update step
# compares this against the same constant in the remote copy and replaces
# the local file on disk when remote is newer. Use semver-ish "M.m.p".
$SCRIPT_VERSION = '1.0.0'

# package constants -- match android/app/build.gradle.kts qa flavor
$APP_PACKAGE  = 'com.compleat.compleat_mobile.test'
$TEST_PACKAGE = 'com.compleat.compleat_mobile.test.test'
$RUNNER       = 'pl.leancode.patrol.PatrolJUnitRunner'
$WORKFLOW     = 'build.yml'

# --- helpers -----------------------------------------------------------------
function Write-Step ($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok   ($msg) { Write-Host "    OK: $msg"  -ForegroundColor Green }
function Write-Warn ($msg) { Write-Host "    WARN: $msg" -ForegroundColor Yellow }
function Write-Fail ($msg) {
    Write-Host ''
    Write-Host '==================== FAILURE ====================' -ForegroundColor Red
    Write-Host $msg -ForegroundColor Red
    Write-Host "Log: $logFile" -ForegroundColor Red
    Write-Host '=================================================' -ForegroundColor Red
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    Write-Host ''
    Read-Host 'Press Enter to close'
    exit 1
}

function Require-Cmd ($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Fail "'$name' not found on PATH. Open a new terminal or check installation."
    }
}

# Run a native command. PS 5.1 compatible -- uses the call operator + splatting
# (NOT ProcessStartInfo.ArgumentList, which is .NET 5+ only).
#
# Stderr is NOT failure -- only $LASTEXITCODE is authoritative. adb in
# particular writes "* daemon not running; starting now at tcp:5037" to
# stderr on first invocation, which is informational. We localize
# ErrorActionPreference to 'Continue' here because the script-wide 'Stop'
# (kept for Invoke-RestMethod / Invoke-WebRequest try/catch) can otherwise
# turn the ErrorRecord objects produced by 2>&1 into terminating errors
# and kill the run on benign daemon-startup chatter. The caller is
# responsible for inspecting the returned exit code.
function Invoke-Native ([string]$exe, [string[]]$argList) {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $exe @argList 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    return @{ Code = $LASTEXITCODE; Out = $output }
}

# Self-update helper -- fetches remote run_tests.ps1, compares versions,
# and (if remote is newer) overwrites this file on disk and re-launches
# with -NoSelfUpdate to break any potential loop. Returns nothing useful;
# either it exits the process after relaunching, or it returns and the
# caller proceeds with the local version.
#
# config.txt is NEVER touched here -- only run_tests.ps1 is replaced.
# Failure for ANY reason (network, auth, parse, IO) is a warning, not
# an error: we'd rather run an old test than block Joe's workflow.
function Invoke-SelfUpdate ([string]$Repo, [hashtable]$Headers,
                            [string]$LocalVersion, [string]$LocalPath) {
    try {
        $url = "https://raw.githubusercontent.com/$Repo/main/scripts/laptop_runner/run_tests.ps1"
        $resp = Invoke-WebRequest -Headers $Headers -Uri $url -UseBasicParsing
        $content = [string]$resp.Content
        if ($content -match '(?i)<html|<!doctype') {
            Write-Warn 'Update check skipped: remote returned HTML (likely 404 or auth -- check PAT scopes).'
            return
        }
        # Strip a UTF-8 BOM if the response carried one.
        if ($content.Length -gt 0 -and [int][char]$content[0] -eq 0xFEFF) {
            $content = $content.Substring(1)
        }
        if ($content -notmatch "(?m)^\`$SCRIPT_VERSION\s*=\s*'([^']+)'") {
            Write-Warn 'Update check skipped: could not parse $SCRIPT_VERSION from remote.'
            return
        }
        $remoteVersion = $matches[1]
        try {
            $localV  = [System.Version]::Parse($LocalVersion)
            $remoteV = [System.Version]::Parse($remoteVersion)
        } catch {
            Write-Warn "Update check skipped: bad version string (local='$LocalVersion', remote='$remoteVersion')."
            return
        }
        if ($remoteV -eq $localV) {
            Write-Ok "Script up to date (v$LocalVersion)"
            return
        }
        if ($remoteV -lt $localV) {
            Write-Warn "Local v$LocalVersion is newer than remote v$remoteVersion (uncommitted edits?). Continuing with local."
            return
        }
        # Remote is newer -- swap and relaunch.
        Write-Host "    Update available: v$remoteVersion (was v$LocalVersion)"
        # Quick smell-test: real PS files start with a banner comment or
        # the param block we added. If the body looks nothing like that,
        # bail rather than overwrite a working copy with garbage.
        $head = $content.Substring(0, [Math]::Min($content.Length, 200))
        if ($head -notmatch '^\s*(#|param)') {
            Write-Warn 'Update aborted: remote content does not look like a PowerShell script.'
            return
        }
        $bakPath = $LocalPath + '.bak'
        Copy-Item -LiteralPath $LocalPath -Destination $bakPath -Force
        # ASCII-only is a hard requirement of the script header. Normalize
        # to CRLF for Windows. WriteAllText with ASCIIEncoding writes no BOM.
        $normalized = ($content -replace "`r`n", "`n") -replace "`n", "`r`n"
        [System.IO.File]::WriteAllText($LocalPath, $normalized, (New-Object System.Text.ASCIIEncoding))
        Write-Ok "Self-updated to v$remoteVersion (backup: $bakPath). Relaunching..."
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LocalPath -NoSelfUpdate
        exit $LASTEXITCODE
    } catch {
        Write-Warn "Update check failed: $($_.Exception.Message). Continuing with local v$LocalVersion."
    }
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "  IMS Patrol Test Runner -- Tera P60 (v$SCRIPT_VERSION)"      -ForegroundColor Cyan
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"          -ForegroundColor Cyan
Write-Host "  Log:     $logFile"                                           -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

# ----------------------------------------------------------------------------
# 1) Validate prerequisites
# ----------------------------------------------------------------------------
Write-Step 'Checking prerequisites'
Require-Cmd 'adb'
Write-Ok 'adb on PATH'

# ----------------------------------------------------------------------------
# 2) Load + validate config
# ----------------------------------------------------------------------------
Write-Step 'Loading config'
if (-not (Test-Path $configPath)) {
    Write-Fail @"
config.txt not found at: $configPath

First-time setup:
  1. Copy config.example.txt to config.txt
  2. Open config.txt in Notepad
  3. Replace YOUR_GITHUB_PAT_HERE with your real GitHub Personal Access Token
     (needs the 'repo' scope)
  4. Save and re-run.
"@
}

$config = @{}
foreach ($line in Get-Content $configPath) {
    if ($line -match '^\s*#')   { continue }
    if ($line -match '^\s*$')   { continue }
    if ($line -match '^\s*([^=]+?)\s*=\s*(.+?)\s*$') {
        $config[$matches[1]] = $matches[2]
    }
}

$token = $config['GITHUB_TOKEN']
$repo  = $config['REPO']
if ([string]::IsNullOrWhiteSpace($token) -or $token -eq 'YOUR_GITHUB_PAT_HERE') {
    Write-Fail 'GITHUB_TOKEN is missing or still the placeholder. Edit config.txt.'
}
if ([string]::IsNullOrWhiteSpace($repo)) {
    Write-Fail 'REPO is missing in config.txt. Expected: REPO=servairmarketing/compleat-mobile'
}
Write-Ok "Config loaded (repo=$repo)"

$headers = @{
    Authorization          = "Bearer $token"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'ims-test-runner'
}

# ----------------------------------------------------------------------------
# Phase 0: Self-update check
# ----------------------------------------------------------------------------
# Runs after config load (we need the PAT to read the private repo's raw
# content) and before any test orchestration. If a newer version of this
# script is in compleat-mobile/scripts/laptop_runner/, we swap on disk and
# relaunch with -NoSelfUpdate (set automatically by the relaunch call to
# avoid loops). Any failure here is non-fatal -- we run the test with the
# local version anyway. config.txt is never touched by this phase.
Write-Step "Self-update check (current v$SCRIPT_VERSION)"
if ($NoSelfUpdate) {
    Write-Host '    (skipped -- relaunched after self-update)'
} elseif (-not $PSCommandPath) {
    Write-Host '    (skipped -- script path unknown, likely dot-sourced)'
} else {
    Invoke-SelfUpdate -Repo $repo -Headers $headers `
        -LocalVersion $SCRIPT_VERSION -LocalPath $PSCommandPath
}

# ----------------------------------------------------------------------------
# 3) Dispatch a fresh Patrol build on GitHub Actions
# ----------------------------------------------------------------------------
# Triggers the whole build.yml workflow (which includes build-patrol-test-apk
# behind its workflow_dispatch gate). Requires the PAT to have 'workflow'
# scope -- 'repo' alone returns 404 here.
Write-Step 'Dispatching Patrol build on GitHub Actions'
Write-Host '    (this run will trigger CI; total wall time about 6-8 minutes)'
$dispatchTimeUtc = (Get-Date).ToUniversalTime()
$dispatchUrl     = "https://api.github.com/repos/$repo/actions/workflows/$WORKFLOW/dispatches"
$dispatchBody    = '{"ref":"main"}'
try {
    # Invoke-WebRequest preserves StatusCode; Invoke-RestMethod hides it for 2xx.
    $dispatchResp = Invoke-WebRequest -Headers $headers -Uri $dispatchUrl `
        -Method Post -Body $dispatchBody -ContentType 'application/json' `
        -UseBasicParsing
} catch {
    Write-Fail @"
GitHub workflow_dispatch failed: $($_.Exception.Message)
URL: $dispatchUrl

Common causes:
  - PAT missing 'workflow' scope (regenerate with both 'repo' and 'workflow')
  - REPO in config.txt is wrong (must be owner/name, e.g. servairmarketing/compleat-mobile)
  - Branch 'main' doesn't exist or workflow doesn't allow workflow_dispatch
"@
}
if ($dispatchResp.StatusCode -ne 204) {
    Write-Fail "Workflow dispatch returned HTTP $($dispatchResp.StatusCode), expected 204."
}
Write-Ok "Dispatch accepted (workflow=$WORKFLOW, ref=main)"

# ----------------------------------------------------------------------------
# 4) Poll until the dispatched run completes
# ----------------------------------------------------------------------------
Write-Step 'Waiting for the dispatched run to register'

# GitHub takes about 5-15 seconds to register a dispatched run. We poll the
# runs list filtered by event=workflow_dispatch and pick the first run created
# at or after our dispatch timestamp. The 5s clock-skew grace is to absorb
# small differences between the local PC clock and GitHub's servers.
Start-Sleep -Seconds 10

$runId       = $null
$runNum      = $null
$runUrl      = $null
$startBudget = 90       # seconds to wait for the run to APPEAR
$startWaited = 10       # already slept 10
while ($startWaited -lt $startBudget -and -not $runId) {
    $listUrl = "https://api.github.com/repos/$repo/actions/runs?event=workflow_dispatch&per_page=10"
    try {
        $listResp = Invoke-RestMethod -Headers $headers -Uri $listUrl -Method Get
    } catch {
        Write-Warn "Run list query failed (will retry): $($_.Exception.Message)"
        Start-Sleep -Seconds 5; $startWaited += 5; continue
    }
    foreach ($run in $listResp.workflow_runs) {
        $runCreatedUtc = [DateTime]::Parse($run.created_at).ToUniversalTime()
        if ($runCreatedUtc -ge $dispatchTimeUtc.AddSeconds(-5)) {
            $runId  = $run.id
            $runNum = $run.run_number
            $runUrl = $run.html_url
            break
        }
    }
    if (-not $runId) {
        Start-Sleep -Seconds 5; $startWaited += 5
        Write-Host "    waiting for dispatched run to appear (${startWaited}s)"
    }
}
if (-not $runId) {
    Write-Fail @"
Dispatched run never appeared in the API after ${startBudget}s.
Open https://github.com/$repo/actions to verify the dispatch landed.
"@
}
Write-Ok "Run #$runNum picked up"
Write-Host "    URL: $runUrl"

Write-Step 'Building APKs (typical: about 5-7 min on a clean cache)'
$pollEvery   = 30
$buildBudget = 15 * 60     # 15 minutes
$buildWaited = 0
$status      = ''
$conclusion  = ''
$runDetail   = $null
$detailUrl   = "https://api.github.com/repos/$repo/actions/runs/$runId"
while ($buildWaited -lt $buildBudget) {
    try {
        $runDetail = Invoke-RestMethod -Headers $headers -Uri $detailUrl -Method Get
    } catch {
        Write-Warn "Run status query failed (will retry): $($_.Exception.Message)"
        Start-Sleep -Seconds $pollEvery; $buildWaited += $pollEvery; continue
    }
    $status     = $runDetail.status
    $conclusion = $runDetail.conclusion
    $mins       = [int]($buildWaited / 60)
    $secs       = $buildWaited % 60
    $tail       = if ($conclusion) { ", conclusion=$conclusion" } else { '' }
    Write-Host ("    [{0:D2}:{1:D2}] status={2}{3}" -f $mins, $secs, $status, $tail)
    if ($status -eq 'completed') { break }
    Start-Sleep -Seconds $pollEvery
    $buildWaited += $pollEvery
}

if ($status -ne 'completed') {
    Write-Fail @"
Build did not complete within $($buildBudget / 60) minutes (last status='$status').
Run URL: $runUrl

The CI run may be queued behind other jobs, or a single step is stuck. Open
the URL above; once it finishes, re-run this script to dispatch a new build.
"@
}
if ($conclusion -ne 'success') {
    Write-Fail @"
Build finished with conclusion='$conclusion' (expected 'success').
Run URL: $runUrl

Open the URL above to see which job failed. Common causes:
  - Flutter compile error in newly-added test code
  - patrol_cli pub global activate failed (transient)
  - Signing keystore secret missing/wrong
"@
}
Write-Ok "Build succeeded in $([int]($buildWaited / 60))m $($buildWaited % 60)s"

# ----------------------------------------------------------------------------
# 5) Fetch artifacts for the just-built run
# ----------------------------------------------------------------------------
Write-Step 'Fetching artifact list for this build'
$artsUrl = "https://api.github.com/repos/$repo/actions/runs/$runId/artifacts"
try {
    $artsResp = Invoke-RestMethod -Headers $headers -Uri $artsUrl -Method Get
} catch {
    Write-Fail "Could not list artifacts for run ${runId}: $($_.Exception.Message)"
}
$debugArt = $artsResp.artifacts | Where-Object { $_.name -eq 'app-patrol-debug.apk'       -and -not $_.expired } | Select-Object -First 1
$testArt  = $artsResp.artifacts | Where-Object { $_.name -eq 'app-patrol-androidTest.apk' -and -not $_.expired } | Select-Object -First 1
if (-not $debugArt -or -not $testArt) {
    $names = ($artsResp.artifacts | ForEach-Object { $_.name }) -join ', '
    Write-Fail @"
Run #$runNum completed successfully but did not produce both Patrol APK artifacts.
Found: $names
Run URL: $runUrl

Check the build-patrol-test-apk job for upload-artifact failures.
"@
}
# Same shape as the rest of the script already consumes for display.
$chosenRun = [pscustomobject]@{
    run_number    = $runNum
    head_sha      = $runDetail.head_sha
    display_title = $runDetail.display_title
    created_at    = $runDetail.created_at
}
Write-Host "    Run:     $($chosenRun.display_title)"
Write-Host "    Commit:  $($chosenRun.head_sha.Substring(0,7))"
Write-Host "    Created: $($chosenRun.created_at)"
Write-Ok "Both artifacts ready for run #$runNum"

# ----------------------------------------------------------------------------
# 6) Download + extract artifacts
# ----------------------------------------------------------------------------
Write-Step 'Downloading artifacts'

# Clean previous downloads to avoid stale APK confusion
Get-ChildItem $downloadDir -Force -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

function Download-Artifact ($artifact, $destZip) {
    $url    = $artifact.archive_download_url
    $sizeMb = [math]::Round($artifact.size_in_bytes / 1MB, 1)
    Write-Host "    GET $($artifact.name) ($sizeMb MB)"
    try {
        Invoke-WebRequest -Headers $headers -Uri $url -OutFile $destZip -UseBasicParsing
    } catch {
        Write-Fail "Download failed for $($artifact.name): $($_.Exception.Message)"
    }
    if (-not (Test-Path $destZip)) {
        Write-Fail "Download produced no file: $destZip"
    }
    $sz = (Get-Item $destZip).Length
    if ($sz -eq 0) {
        Write-Fail "Downloaded $($artifact.name) is empty (0 bytes)."
    }

    # Validate by zip magic bytes (PK\x03\x04), not by size. The androidTest
    # APK is genuinely tiny (~3.5 KB) -- it only holds the JUnit runner class
    # plus the Patrol bundle reference; the actual Dart test code lives in
    # app-patrol-debug.apk. A size-based gate produces false positives here.
    $magic = $null
    try {
        $fs = [System.IO.File]::OpenRead($destZip)
        try {
            $buf  = New-Object byte[] 4
            $read = $fs.Read($buf, 0, 4)
            if ($read -eq 4) { $magic = $buf }
        } finally {
            $fs.Dispose()
        }
    } catch {
        Write-Fail "Could not read $destZip to verify format: $($_.Exception.Message)"
    }

    $isZip = ($magic -and $magic[0] -eq 0x50 -and $magic[1] -eq 0x4B -and $magic[2] -eq 0x03 -and $magic[3] -eq 0x04)
    if (-not $isZip) {
        # Peek at the head -- when GitHub rejects auth, it returns HTML/JSON
        # instead of a zip; surfacing that text saves the user a guessing game.
        $preview = ''
        try {
            $bytes = [System.IO.File]::ReadAllBytes($destZip)
            $take  = [Math]::Min($bytes.Length, 400)
            $preview = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $take)
        } catch { }
        $hint = ''
        if ($preview -match '(?i)<html|<!doctype') {
            $hint = ' Looks like an HTML error page from GitHub -- verify GITHUB_TOKEN is valid and has the ''repo'' scope.'
        } elseif ($preview -match '"message"\s*:\s*"') {
            $hint = ' Looks like a GitHub API JSON error -- response: ' + $preview.Trim()
        }
        Write-Fail "Downloaded $($artifact.name) is not a zip (bad magic bytes, $sz bytes total).$hint"
    }
}

$debugZip = Join-Path $downloadDir 'app-patrol-debug.zip'
$testZip  = Join-Path $downloadDir 'app-patrol-androidTest.zip'
Download-Artifact $debugArt $debugZip
Download-Artifact $testArt  $testZip
Write-Ok 'Both artifact zips downloaded'

$debugDir = Join-Path $downloadDir 'debug'
$testDir  = Join-Path $downloadDir 'androidTest'
Expand-Archive -Path $debugZip -DestinationPath $debugDir -Force
Expand-Archive -Path $testZip  -DestinationPath $testDir  -Force

$debugApk = Get-ChildItem $debugDir -Filter '*.apk' -Recurse | Select-Object -First 1
$testApk  = Get-ChildItem $testDir  -Filter '*.apk' -Recurse | Select-Object -First 1
if (-not $debugApk) { Write-Fail 'No APK found inside app-patrol-debug.zip' }
if (-not $testApk)  { Write-Fail 'No APK found inside app-patrol-androidTest.zip' }
$debugMb = [math]::Round($debugApk.Length / 1MB, 1)
$testMb  = [math]::Round($testApk.Length  / 1MB, 1)
Write-Ok "Extracted: $($debugApk.Name) ($debugMb MB)"
Write-Ok "Extracted: $($testApk.Name) ($testMb MB)"

# ----------------------------------------------------------------------------
# 7) Verify a device is connected
# ----------------------------------------------------------------------------
Write-Step 'Checking adb device'
$devicesRaw  = (Invoke-Native 'adb' @('devices')).Out
$deviceLines = $devicesRaw -split '\r?\n' | Where-Object { $_ -match '^\S+\s+device\s*$' }
if ($deviceLines.Count -eq 0) {
    Write-Fail @"
No device in 'device' state.

adb devices output:
$devicesRaw

Checklist:
  - Tera P60 plugged in via USB
  - USB debugging enabled
  - This computer authorized on the device (check the popup on the P60)
"@
}
if ($deviceLines.Count -gt 1) {
    Write-Warn 'Multiple devices connected -- adb will refuse to install. Unplug the other devices.'
    Write-Fail 'Aborting due to ambiguous device selection.'
}
$serial = ($deviceLines[0] -split '\s+')[0]
Write-Ok "Device: $serial"

# ----------------------------------------------------------------------------
# 8) Uninstall old app + test app (ignore failures; package may not be installed)
# ----------------------------------------------------------------------------
# adb uninstall returns exit 0 even when package is missing -- check stdout.
Write-Step 'Uninstalling previous app + test app (if present)'
$u1 = Invoke-Native 'adb' @('uninstall', $APP_PACKAGE)
if ($u1.Out -match 'Success') { Write-Ok "removed $APP_PACKAGE" } else { Write-Host "    (not installed: $APP_PACKAGE)" }
$u2 = Invoke-Native 'adb' @('uninstall', $TEST_PACKAGE)
if ($u2.Out -match 'Success') { Write-Ok "removed $TEST_PACKAGE" } else { Write-Host "    (not installed: $TEST_PACKAGE)" }

# ----------------------------------------------------------------------------
# 9) Install both APKs (-t allows test packages, -r reinstall, -d allow downgrade)
# ----------------------------------------------------------------------------
Write-Step 'Installing app APK'
$i1 = Invoke-Native 'adb' @('install', '-t', '-r', '-d', $debugApk.FullName)
Write-Host $i1.Out.Trim()
if ($i1.Code -ne 0 -or $i1.Out -notmatch 'Success') {
    Write-Fail "adb install failed for $($debugApk.Name) (exit=$($i1.Code))"
}
Write-Ok "Installed $($debugApk.Name)"

Write-Step 'Installing androidTest APK'
$i2 = Invoke-Native 'adb' @('install', '-t', '-r', '-d', $testApk.FullName)
Write-Host $i2.Out.Trim()
if ($i2.Code -ne 0 -or $i2.Out -notmatch 'Success') {
    Write-Fail "adb install failed for $($testApk.Name) (exit=$($i2.Code))"
}
Write-Ok "Installed $($testApk.Name)"

# Verify both packages present
Write-Step 'Verifying install'
$pkgList = (Invoke-Native 'adb' @('shell', 'pm', 'list', 'packages')).Out
if ($pkgList -notmatch [regex]::Escape("package:$APP_PACKAGE"))  { Write-Fail "Package $APP_PACKAGE not visible after install." }
if ($pkgList -notmatch [regex]::Escape("package:$TEST_PACKAGE")) { Write-Fail "Package $TEST_PACKAGE not visible after install." }
Write-Ok 'Both packages present on device'

# ----------------------------------------------------------------------------
# 10) Run Patrol instrumentation
# ----------------------------------------------------------------------------
Write-Step 'Running Patrol tests (this can take ~30-90s)'
Write-Host "    Cmd: adb shell am instrument -w -e clearPackageData true $TEST_PACKAGE/$RUNNER"
Write-Host ''

$instArgs = @(
    'shell', 'am', 'instrument', '-w',
    '-e', 'clearPackageData', 'true',
    "$TEST_PACKAGE/$RUNNER"
)
$inst    = Invoke-Native 'adb' $instArgs
$instOut = $inst.Out
Write-Host $instOut

# ----------------------------------------------------------------------------
# 11) Parse results
# ----------------------------------------------------------------------------
Write-Step 'Result'

$passed  = $false
$crashed = $false
$reason  = ''

if ($instOut -match 'Process crashed' -or $instOut -match 'INSTRUMENTATION_FAILED') {
    $crashed = $true
    $reason  = 'Instrumentation process crashed before tests could report a result.'
}
elseif ($instOut -match 'OK \((\d+) tests?\)') {
    $passed = $true
    $count  = $matches[1]
    $reason = "All $count test(s) passed."
}
elseif ($instOut -match 'FAILURES!!![\s\S]*?Tests run:\s*(\d+),\s*Failures:\s*(\d+)') {
    $reason = "Tests run: $($matches[1]), Failures: $($matches[2])"
}
else {
    $reason = 'Could not parse instrumentation output. Treating as failure.'
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
if ($passed) {
    Write-Host '  RESULT: PASS' -ForegroundColor Green
    Write-Host "  $reason"      -ForegroundColor Green
} else {
    Write-Host '  RESULT: FAIL' -ForegroundColor Red
    Write-Host "  $reason"      -ForegroundColor Red
    if ($crashed) {
        Write-Host ''
        Write-Host '  Likely causes:' -ForegroundColor Yellow
        Write-Host '    - Test backend unreachable from device'
        Write-Host "    - Test user 'joseph' / 'Test@1234' missing in test Firestore/Auth"
        Write-Host '    - APK pair from a different commit than expected'
    }
}
Write-Host "  Run #$($chosenRun.run_number) | commit $($chosenRun.head_sha.Substring(0,7))"
Write-Host "  Log: $logFile"
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

Stop-Transcript -ErrorAction SilentlyContinue | Out-Null

Read-Host 'Press Enter to close'
if (-not $passed) { exit 1 }
exit 0
