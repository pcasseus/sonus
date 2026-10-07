param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $FlutterArgs
)

$ErrorActionPreference = 'Stop'

$config = Join-Path $PSScriptRoot '..\config\sonus.dev.json'

if (-not (Test-Path $config)) {
    Write-Error @"
Missing config\sonus.dev.json.

Copy:
  config\sonus.dev.example.json
to:
  config\sonus.dev.json

Then fill in the development Supabase and Google client configuration.
"@
}

Push-Location (Join-Path $PSScriptRoot '..')

try {
    flutter run `
        --dart-define-from-file="$config" `
        @FlutterArgs
}
finally {
    Pop-Location
}
