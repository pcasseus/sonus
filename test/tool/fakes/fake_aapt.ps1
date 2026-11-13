# A stand-in for aapt: reports the identity registered for an APK's SHA-256
# in $env:FAKE_APK_DIR.

$apk = $args[2]
$sha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
$identity = Get-Content (Join-Path $env:FAKE_APK_DIR "$sha.json") -Raw | ConvertFrom-Json

if ($args[0] -eq 'dump' -and $args[1] -eq 'badging') {
    "package: name='$($identity.package)' versionCode='$($identity.versionCode)' versionName='1.0.0'"
    if ($identity.debuggable) { 'application-debuggable' }
    exit 0
}
if ($args[0] -eq 'dump' -and $args[1] -eq 'xmltree') {
    foreach ($authority in $identity.authorities) {
        "        A: android:authorities(0x01010018)=`"$authority`" (Raw: `"$authority`")"
    }
    exit 0
}
"fake aapt: unsupported"
exit 1
