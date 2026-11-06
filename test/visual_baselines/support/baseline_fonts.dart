// Real fonts for the protected visual baselines.
//
// Flutter's test runner draws every glyph, icons included, as a square.
// The baselines load the real Material Icons font that ships with the
// Flutter SDK, so icon regressions are visible in the golden images, and
// reuse the real Roboto loader from test/support/device_layout.dart (that
// shared helper is not edited).
import 'dart:io';

import 'package:flutter/services.dart';

import '../../support/device_layout.dart';

bool _iconsLoaded = false;

/// Loads `materialicons-regular.otf` from the Flutter SDK under the family
/// Material's [Icons] use ('MaterialIcons').
Future<void> loadMaterialIcons() async {
  if (_iconsLoaded) return;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError('FLUTTER_ROOT is not set; run with `flutter test`.');
  }
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (!file.existsSync()) {
    throw StateError('Material Icons font not found at ${file.path}.');
  }
  final bytes = await file.readAsBytes();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
  _iconsLoaded = true;
}

/// Real Roboto and real Material Icons.
Future<void> loadBaselineFonts() async {
  await loadRealRoboto();
  await loadMaterialIcons();
}
