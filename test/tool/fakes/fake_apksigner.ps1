# A stand-in for apksigner: reports the signers registered for an APK's
# SHA-256 in $env:FAKE_APK_DIR.

if ($args[0] -ne 'verify' -or $args[1] -ne '--print-certs') { 'fake apksigner: unsupported'; exit 1 }
$sha = (Get-FileHash $args[2] -Algorithm SHA256).Hash.ToLowerInvariant()
$identity = Get-Content (Join-Path $env:FAKE_APK_DIR "$sha.json") -Raw | ConvertFrom-Json
$number = 1
foreach ($signer in $identity.signers) {
    "Signer #$number certificate DN: CN=Android Debug, O=Android, C=US"
    "Signer #$number certificate SHA-256 digest: $signer"
    $number++
}
exit 0
