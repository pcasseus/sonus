import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// The official Waveform S branding on the platform folders, and what it
// must never change.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Width, height and PNG colour type (2 = RGB, 6 = RGBA).
  (int, int, int) pngHeader(String path) {
    final bytes = File(path).readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    return (data.getUint32(16), data.getUint32(20), bytes[25]);
  }

  test('Android shows "Sonus" with launcher, round, adaptive and themed '
      'icons', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:label="Sonus"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));

    const res = 'android/app/src/main/res';
    for (final bucket in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      for (final name in [
        'ic_launcher',
        'ic_launcher_round',
        'ic_launcher_foreground',
        'ic_launcher_monochrome',
      ]) {
        expect(File('$res/mipmap-$bucket/$name.png').existsSync(), isTrue);
      }
    }
    final adaptive = read('$res/mipmap-anydpi-v26/ic_launcher.xml');
    expect(adaptive, contains('@mipmap/ic_launcher_monochrome'));
    expect(read('$res/values/ic_launcher_background.xml'), contains('#17191D'));
  });

  test('the package, playback service and notification icon are kept', () {
    final gradle = read('android/app/build.gradle.kts');
    expect(gradle, contains('applicationId = "com.sonus.sonus_next"'));
    expect(gradle, contains('namespace = "com.sonus.sonus_next"'));

    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('com.ryanheise.audioservice.AudioService'));
    expect(manifest, contains('android:foregroundServiceType="mediaPlayback"'));
    // SN-44's media notification icon is its own resource.
    expect(
      File('android/app/src/main/res/drawable/ic_stat_sonus.xml').existsSync(),
      isTrue,
    );
  });

  test('iOS shows "Sonus" and its icons are opaque (App Store)', () {
    expect(read('ios/Runner/Info.plist'), contains('<string>Sonus</string>'));

    final icons = Directory(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.png'));
    expect(icons, hasLength(15));
    for (final icon in icons) {
      final (_, _, colorType) = pngHeader(icon.path);
      expect(colorType, 2, reason: '${icon.path} must have no alpha');
    }
    final (width, height, _) = pngHeader(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
    );
    expect((width, height), (1024, 1024));
  });

  test('web uses the Sonus name, colours and icons', () {
    final manifest = read('web/manifest.json');
    expect(manifest, contains('"name": "Sonus"'));
    expect(manifest, contains('"theme_color": "#17191D"'));
    expect(read('web/index.html'), contains('<title>Sonus</title>'));
    expect(pngHeader('web/icons/Icon-512.png').$1, 512);
  });

  test('Windows has the Sonus icon and title, and keeps its data folder', () {
    final ico = File('windows/runner/resources/app_icon.ico').readAsBytesSync();
    final header = ByteData.sublistView(ico);
    expect(header.getUint16(2, Endian.little), 1, reason: 'icon type');
    expect(header.getUint16(4, Endian.little), greaterThanOrEqualTo(4));
    // The largest layer is 256px (stored as 0).
    final sizes = [
      for (var i = 0; i < header.getUint16(4, Endian.little); i++)
        ico[6 + i * 16],
    ];
    expect(sizes, contains(0));

    expect(read('windows/runner/main.cpp'), contains('L"Sonus"'));
    // The version resource names the app-data folder; renaming it would
    // hide an existing library, so it stays.
    final rc = read('windows/runner/Runner.rc');
    expect(rc, contains('VALUE "ProductName", "sonus_next"'));
    expect(
      read('windows/CMakeLists.txt'),
      contains('set(BINARY_NAME "sonus_next")'),
    );
  });
}
