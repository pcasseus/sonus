# Sonus branding (SN-48L)

The official Sonus identity, prepared for a coordinated platform hand-off.

- **Display name:** Sonus
- **Package and application ID:** `com.sonus.sonus_next` (unchanged; do not rename)
- **Mark:** the approved Waveform S (`SonusBrandConcept.selected` in `lib/core/design/widgets/sonus_brand_mark.dart`)
- **Colours:** Concrete & Spray. Background `#17191D`, primary `#398BFF`, secondary `#FF4F91`. Themed and monochrome icons use white.

`preview_sheet.png` shows, from the left:
- legacy launcher;
- round launcher;
- adaptive foreground;
- monochrome (themed) layer;
- maskable web icon;
- iOS App Store icon.

## Regenerating

Every asset is rendered from the app's own `SonusBrandMarkPainter`. The icons always match the in-app mark, and no extra package is needed.

```sh
# Check: renders every asset in memory.
flutter test branding/tool/brand_assets_test.dart

# Write the files into branding/generated.
flutter test branding/tool/brand_assets_test.dart --dart-define=SONUS_WRITE_BRAND_ASSETS=true
```

## What is generated (`branding/generated/`)

| Platform | Files |
|---|---|
| Android legacy | `android/mipmap-*/ic_launcher.png`, `ic_launcher_round.png` (48dp at mdpi to xxxhdpi) |
| Android adaptive | `android/mipmap-*/ic_launcher_foreground.png`. The mark is inside the 66dp safe zone of the 108dp layer. |
| Android themed (13+) | `android/mipmap-*/ic_launcher_monochrome.png`: a white mark on transparency |
| Android resources | `android/mipmap-anydpi-v26/ic_launcher.xml`, `ic_launcher_round.xml`, `android/values/ic_launcher_background.xml` |
| Play Store | `android/play_store_512.png` |
| iOS | `ios/AppIcon-1024.png`: opaque, no alpha, as the App Store requires |
| macOS | `macos/app_icon_{16..1024}.png` |
| Web | `web/Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png`, `favicon.png` |
| Windows | `windows/app_icon_256.png` (source for `app_icon.ico`) |

## Integration hand-off (not done here)

Nothing in `android/`, `ios/`, `macos/`, `web/`, `windows/`, `pubspec.yaml` or the app entry point was changed. Those files belong to the SN-44 playback and platform work until they are released. When they are:

1. **Android:**
   - Copy `generated/android/mipmap-*` into `android/app/src/main/res/mipmap-*`.
   - Copy `mipmap-anydpi-v26/` and `values/ic_launcher_background.xml` alongside them.
   - Set `android:label="Sonus"` in `AndroidManifest.xml` and keep `android:icon="@mipmap/ic_launcher"`.
   - Add `android:roundIcon="@mipmap/ic_launcher_round"`.
   - Do **not** replace `drawable/ic_stat_sonus.xml`. It is the media-session notification icon owned by SN-44, which should only be redrawn in coordination with SN-44.
2. **iOS:** set `CFBundleDisplayName` to "Sonus". Generate the AppIcon set from `ios/AppIcon-1024.png` (Xcode's single-size App Icon).
3. **macOS:** fill `AppIcon.appiconset` with `macos/app_icon_*.png` (1x and 2x pairs). Set the product name to Sonus.
4. **Web:** copy `web/*` into `web/` and `web/icons/`. Set `"name"` and `"short_name"` to "Sonus" in `manifest.json`, with `"purpose": "maskable"` on the maskable icons.
5. **Windows:** convert `windows/app_icon_256.png` into `windows/runner/resources/app_icon.ico` (16, 32, 48 and 256 layers).

After integration, verify:
- launcher, round and themed icons on the disposable emulator (Android 13+ themed icons on);
- that the app name reads "Sonus";
- that the package is still `com.sonus.sonus_next`.
