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
    flutter build apk --release "--dart-define-from-file=$Config" @FlutterArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

    $apk = 'build\app\outputs\flutter-apk\app-release.apk'
    $hash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Output "Built $apk"
    Write-Output "SHA-256 $hash"
}
finally {
    Pop-Location
}
