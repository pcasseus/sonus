# Operates the Android system document dialogs for the SN-42 picker test.
# Targets ONLY the disposable emulator (emulator-5584).
param([string]$Serial = 'emulator-5584')

# Disposable-emulator guard: never run against a physical device.
if ($Serial -notlike 'emulator-*') { throw "Refusing to run on ${Serial}: emulators only." }
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\sdk' }
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$serial = $Serial

$deadline = (Get-Date).AddMinutes(10)
$saved = $false
$opened = $false

function Get-Ui {
    $xml = & $adb -s $serial exec-out uiautomator dump /dev/tty 2>$null
    $text = ($xml -join "`n") -replace 'UI hierchary dumped to: /dev/tty', ''
    try { return [xml]$text } catch { return $null }
}

function Tap-Node($node) {
    if ($node.bounds -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
        $x = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
        $y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
        & $adb -s $serial shell input tap $x $y | Out-Null
        return "$x,$y"
    }
}

while ((Get-Date) -lt $deadline -and -not $opened) {
    Start-Sleep -Milliseconds 1500
    $ui = Get-Ui
    if ($null -eq $ui) { continue }

    $nodes = $ui.SelectNodes('//node')
    $packages = ($nodes | ForEach-Object { $_.package } | Select-Object -Unique) -join ','

    if ($packages -notmatch 'documentsui') { continue }

    if (-not $saved) {
        $save = $nodes | Where-Object {
            $_.clickable -eq 'true' -and ($_.text -match '^(SAVE|Save)$')
        } | Select-Object -First 1
        if ($save) { "save_tapped=$(Tap-Node $save)"; $saved = $true; Start-Sleep 3 }
        continue
    }

    $file = $nodes | Where-Object { $_.text -like 'sn42-import-*' } | Select-Object -First 1
    if ($file) {
        "file_tapped=$(Tap-Node $file) name=$($file.text)"
        $opened = $true
        continue
    }

    # Not visible yet: open the Downloads root if the drawer shows it.
    $downloads = $nodes | Where-Object { $_.text -eq 'Downloads' } | Select-Object -First 1
    if ($downloads) { "downloads_tapped=$(Tap-Node $downloads)" }
}

"driver_saved=$saved driver_opened=$opened"
