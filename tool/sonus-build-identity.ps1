# Build identity shared by tool\build-release.ps1, tool\build-qa.ps1 and
# tool\install-device.ps1 (App Update 1.2, DEV-20). Dot-source it.
#
# versionCode = whole minutes since 2026-01-01 00:00 UTC at build time.
# - Android accepts 1..2,100,000,000; this stays below that until about
#   year 5990. Every earlier Sonus build is versionCode 1, so codes start
#   far above it.
# - Build time only moves forward, so codes keep their order across
#   branches and worktrees (a commit count would not).
# - Two builds in the same minute, or a PC clock set back, would repeat or
#   lower a code. The ledger stops both: every code is reserved there under
#   an exclusive file lock before the build, and a code that is not above
#   every recorded code is refused.
#
# The ledger lives outside every worktree (one per Windows user), so all
# worktrees on this PC share it.

$SonusVersionEpochUtc = [DateTime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
$SonusMaxVersionCode = 2100000000
$SonusDefaultLedger = Join-Path $env:LOCALAPPDATA 'Sonus\build-ledger.csv'

# The certificate every installed Sonus build is signed with (the Android
# debug key of this PC). Not a secret: it is in every APK. A build signed
# with anything else could not update the installed app without wiping it.
$SonusSignerSha256 = '92dd91c7be6e2de9d3f98b62fb61802fc2eb12ce548116a632b119a3a30776ab'

$SonusLedgerHeader = 'version_code,status,flavor,commit,sha256,recorded_utc'

function Get-SonusVersionCode {
    param([Parameter(Mandatory)] [DateTime] $UtcNow)

    $minutes = [Math]::Floor(($UtcNow.ToUniversalTime() - $SonusVersionEpochUtc).TotalMinutes)
    if ($minutes -le 1) {
        throw "The PC clock says $($UtcNow.ToUniversalTime().ToString('u')), before Sonus versionCodes begin (2026-01-01 UTC). Check the clock."
    }
    if ($minutes -gt $SonusMaxVersionCode) {
        throw "versionCode $minutes is above Android's limit ($SonusMaxVersionCode)."
    }
    return [long]$minutes
}

# Runs $Action with the ledger open exclusively. Another build holding it is
# waited for (up to about 30 seconds), never ignored.
function Use-SonusLedger {
    param(
        [Parameter(Mandatory)] [string] $Ledger,
        [Parameter(Mandatory)] [scriptblock] $Action
    )

    $folder = Split-Path $Ledger -Parent
    if ($folder -and -not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $stream = $null
    for ($attempt = 1; -not $stream; $attempt++) {
        try {
            $stream = [IO.File]::Open($Ledger, 'OpenOrCreate', 'ReadWrite', 'None')
        }
        catch [IO.IOException] {
            if ($attempt -ge 60) { throw "The build ledger $Ledger stayed locked by another build." }
            Start-Sleep -Milliseconds 500
        }
    }
    try {
        $reader = New-Object IO.StreamReader($stream, [Text.UTF8Encoding]::new($false), $false, 4096, $true)
        $text = $reader.ReadToEnd()
        $reader.Dispose()
        $rows = @(ConvertFrom-SonusLedger $text $Ledger)

        $stream.Seek(0, 'End') | Out-Null
        $writer = New-Object IO.StreamWriter($stream, [Text.UTF8Encoding]::new($false), 4096, $true)
        try {
            if ($stream.Length -eq 0) { $writer.WriteLine($SonusLedgerHeader) }
            & $Action $rows $writer
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function ConvertFrom-SonusLedger {
    param([string] $Text, [string] $Ledger)

    $lines = @($Text -split "`r?`n" | Where-Object { $_ })
    if (-not $lines) { return }
    if ($lines[0] -ne $SonusLedgerHeader) { throw "$Ledger is not a Sonus build ledger." }
    foreach ($line in $lines | Select-Object -Skip 1) {
        $f = $line.Split(',')
        if ($f.Count -ne 6 -or $f[0] -notmatch '^\d+$') { throw "$Ledger has an unreadable line: $line" }
        [pscustomobject]@{
            VersionCode = [long]$f[0]; Status = $f[1]; Flavor = $f[2]
            Commit = $f[3]; Sha256 = $f[4]; RecordedUtc = $f[5]
        }
    }
}

function Read-SonusLedger {
    param([string] $Ledger = $SonusDefaultLedger)

    if (-not (Test-Path $Ledger)) { return }
    ConvertFrom-SonusLedger (Get-Content $Ledger -Raw) $Ledger
}

# Reserves the versionCode for a build starting now and returns it.
function New-SonusVersionCode {
    param(
        [Parameter(Mandatory)] [ValidateSet('prod', 'qa')] [string] $Flavor,
        [Parameter(Mandatory)] [string] $Commit,
        [string] $Ledger = $SonusDefaultLedger,
        [DateTime] $UtcNow = [DateTime]::UtcNow
    )

    if ($Commit -match '[,\r\n]') { throw "Commit '$Commit' cannot be recorded." }
    $code = Get-SonusVersionCode -UtcNow $UtcNow
    Use-SonusLedger -Ledger $Ledger -Action {
        param($rows, $writer)
        $highest = ($rows | Measure-Object VersionCode -Maximum).Maximum
        if ($null -ne $highest -and $code -le $highest) {
            throw "versionCode $code is not above the highest recorded ($highest) in $Ledger. Wait until the next minute, or check the PC clock."
        }
        $writer.WriteLine("$code,reserved,$Flavor,$Commit,,$($UtcNow.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))")
    }
    return $code
}

# Records the APK built under a reserved code.
function Add-SonusBuildRecord {
    param(
        [Parameter(Mandatory)] [long] $VersionCode,
        [Parameter(Mandatory)] [ValidateSet('prod', 'qa')] [string] $Flavor,
        [Parameter(Mandatory)] [ValidatePattern('^[0-9a-f]{64}$')] [string] $Sha256,
        [string] $Ledger = $SonusDefaultLedger
    )

    Use-SonusLedger -Ledger $Ledger -Action {
        param($rows, $writer)
        $reserved = @($rows | Where-Object { $_.VersionCode -eq $VersionCode -and $_.Status -eq 'reserved' -and $_.Flavor -eq $Flavor })
        if ($reserved.Count -ne 1) { throw "versionCode $VersionCode ($Flavor) was not reserved in $Ledger." }
        if ($rows | Where-Object { $_.VersionCode -eq $VersionCode -and $_.Status -eq 'built' }) {
            throw "versionCode $VersionCode already has a build recorded in $Ledger."
        }
        $writer.WriteLine("$VersionCode,built,$Flavor,$($reserved[0].Commit),$Sha256,$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
    }
}

# What aapt and apksigner say about an APK.
function Get-SonusApkIdentity {
    param(
        [Parameter(Mandatory)] [string] $Apk,
        [Parameter(Mandatory)] [string] $Aapt,
        [Parameter(Mandatory)] [string] $Apksigner
    )

    $badging = @(& $Aapt dump badging $Apk)
    if ($LASTEXITCODE -ne 0) { throw "aapt could not read $Apk." }
    $package = [regex]::Match(($badging -join "`n"), "package: name='([^']+)' versionCode='(\d+)'")
    if (-not $package.Success) { throw "aapt reported no package for $Apk." }

    $manifest = (@(& $Aapt dump xmltree $Apk AndroidManifest.xml) -join "`n")
    $authorities = @([regex]::Matches($manifest, 'android:authorities\([^)]*\)="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })

    $certs = (@(& $Apksigner verify --print-certs $Apk) -join "`n")
    if ($LASTEXITCODE -ne 0) { throw "apksigner could not verify $Apk." }
    $signers = @([regex]::Matches($certs, 'certificate SHA-256 digest: ([0-9a-f]{64})') | ForEach-Object { $_.Groups[1].Value })

    [pscustomobject]@{
        Package     = $package.Groups[1].Value
        VersionCode = [long]$package.Groups[2].Value
        Debuggable  = [bool]($badging -match '^application-debuggable')
        Authorities = $authorities
        Signers     = $signers
        Sha256      = (Get-FileHash $Apk -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

# Refuses an APK whose package, versionCode, artwork provider or signer is
# not the expected one.
function Assert-SonusApkIdentity {
    param(
        [Parameter(Mandatory)] $Identity,
        [Parameter(Mandatory)] [string] $Package,
        [long] $VersionCode = 0
    )

    if ($Identity.Package -ne $Package) { throw "The APK is package '$($Identity.Package)', not $Package." }
    if ($VersionCode -and $Identity.VersionCode -ne $VersionCode) {
        throw "The APK has versionCode $($Identity.VersionCode), not $VersionCode."
    }
    if (@($Identity.Authorities) -notcontains "$Package.artwork") {
        throw "The APK's artwork provider is not $Package.artwork."
    }
    if (@($Identity.Signers).Count -ne 1 -or $Identity.Signers[0] -ne $SonusSignerSha256) {
        throw "The APK is not signed only by the Sonus certificate ($SonusSignerSha256); it could not update the installed app."
    }
}

function Find-SonusBuildTools {
    $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    $buildTools = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory |
        Sort-Object { [version]$_.Name } | Select-Object -Last 1
    $tools = [pscustomobject]@{
        Aapt      = Join-Path $buildTools.FullName 'aapt.exe'
        Apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
        Adb       = Join-Path $sdk 'platform-tools\adb.exe'
    }
    foreach ($path in $tools.Aapt, $tools.Apksigner) {
        if (-not (Test-Path $path)) { throw "$path not found." }
    }
    return $tools
}
