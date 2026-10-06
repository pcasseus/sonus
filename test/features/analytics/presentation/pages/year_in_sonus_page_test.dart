import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/presentation/pages/year_in_sonus_page.dart';

void main() {
  testWidgets(
    'shows initializing state when Year in Sonus controller is unavailable',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: YearInSonusPage())),
      );

      expect(
        find.byKey(const ValueKey<String>('year-in-sonus-initializing')),
        findsOneWidget,
      );

      expect(find.text('Year in Sonus is getting ready'), findsOneWidget);
    },
  );
}
