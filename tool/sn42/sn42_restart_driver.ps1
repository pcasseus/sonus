# Runs the SN-42 restart driver on the disposable emulator ONLY, with real
# process kills between phases. Results are read from the app sandbox.
param([string]$Serial = 'emulator-5584')

# Disposable-emulator guard: never run against a physical device.
if ($Serial -notlike 'emulator-*') { throw "Refusing to run on ${Serial}: emulators only." }
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\sdk' }
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$serial = $Serial

Set-Location (Join-Path $PSScriptRoot '..\..')
$package = 'com.sonus.sonus_next'
$base = 'files/sn42_integration/restart'

function Run-As([string]$command) {
    & $adb -s $serial shell "run-as $package sh -c '$command'" 2>$null
}

function Wait-For([string]$file, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        $found = Run-As "test -e $base/$file && echo yes"
        if ($found -match 'yes') { return $true }
        $error_file = Run-As "test -e $base/result_error.json && cat $base/result_error.json"
        if ($error_file) { "driver_error=$error_file"; return $false }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Start-SonusDriver { & $adb -s $serial shell am start -W -n "$package/.MainActivity" | Out-Null }

# Force-stops the app and proves the process is gone.
function Stop-SonusDriver {
    & $adb -s $serial shell am force-stop $package | Out-Null
    Start-Sleep -Seconds 2
    $alive = (& $adb -s $serial shell pidof $package 2>$null)
    if ($alive) { throw "process still alive after force-stop: $alive" }
    "process_stopped=verified"
}

flutter build apk --debug -t integration_test/sn42_restart_driver.dart 2>&1 | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { throw "driver build failed ($LASTEXITCODE)" }

& $adb -s $serial install -r build\app\outputs\flutter-apk\app-debug.apk | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { throw "install failed ($LASTEXITCODE)" }
Stop-SonusDriver
Run-As "rm -rf $base" | Out-Null

# Phase 1: kill inside the restore transaction.
Start-SonusDriver
if (-not (Wait-For 'inside_transaction.marker' 180)) { throw 'restore never reached the transaction' }
Stop-SonusDriver
"phase_kill=done (inside transaction)"

# Phase 2: relaunch, recover, then complete a held restore.
Start-SonusDriver
if (-not (Wait-For 'result_recover.json' 180)) { throw 'recover phase did not finish' }
"result_recover=$(Run-As "cat $base/result_recover.json")"
Stop-SonusDriver

# Phase 3: relaunch; the hold must persist.
Start-SonusDriver
if (-not (Wait-For 'result_persist.json' 120)) { throw 'persist phase did not finish' }
"result_persist=$(Run-As "cat $base/result_persist.json")"
Stop-SonusDriver

& $adb -s $serial uninstall $package | Select-Object -Last 1
"driver_complete"
