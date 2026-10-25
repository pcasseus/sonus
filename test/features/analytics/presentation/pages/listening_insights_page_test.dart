import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/presentation/pages/listening_insights_page.dart';

void main() {
  testWidgets('starts on Monthly and switches to Year', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ListeningInsightsPage())),
    );

    expect(
      find.byKey(const ValueKey<String>('listening-insights-view-selector')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey<String>('monthly-insights-initializing')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey<String>('year-in-sonus-initializing')),
      findsNothing,
    );

    await tester.tap(find.text('Year'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('year-in-sonus-initializing')),
      findsOneWidget,
    );
  });

  testWidgets('can switch back to Monthly after opening Year', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ListeningInsightsPage())),
    );

    await tester.tap(find.text('Year'));
    await tester.pump();

    await tester.tap(find.text('Monthly'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('monthly-insights-initializing')),
      findsOneWidget,
    );
  });

  // Characterization (SN-48K1): both views stay mounted, so switching never
  // discards the other view's state.
  testWidgets('keeps Monthly mounted while Year is shown', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ListeningInsightsPage())),
    );

    await tester.tap(find.text('Year'));
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey<String>('monthly-insights-initializing'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('monthly-insights-initializing')),
      findsNothing,
    );
  });
}
