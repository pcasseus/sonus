param(
    # The device, exactly as `adb devices` lists it: a USB serial, or the
    # ip:port of Wireless debugging. Never guessed from the connected devices.
    [Parameter(Mandatory)] [string] $Serial,
    # A new folder is created inside it for this run's backup and report.
    [Parameter(Mandatory)] [string] $BackupRoot,
    # The APK to install (from tool\build-release.ps1 or tool\build-qa.ps1).
    [string] $Apk,
    [ValidateSet('com.sonus.sonus_next', 'com.sonus.sonus_next.qa')]
    [string] $Package = 'com.sonus.sonus_next',
    # Back up and check only; nothing is installed. Run it after opening the
    # updated app once, with -Baseline set to the install's report.json.
    [switch] $CheckOnly,
    [string] $Baseline,
    [string] $Ledger,
    [string] $Adb,
    [string] $Aapt,
    [string] $Apksigner,
    [string] $Python = 'python'
)

# Installs a Sonus build over the one on a device, in place, keeping its data
# (App Update 1.2, DEV-20). Works over USB or Wireless debugging.
#
# Before installing, it refuses unless:
# - the device is the one named and is online;
# - the APK is the expected package, has the Sonus artwork provider, is
#   signed by the installed app's certificate, is debuggable (so later
#   backups still work) and was built and recorded by the build scripts;
# - its versionCode is above the installed one (no downgrade);
# - a backup of the app's data was taken, read back identically three
#   times, and the database passed its integrity checks.
#
# It installs only with `adb install -r`. It never uninstalls, clears data or
# downgrades (`-d`). Afterwards it checks that the installed APK is exactly
# this one, the first install time is unchanged, and the database is
# byte-identical to the backup and still passes its checks.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sonus-build-identity.ps1')

if (-not $Ledger) { $Ledger = $SonusDefaultLedger }
if (-not ($Adb -and $Aapt -and $Apksigner)) {
    $tools = Find-SonusBuildTools
    if (-not $Adb) { $Adb = $tools.Adb }
    if (-not $Aapt) { $Aapt = $tools.Aapt }
    if (-not $Apksigner) { $Apksigner = $tools.Apksigner }
}
if (-not $CheckOnly -and -not $Apk) { throw 'Name the APK to install with -Apk (or use -CheckOnly).' }
if ($CheckOnly -and $Apk) { throw '-CheckOnly installs nothing; leave out -Apk.' }
if ($Baseline -and -not $CheckOnly) { throw '-Baseline is for -CheckOnly.' }
if (-not $Serial.Trim()) { throw 'Name the device with -Serial.' }

$checker = Join-Path $PSScriptRoot 'sonus_db_check.py'
$database = 'databases/sonus_next.db'

# Text output of an adb command for this device only.
function Invoke-DeviceAdb {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    # adb reports progress on stderr; read it as text rather than as errors.
    $ErrorActionPreference = 'Continue'
    $output = @(& $Adb -s $Serial @Arguments 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { throw "adb $($Arguments -join ' ') failed ($LASTEXITCODE): $($output -join ' ')" }
    return $output
}

# Binary output of an adb command, written to a file byte for byte
# (PowerShell's pipeline would re-encode it).
function Save-DeviceAdbOutput {
    param([Parameter(Mandatory)] [string[]] $Arguments, [Parameter(Mandatory)] [string] $OutFile)

    $all = @('-s', $Serial) + $Arguments
    $start = New-Object Diagnostics.ProcessStartInfo
    if ($Adb -like '*.ps1') {
        # A script stand-in for adb (tests): each argument is passed as a
        # quoted literal, so values such as '-' are never read as options.
        $literals = ($all | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ' '
        $command = "& '$($Adb -replace "'", "''")' $literals; exit `$LASTEXITCODE"
        $start.FileName = 'powershell.exe'
        $start.Arguments = '-NoProfile -ExecutionPolicy Bypass -EncodedCommand ' +
            [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    }
    else {
        $start.FileName = $Adb
        $start.Arguments = ($all | ForEach-Object { if ($_ -match '[\s"]' -or -not $_) { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    }
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    $errors = $process.StandardError.ReadToEndAsync()
    $file = [IO.File]::Create($OutFile)
    try { $process.StandardOutput.BaseStream.CopyTo($file) } finally { $file.Dispose() }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "adb $($Arguments -join ' ') failed ($($process.ExitCode)): $($errors.Result)" }
}

function Get-Sha256 { param([string] $Path) (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Get-InstalledState {
    $dump = (Invoke-DeviceAdb @('shell', 'dumpsys', 'package', $Package)) -join "`n"
    if ($dump -notmatch "Package \[$([regex]::Escape($Package))\]") {
        throw "$Package is not installed on $Serial. This script only updates an installed app; it never installs one fresh."
    }
    $code = [regex]::Match($dump, 'versionCode=(\d+)')
    $first = [regex]::Match($dump, 'firstInstallTime=([^\r\n]+)')
    if (-not ($code.Success -and $first.Success)) { throw "Could not read $Package's versionCode and first install time." }
    [pscustomobject]@{
        VersionCode      = [long]$code.Groups[1].Value
        FirstInstallTime = $first.Groups[1].Value.Trim()
        LastUpdateTime   = [regex]::Match($dump, 'lastUpdateTime=([^\r\n]+)').Groups[1].Value.Trim()
        Debuggable       = $dump -match 'pkgFlags=\[[^\]]*\bDEBUGGABLE\b'
    }
}

# Pulls the installed APK and returns its local copy.
function Save-InstalledApk {
    param([string] $OutFile)
    $paths = @(Invoke-DeviceAdb @('shell', 'pm', 'path', $Package) | Where-Object { $_ -match '^package:.*/base\.apk$' })
    if ($paths.Count -ne 1) { throw "Could not find $Package's installed APK." }
    Invoke-DeviceAdb @('pull', ($paths[0] -replace '^package:', ''), $OutFile) | Out-Null
    return $OutFile
}

# Copies the database three times; the copies must be identical. Returns the
# first copy, its SHA-256 and what the checker reads in it.
function Save-Database {
    param([string] $Folder, [string] $Prefix)

    $listing = (Invoke-DeviceAdb @('shell', 'run-as', $Package, 'ls', '-l', 'databases')) -join "`n"
    if ($listing -notmatch '\ssonus_next\.db\s*(\n|$)') { throw "$Package has no database to back up." }
    if ($listing -match 'sonus_next\.db-wal') { throw 'The database has a write-ahead log; Sonus does not use one. Stopping.' }
    $journal = [regex]::Match($listing, '\s(\d+)\s+\S+\s+\S+\s+sonus_next\.db-journal')
    if ($journal.Success -and [long]$journal.Groups[1].Value -gt 0) {
        throw 'The database has an unfinished transaction (non-empty journal). Open and close Sonus, then try again.'
    }

    $copies = foreach ($letter in 'a', 'b', 'c') {
        $copy = Join-Path $Folder "$Prefix-db-$letter.db"
        Save-DeviceAdbOutput @('exec-out', 'run-as', $Package, 'cat', $database) $copy
        $copy
    }
    $hashes = @($copies | ForEach-Object { Get-Sha256 $_ } | Select-Object -Unique)
    if ($hashes.Count -ne 1) { throw 'The three database copies differ; the app may still be writing. Nothing was installed.' }
    if ((Get-Item $copies[0]).Length -eq 0) { throw 'The database copy is empty. Nothing was installed.' }

    $checked = (& $Python -I $checker $copies[0]) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "The database check could not read the copy: $checked" }
    $report = $checked | ConvertFrom-Json
    if ((@($report.integrity_check) -join ',') -ne 'ok') { throw "The database failed its integrity check: $(@($report.integrity_check) -join '; ')" }
    if ($report.foreign_key_violations -ne 0) { throw "The database has $($report.foreign_key_violations) foreign-key violations." }

    [pscustomobject]@{ Copy = $copies[0]; Sha256 = $hashes[0]; Check = $report }
}

function Assert-NoRowsLost {
    param($Before, $After)
    if ($After.user_version -lt $Before.user_version) {
        throw "The schema went back from version $($Before.user_version) to $($After.user_version)."
    }
    foreach ($table in $Before.counts.PSObject.Properties.Name) {
        $was = $Before.counts.$table
        $now = $After.counts.$table
        if ($null -eq $now -or $now -lt $was) { throw "$table has fewer rows than before ($was -> $now)." }
    }
}

# 1. The device.
$ErrorActionPreference = 'Continue'
$devices = @(& $Adb devices 2>&1 | ForEach-Object { "$_" })
$ErrorActionPreference = 'Stop'
$listed = @($devices | Where-Object { $_ -match "^$([regex]::Escape($Serial))\s+(\S+)" } | ForEach-Object { ($_ -split '\s+')[1] })
if ($listed.Count -ne 1 -or $listed[0] -ne 'device') {
    throw "Device $Serial is not connected and authorised (adb devices: $($devices -join '; '))."
}
$model = (Invoke-DeviceAdb @('shell', 'getprop', 'ro.product.model')) -join ''

$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$folder = Join-Path $BackupRoot "$(if ($CheckOnly) { 'check' } else { 'install' })-$Package-$stamp"
New-Item -ItemType Directory -Path $folder | Out-Null
Write-Output "Device $Serial ($model); package $Package; backup folder $folder"

# 2. The APK.
$identity = $null
if (-not $CheckOnly) {
    $identity = Get-SonusApkIdentity -Apk $Apk -Aapt $Aapt -Apksigner $Apksigner
    Assert-SonusApkIdentity -Identity $identity -Package $Package
    if (-not $identity.Debuggable) {
        throw 'The APK is not debuggable. After installing it, backups through adb run-as would stop working; that switch needs its own approval.'
    }
    $flavor = if ($Package -like '*.qa') { 'qa' } else { 'prod' }
    $record = @(Read-SonusLedger -Ledger $Ledger | Where-Object {
            $_.Status -eq 'built' -and $_.Sha256 -eq $identity.Sha256 -and $_.VersionCode -eq $identity.VersionCode -and $_.Flavor -eq $flavor
        })
    if ($record.Count -ne 1) { throw "The APK (SHA-256 $($identity.Sha256)) is not a recorded $flavor build in $Ledger." }
    Write-Output "APK versionCode $($identity.VersionCode), commit $($record[0].Commit), SHA-256 $($identity.Sha256)"
}

# 3. The installed app.
$installed = Get-InstalledState
if (-not $installed.Debuggable) { throw "The installed $Package is not debuggable, so its data cannot be backed up with adb run-as." }
$installedApk = Save-InstalledApk (Join-Path $folder 'installed_base.apk')
$installedIdentity = Get-SonusApkIdentity -Apk $installedApk -Aapt $Aapt -Apksigner $Apksigner
if ((@($installedIdentity.Signers) -join ',') -ne $SonusSignerSha256) {
    throw "The installed app is signed by $(@($installedIdentity.Signers) -join ', '), not the Sonus certificate. Stopping."
}
Write-Output "Installed versionCode $($installed.VersionCode); first installed $($installed.FirstInstallTime)"
if ($identity -and $identity.VersionCode -le $installed.VersionCode) {
    throw "The APK's versionCode $($identity.VersionCode) is not above the installed $($installed.VersionCode). Downgrades are never installed."
}

# 4. Backup and checks.
Invoke-DeviceAdb @('shell', 'am', 'force-stop', $Package) | Out-Null
$before = Save-Database -Folder $folder -Prefix 'before'
Save-DeviceAdbOutput @('exec-out', 'run-as', $Package, 'tar', '-cf', '-', '.') (Join-Path $folder 'app_data.tar')
if ((Get-Item (Join-Path $folder 'app_data.tar')).Length -eq 0) { throw 'The app data archive is empty. Nothing was installed.' }

$report = [ordered]@{
    serial = $Serial; model = $model; package = $Package; mode = $(if ($CheckOnly) { 'check' } else { 'install' })
    installed_before = $installed
    database_sha256 = $before.Sha256; database = $before.Check
    app_data_sha256 = Get-Sha256 (Join-Path $folder 'app_data.tar')
    installed_apk_sha256 = $installedIdentity.Sha256
}
function Save-Report { $report | ConvertTo-Json -Depth 6 | ForEach-Object { [IO.File]::WriteAllText((Join-Path $folder 'report.json'), $_, [Text.UTF8Encoding]::new($false)) } }
Save-Report
Write-Output "Backup ok: schema v$($before.Check.user_version), integrity ok, database $($before.Sha256)"

if ($CheckOnly) {
    if ($Baseline) {
        $baselineReport = Get-Content $Baseline -Raw | ConvertFrom-Json
        Assert-NoRowsLost -Before $baselineReport.database -After $before.Check
        Write-Output "No rows lost since $Baseline (schema v$($baselineReport.database.user_version) -> v$($before.Check.user_version))."
    }
    Write-Output 'Check complete. Nothing was installed.'
    return
}

# 5. Install in place.
$result = (Invoke-DeviceAdb @('install', '-r', $Apk)) -join "`n"
if ($result -notmatch '(^|\n)Success\s*$') { throw "adb install did not report Success: $result" }

# 6. After.
$after = Get-InstalledState
if ($after.VersionCode -ne $identity.VersionCode) { throw "The device reports versionCode $($after.VersionCode), not $($identity.VersionCode)." }
if ($after.FirstInstallTime -ne $installed.FirstInstallTime) {
    throw "The first install time changed ($($installed.FirstInstallTime) -> $($after.FirstInstallTime)): the app was not updated in place. Restore from $folder."
}
$afterApk = Save-InstalledApk (Join-Path $folder 'installed_after.apk')
if ((Get-Sha256 $afterApk) -ne $identity.Sha256) { throw 'The installed APK is not the one given.' }
Remove-Item $afterApk
$afterDb = Save-Database -Folder $folder -Prefix 'after'
if ($afterDb.Sha256 -ne $before.Sha256) { throw 'The database changed during the install. Restore from the backup in this folder.' }
Get-ChildItem $folder -Filter 'after-db-*.db' | Remove-Item

$report.installed_after = $after
$report.apk_sha256 = $identity.Sha256
Save-Report
Write-Output "Installed versionCode $($after.VersionCode) in place; first install time kept; data unchanged."
Write-Output "Next: open Sonus once (it upgrades its database on first launch), then run this script with -CheckOnly -Baseline `"$(Join-Path $folder 'report.json')`"."
