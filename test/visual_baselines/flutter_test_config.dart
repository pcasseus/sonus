// Applies to every test under test/visual_baselines/ only (Flutter picks up
// the nearest flutter_test_config.dart). Other tests, including the legacy
// Moments JSON goldens, are unaffected.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/baseline_fonts.dart';
import 'support/tolerant_golden_comparator.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    // Same folder as the default comparator: goldens sit beside the test.
    goldenFileComparator = TolerantGoldenComparator(
      current.basedir.resolve('baseline_test.dart'),
    );
  }
  await loadBaselineFonts();
  await testMain();
}
