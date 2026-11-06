// Pinned geometry for the protected visual baselines.
//
// Pixel comparison can miss a small move or resize that is still a
// regression (or be noisy where it doesn't matter), so every baseline also
// pins the rectangles of its key parts, in logical pixels at the phone's
// real density. The numbers live in a reviewable JSON file beside the
// goldens and are recorded and approved exactly like them: with
// `flutter test --update-goldens <file>` (see test/visual_baselines/README.md).
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// Rectangles may differ by this much (logical pixels) and still match.
const double geometryTolerance = 0.5;

class GeometryBaseline {
  /// [path] is relative to the package root, e.g.
  /// `test/visual_baselines/goldens/roster/geometry.json`.
  GeometryBaseline(this.path);

  final String path;
  Map<String, dynamic> _recorded = const {};
  final Map<String, Map<String, List<double>?>> _updates = {};

  /// Call from setUpAll and tearDownAll.
  void register() {
    setUpAll(() {
      final file = File(path);
      if (file.existsSync()) {
        _recorded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      }
    });
    tearDownAll(() {
      if (!autoUpdateGoldenFiles || _updates.isEmpty) return;
      final merged = <String, dynamic>{..._recorded, ..._updates};
      final sorted = {
        for (final key in merged.keys.toList()..sort()) key: merged[key],
      };
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
        );
    });
  }

  /// Checks (or, when updating, records) the rectangles of [parts] under
  /// [scenario]. A part that is not on screen is pinned as null, so a part
  /// that appears or disappears is a change too.
  void check(WidgetTester tester, String scenario, Map<String, Finder> parts) {
    final actual = <String, List<double>?>{
      for (final MapEntry(:key, :value) in parts.entries)
        key: value.evaluate().isEmpty ? null : _encode(tester.getRect(value)),
    };
    if (autoUpdateGoldenFiles) {
      _updates[scenario] = actual;
      return;
    }
    final expected = _recorded[scenario] as Map<String, dynamic>?;
    if (expected == null) {
      fail(
        'No pinned geometry for "$scenario" in $path. Record it with '
        '`flutter test --update-goldens <this test file>` after approval.',
      );
    }
    for (final MapEntry(:key, :value) in actual.entries) {
      expect(
        expected.containsKey(key),
        isTrue,
        reason: '$scenario: "$key" is not pinned in $path',
      );
      final pinned = expected[key] as List<dynamic>?;
      if (pinned == null || value == null) {
        expect(
          value == null,
          pinned == null,
          reason:
              '$scenario: "$key" is ${value == null ? 'missing' : 'shown'} '
              'but was ${pinned == null ? 'missing' : 'shown'} when approved',
        );
        continue;
      }
      for (var i = 0; i < 4; i++) {
        expect(
          value[i],
          closeTo((pinned[i] as num).toDouble(), geometryTolerance),
          reason:
              '$scenario: "$key" ${const ['left', 'top', 'width', 'height'][i]} '
              'moved (now ${_describe(value)}, approved ${pinned.join(', ')})',
        );
      }
    }
  }

  static List<double> _encode(Rect rect) => [
    for (final v in [rect.left, rect.top, rect.width, rect.height])
      double.parse(v.toStringAsFixed(2)),
  ];

  static String _describe(List<double> v) => v.join(', ');
}
