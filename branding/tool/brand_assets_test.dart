// Renders the official Sonus launcher assets from the Waveform S brand mark
// (SN-48L). It uses the app's own SonusBrandMarkPainter and Flutter's
// renderer, so the icons always match the in-app mark and no extra package
// is needed.
//
// Check (renders every asset in memory):
//   flutter test branding/tool/brand_assets_test.dart
// Write the files into branding/generated:
//   flutter test branding/tool/brand_assets_test.dart --dart-define=SONUS_WRITE_BRAND_ASSETS=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/widgets/sonus_brand_mark.dart';

const bool _write = bool.fromEnvironment('SONUS_WRITE_BRAND_ASSETS');

/// Brand colours: Concrete & Spray, the default theme.
final _palette = SonusThemeCatalog.of(SonusThemeId.concreteSpray).palette;
final Color brandBackground = _palette.background;
final Color brandPrimary = _palette.primary;
final Color brandSecondary = _palette.secondary;

enum _Shape { square, roundedSquare, circle, none }

class _Asset {
  const _Asset(
    this.path,
    this.size, {
    this.shape = _Shape.roundedSquare,
    this.markScale = 0.62,
    this.monochrome = false,
    this.opaque = false,
  });

  final String path;
  final int size;
  final _Shape shape;

  /// The mark's share of the canvas.
  final double markScale;

  /// White mark on transparency, for Android 13 themed icons.
  final bool monochrome;

  /// No transparency at all (iOS App Store icon).
  final bool opaque;
}

/// Android density buckets and their launcher sizes (48dp legacy icon,
/// 108dp adaptive layers).
const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

List<_Asset> _assets() => [
  for (final MapEntry(key: bucket, value: scale) in _densities.entries) ...[
    _Asset('android/mipmap-$bucket/ic_launcher.png', (48 * scale).round()),
    _Asset(
      'android/mipmap-$bucket/ic_launcher_round.png',
      (48 * scale).round(),
      shape: _Shape.circle,
    ),
    // Adaptive layers: the mark stays inside the central 66dp safe zone.
    _Asset(
      'android/mipmap-$bucket/ic_launcher_foreground.png',
      (108 * scale).round(),
      shape: _Shape.none,
      markScale: 0.52,
    ),
    _Asset(
      'android/mipmap-$bucket/ic_launcher_monochrome.png',
      (108 * scale).round(),
      shape: _Shape.none,
      markScale: 0.52,
      monochrome: true,
    ),
  ],
  const _Asset('android/play_store_512.png', 512, shape: _Shape.square),
  const _Asset(
    'ios/AppIcon-1024.png',
    1024,
    shape: _Shape.square,
    opaque: true,
  ),
  for (final size in const [16, 32, 64, 128, 256, 512, 1024])
    _Asset('macos/app_icon_$size.png', size),
  const _Asset('web/Icon-192.png', 192),
  const _Asset('web/Icon-512.png', 512),
  const _Asset(
    'web/Icon-maskable-192.png',
    192,
    shape: _Shape.square,
    markScale: 0.5,
  ),
  const _Asset(
    'web/Icon-maskable-512.png',
    512,
    shape: _Shape.square,
    markScale: 0.5,
  ),
  const _Asset('web/favicon.png', 32),
  const _Asset('windows/app_icon_256.png', 256),
];

Future<ui.Image> _render(_Asset asset) async {
  final size = asset.size.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

  if (asset.opaque) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size),
      Paint()..color = brandBackground,
    );
  }

  final background = Paint()..color = brandBackground;
  switch (asset.shape) {
    case _Shape.square:
      canvas.drawRect(Rect.fromLTWH(0, 0, size, size), background);
    case _Shape.roundedSquare:
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size, size),
          Radius.circular(size * 0.22),
        ),
        background,
      );
    case _Shape.circle:
      canvas.drawCircle(Offset(size / 2, size / 2), size / 2, background);
    case _Shape.none:
      break;
  }

  final markSize = size * asset.markScale;
  canvas.save();
  canvas.translate((size - markSize) / 2, (size - markSize) / 2);
  SonusBrandMarkPainter(
    concept: SonusBrandConcept.selected,
    primary: asset.monochrome ? Colors.white : brandPrimary,
    secondary: asset.monochrome ? Colors.white : brandSecondary,
  ).paint(canvas, Size.square(markSize));
  canvas.restore();

  return recorder.endRecording().toImage(asset.size, asset.size);
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Resource files for the Android adaptive icon (API 26+, themed on 33+).
Map<String, String> _resources() => {
  'android/mipmap-anydpi-v26/ic_launcher.xml':
      '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
''',
  'android/mipmap-anydpi-v26/ic_launcher_round.xml':
      '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
''',
  'android/values/ic_launcher_background.xml':
      '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">${_hex(brandBackground)}</color>
</resources>
''',
};

void main() {
  testWidgets('renders every Sonus launcher asset', (tester) async {
    final out = Directory('branding/generated');

    await tester.runAsync(() async {
      for (final asset in _assets()) {
        final image = await _render(asset);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

        expect(image.width, asset.size, reason: asset.path);
        expect(bytes!.lengthInBytes, greaterThan(64), reason: asset.path);

        if (_write) {
          final file = File('${out.path}/${asset.path}');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes.buffer.asUint8List());
        }
        image.dispose();
      }

      for (final MapEntry(key: path, value: text) in _resources().entries) {
        expect(text, contains('<'), reason: path);
        if (_write) {
          final file = File('${out.path}/$path');
          await file.parent.create(recursive: true);
          await file.writeAsString(text);
        }
      }
    });
  });

  test('the adaptive mark stays inside the 66dp safe zone', () {
    for (final asset in _assets().where((a) => a.shape == _Shape.none)) {
      expect(asset.markScale * 108, lessThanOrEqualTo(66), reason: asset.path);
    }
  });
}
