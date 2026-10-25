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

## Applied to the platforms

The assets above are applied (UI integration on `2f0f5af`):

- **Android:** launcher, round, adaptive (foreground and `#17191D` background) and Android 13 themed icons in every density; `android:label="Sonus"` and `android:roundIcon`. The package and application ID stay `com.sonus.sonus_next`. SN-44's `drawable/ic_stat_sonus.xml` notification icon and the audio service are unchanged.
- **iOS:** every AppIcon size, rendered from the same mark and stored as opaque RGB (the App Store rejects alpha); `CFBundleDisplayName` is "Sonus".
- **macOS:** `AppIcon.appiconset` from `generated/macos`.
- **Web:** icons, maskable icons and favicon; the manifest name, short name and colours, and the page title.
- **Windows:** `app_icon.ico` (16 to 256 px) and the window title "Sonus".

Left unchanged on purpose:
- **Windows `ProductName`:** it sets the app-data folder `path_provider` uses, so renaming it would hide an existing library. The same goes for the executable name.
- **macOS `PRODUCT_NAME`:** it renames the built `.app`. Both are separate, planned changes.

`test/branding/platform_branding_test.dart` checks all of this.
