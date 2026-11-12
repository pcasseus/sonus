param(
    [string] $Config = (Join-Path $PSScriptRoot '..\config\sonus.dev.json'),
    # debug is the debuggable build the phone runs today (backups use
    # `adb run-as`, which needs it); release is not debuggable.
    [ValidateSet('release', 'debug')] [string] $Mode = 'release',
    [string] $Ledger,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $FlutterArgs
)

# Builds the real app's APK (prod flavor) with the account settings compiled
# in. A build without them has no sign-in, so this refuses to build instead.
# Values are checked, never printed.
#
# Every build gets a new, higher versionCode reserved in the build ledger
# (tool\sonus-build-identity.ps1), and the APK is refused unless its package,
# versionCode, artwork provider and signing certificate are the expected
# ones. The SHA-256 is recorded in the ledger for tool\install-device.ps1.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sonus-build-identity.ps1')
if (-not $Ledger) { $Ledger = $SonusDefaultLedger }
$tools = Find-SonusBuildTools

if (-not (Test-Path $Config)) {
    throw "Missing $Config. Copy config\sonus.dev.example.json to it and fill in the Supabase URL, the Supabase publishable key and the Google web client ID."
}

$settings = Get-Content $Config -Raw | ConvertFrom-Json
foreach ($name in 'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'GOOGLE_WEB_CLIENT_ID') {
    $value = "$($settings.$name)".Trim()
    if (-not $value -or $value -eq 'REPLACE_ME') {
        throw "$name is not set in $Config; sign-in would be off in this build."
    }
}

# Only the publishable key belongs in an app. A secret or service-role key
# would give anyone with the APK full access to the project.
$key = "$($settings.SUPABASE_PUBLISHABLE_KEY)".Trim()
if ($key.StartsWith('sb_secret_') -or $key -match 'service_role') {
    throw 'SUPABASE_PUBLISHABLE_KEY looks like a secret or service-role key. Use the publishable key.'
}
if (-not "$($settings.GOOGLE_WEB_CLIENT_ID)".Trim().EndsWith('.apps.googleusercontent.com')) {
    throw 'GOOGLE_WEB_CLIENT_ID should be the Web client ID (ends with .apps.googleusercontent.com).'
}

Push-Location (Join-Path $PSScriptRoot '..')
try {
    # Build identity, shown in Settings > About. Without Git the app says
    # the commit was not recorded instead of guessing.
    $buildDefines = @()
    $commit = 'unrecorded'
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $head = "$(git rev-parse --short HEAD 2>$null)".Trim()
        if ($LASTEXITCODE -eq 0 -and $head) {
            $commit = $head
            $changes = "$(git status --porcelain 2>$null)".Trim()
            if ($changes) { $commit = "$commit-dirty" }
            $buildDefines += "--dart-define=SONUS_BUILD_COMMIT=$commit"
            Write-Output "Build commit $commit"
        }
        else {
            Write-Warning 'Git did not report a commit; the build commit will show as not recorded.'
        }
    }
    else {
        Write-Warning 'Git is not available; the build commit will show as not recorded.'
    }
    $buildTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $buildDefines += "--dart-define=SONUS_BUILD_TIME=$buildTime"

    $versionCode = New-SonusVersionCode -Flavor prod -Commit $commit -Ledger $Ledger
    Write-Output "versionCode $versionCode (reserved in $Ledger)"

    # The real app is the prod flavor (com.sonus.sonus_next); the QA
    # install has its own script, tool\build-qa.ps1.
    flutter build apk "--$Mode" --flavor prod "--build-number=$versionCode" "--dart-define-from-file=$Config" @buildDefines @FlutterArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

    $apk = "build\app\outputs\flutter-apk\app-prod-$Mode.apk"
    $identity = Get-SonusApkIdentity -Apk $apk -Aapt $tools.Aapt -Apksigner $tools.Apksigner
    Assert-SonusApkIdentity -Identity $identity -Package 'com.sonus.sonus_next' -VersionCode $versionCode
    Add-SonusBuildRecord -VersionCode $versionCode -Flavor prod -Sha256 $identity.Sha256 -Ledger $Ledger
    Write-Output "Built $apk"
    Write-Output "Package com.sonus.sonus_next; versionCode $versionCode; debuggable $($identity.Debuggable); signer $SonusSignerSha256"
    Write-Output "SHA-256 $($identity.Sha256)"
}
finally {
    Pop-Location
}
