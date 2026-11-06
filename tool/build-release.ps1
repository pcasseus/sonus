param(
    [string] $Config = (Join-Path $PSScriptRoot '..\config\sonus.dev.json'),
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $FlutterArgs
)

# Builds the release APK with the account settings compiled in. A release
# built without them has no sign-in, so this refuses to build instead.
# Values are checked, never printed.

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
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $commit = "$(git rev-parse --short HEAD 2>$null)".Trim()
        if ($LASTEXITCODE -eq 0 -and $commit) {
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

    flutter build apk --release "--dart-define-from-file=$Config" @buildDefines @FlutterArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

    $apk = 'build\app\outputs\flutter-apk\app-release.apk'
    $hash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Output "Built $apk"
    Write-Output "SHA-256 $hash"
}
finally {
    Pop-Location
}
