param(
    [string] $Ledger,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $FlutterArgs
)

# Builds the isolated QA install of Sonus (App Update 1.2 device QA):
# package com.sonus.sonus_next.qa, "Sonus QA", beside the real app.
#
# - Profile mode: compiled ahead of time like a release (timings are real)
#   and debuggable, so its own data can be read with `adb run-as`.
# - No account settings: sign-in, sync and cloud backup are off, so it can
#   never reach the cloud. The build is refused if any are found in it.
#
# It never builds, installs or touches the real app (the prod flavor).
#
# Like the real app, every build gets a new, higher versionCode from the
# shared build ledger (tool\sonus-build-identity.ps1).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sonus-build-identity.ps1')
if (-not $Ledger) { $Ledger = $SonusDefaultLedger }

$expectedPackage = 'com.sonus.sonus_next.qa'
$expectedAuthority = "$expectedPackage.artwork"

$tools = Find-SonusBuildTools
$aapt = $tools.Aapt

Push-Location (Join-Path $PSScriptRoot '..')
try {
    $buildDefines = @()
    $commit = 'unrecorded'
    $head = "$(git rev-parse --short HEAD 2>$null)".Trim()
    if ($LASTEXITCODE -eq 0 -and $head) {
        $commit = $head
        if ("$(git status --porcelain 2>$null)".Trim()) { $commit = "$commit-dirty" }
        $buildDefines += "--dart-define=SONUS_BUILD_COMMIT=$commit"
        Write-Output "Build commit $commit"
    }
    $buildDefines += "--dart-define=SONUS_BUILD_TIME=$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"

    $versionCode = New-SonusVersionCode -Flavor qa -Commit $commit -Ledger $Ledger
    Write-Output "versionCode $versionCode (reserved in $Ledger)"

    # Deliberately no --dart-define-from-file: no account settings.
    flutter build apk --profile --flavor qa "--build-number=$versionCode" @buildDefines @FlutterArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

    $apk = 'build\app\outputs\flutter-apk\app-qa-profile.apk'

    # The package and the artwork provider must be the QA ones.
    $badging = & $aapt dump badging $apk
    $package = ($badging | Select-String "^package: name='([^']+)'").Matches[0].Groups[1].Value
    if ($package -ne $expectedPackage) { throw "Package is '$package', not $expectedPackage." }
    $manifest = (& $aapt dump xmltree $apk AndroidManifest.xml) -join "`n"
    if ($manifest -notmatch [regex]::Escape("`"$expectedAuthority`"")) {
        throw "The artwork provider authority is not $expectedAuthority."
    }
    if ($manifest -match '"com\.sonus\.sonus_next\.artwork"') {
        throw 'The real app''s artwork authority is in the QA build.'
    }

    # No account settings compiled in.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $apk))
    try {
        foreach ($entry in $zip.Entries | Where-Object { $_.FullName -like 'lib/*/libapp.so' }) {
            $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::GetEncoding(28591))
            $text = $reader.ReadToEnd()
            $reader.Close()
            # A Supabase project URL, a Google client ID, or an actual
            # publishable key. The bare prefix 'sb_publishable_' is in the
            # Supabase library's own code, so a key needs characters after it.
            $patterns = '\.supabase\.co', '\.apps\.googleusercontent\.com', 'sb_publishable_[A-Za-z0-9_-]{20,}'
            foreach ($pattern in $patterns) {
                if ($text -match $pattern) { throw "The QA build contains account settings ($pattern in $($entry.FullName))." }
            }
        }
    }
    finally {
        $zip.Dispose()
    }

    $identity = Get-SonusApkIdentity -Apk $apk -Aapt $tools.Aapt -Apksigner $tools.Apksigner
    Assert-SonusApkIdentity -Identity $identity -Package $expectedPackage -VersionCode $versionCode
    Add-SonusBuildRecord -VersionCode $versionCode -Flavor qa -Sha256 $identity.Sha256 -Ledger $Ledger
    Write-Output "Built $apk"
    Write-Output "Package $package; versionCode $versionCode; artwork provider $expectedAuthority; no account settings"
    Write-Output "SHA-256 $($identity.Sha256)"
}
finally {
    Pop-Location
}
