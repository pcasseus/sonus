# SN-42 audit remediation validation.
#
# Runs Flutter analysis, the recovery suite, the affected feature suites,
# and the full host regression suite, writing every log under
# build/audit_validation/<label>/ so results can be reviewed afterwards.
#
# Usage (from the project root):
#   powershell -ExecutionPolicy Bypass -File tool\sn42\run_audit_validation.ps1 -Label batch1
#
# Host tests only. It never touches a device, Git, or user data.
param(
    [string]$Label = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [switch]$SkipFull,
    # Repeats the full suite to surface load-dependent (intermittent) failures.
    [int]$FullRuns = 1
)

$ErrorActionPreference = 'Continue'
Set-Location (Join-Path $PSScriptRoot '..\..')

$out = Join-Path 'build\audit_validation' $Label
New-Item -ItemType Directory -Force -Path $out | Out-Null
$summary = Join-Path $out 'summary.txt'
"label=$Label" | Out-File -Encoding utf8 $summary
"started=$(Get-Date -Format o)" | Out-File -Encoding utf8 -Append $summary
"head=$(git rev-parse HEAD)" | Out-File -Encoding utf8 -Append $summary
"branch=$(git branch --show-current)" | Out-File -Encoding utf8 -Append $summary
"uncommitted=$((git status --short) -join '; ')" | Out-File -Encoding utf8 -Append $summary

$script:failedSteps = @()

function Run-Step([string]$name, [string[]]$arguments) {
    $log = Join-Path $out "$name.log"
    Write-Host "=== $name : flutter $($arguments -join ' ')" -ForegroundColor Cyan
    # Captured, then written as UTF-8 so logs are readable on any host.
    & flutter @arguments *>&1 | Tee-Object -Variable captured
    $code = $LASTEXITCODE
    $captured | Out-File -Encoding utf8 $log
    "$name exit=$code" | Out-File -Encoding utf8 -Append $summary
    if ($code -ne 0) { $script:failedSteps += $name }
    Write-Host "=== $name exit=$code" -ForegroundColor Cyan
}

& flutter --version *>&1 | Out-File -Encoding utf8 (Join-Path $out 'flutter_version.log')

# Every step runs and is recorded, even after an earlier step fails.
Run-Step 'analyze' @('analyze')
Run-Step 'recovery' @('test', 'test/features/recovery', '--reporter', 'expanded')
Run-Step 'affected' @('test', 'test/features/sync', 'test/core', 'test/app', '--reporter', 'expanded')

if (-not $SkipFull) {
    for ($run = 1; $run -le $FullRuns; $run++) {
        $name = if ($FullRuns -eq 1) { 'full' } else { "full_$run" }
        Run-Step $name @('test', '--reporter', 'expanded')
    }
}

$overall = if ($script:failedSteps.Count -eq 0) { 0 } else { 1 }
"failed_steps=$($script:failedSteps -join ',')" | Out-File -Encoding utf8 -Append $summary
"overall exit=$overall" | Out-File -Encoding utf8 -Append $summary
"finished=$(Get-Date -Format o)" | Out-File -Encoding utf8 -Append $summary
Write-Host "Logs written to $out" -ForegroundColor Green
Get-Content $summary

# Nonzero when any step failed. The known SN-41 baseline failure still
# counts: it is reported, never hidden.
exit $overall
