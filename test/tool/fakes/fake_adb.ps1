# A stand-in for adb in test/tool/install_device_script_test.dart. It acts
# on a JSON device state ($env:FAKE_ADB_STATE), logs every call
# ($env:FAKE_ADB_LOG) and refuses anything it does not know, so a test fails
# loudly if the script ever runs another command. It never reaches a device.

$state = Get-Content $env:FAKE_ADB_STATE -Raw | ConvertFrom-Json
Add-Content -Path $env:FAKE_ADB_LOG -Value ($args -join ' ')

function Save-State { $state | ConvertTo-Json -Depth 6 | Set-Content -Path $env:FAKE_ADB_STATE -Encoding UTF8 }

function Write-Bytes([byte[]] $bytes) {
    $out = [Console]::OpenStandardOutput()
    $out.Write($bytes, 0, $bytes.Length)
    $out.Flush()
}

function Get-Sidecar([string] $apk) {
    $sha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    Get-Content (Join-Path $env:FAKE_APK_DIR "$sha.json") -Raw | ConvertFrom-Json
}

if ($args[0] -eq 'devices') {
    'List of devices attached'
    foreach ($device in $state.devices) { "$($device.serial)`t$($device.state)" }
    exit 0
}

if ($args[0] -ne '-s' -or $args.Count -lt 3) { "fake adb: no device named"; exit 1 }
$serial = $args[1]
if (-not ($state.devices | Where-Object { $_.serial -eq $serial -and $_.state -eq 'device' })) {
    "error: device '$serial' not found"; exit 1
}
$command = @($args | Select-Object -Skip 2)
$line = $command -join ' '
$package = $state.package
$app = $state.installed

switch -Regex ($line) {
    '^shell getprop ro\.product\.model$' { 'Fake Phone'; exit 0 }
    '^shell dumpsys package (\S+)$' {
        if (-not $app -or $Matches[1] -ne $package) { 'Dexopt state:'; exit 0 }
        'Packages:'
        "  Package [$package] (1a2b3c):"
        "    versionCode=$($app.versionCode) minSdk=24 targetSdk=36"
        "    pkgFlags=[ $(if ($app.debuggable) { 'DEBUGGABLE ' })HAS_CODE ALLOW_CLEAR_USER_DATA ]"
        "    firstInstallTime=$($app.firstInstallTime)"
        "    lastUpdateTime=$($app.lastUpdateTime)"
        exit 0
    }
    '^shell pm path (\S+)$' { "package:/data/app/~~fake==/$package-1/base.apk"; exit 0 }
    '^pull /data/app/\S+/base\.apk (.+)$' { Copy-Item $app.apk $Matches[1]; '1 file pulled.'; exit 0 }
    '^shell am force-stop (\S+)$' { exit 0 }
    '^shell run-as (\S+) ls -l databases$' {
        'total 2'
        "-rw------- 1 u0_a1 u0_a1 $((Get-Item $state.database).Length) 2026-11-12 10:00 sonus_next.db"
        "-rw------- 1 u0_a1 u0_a1 $($state.journalBytes) 2026-11-12 10:00 sonus_next.db-journal"
        exit 0
    }
    '^exec-out run-as (\S+) cat databases/sonus_next\.db$' {
        Write-Bytes ([IO.File]::ReadAllBytes($state.database))
        exit 0
    }
    '^exec-out run-as (\S+) tar -cf - \.$' { Write-Bytes ([Text.Encoding]::ASCII.GetBytes('fake app data')); exit 0 }
    '^install -r (.+)$' {
        $apk = $Matches[1]
        if ($state.installOutcome -eq 'fail') { 'Failure [INSTALL_FAILED_INTERNAL_ERROR]'; exit 1 }
        $app.versionCode = (Get-Sidecar $apk).versionCode
        $app.apk = $apk
        $app.lastUpdateTime = '2026-11-12 10:05:00'
        if ($state.installOutcome -eq 'reinstalled') { $app.firstInstallTime = '2026-11-12 10:05:00' }
        Save-State
        'Performing Streamed Install'
        'Success'
        exit 0
    }
}

"fake adb: unsupported command: $line"
exit 1
