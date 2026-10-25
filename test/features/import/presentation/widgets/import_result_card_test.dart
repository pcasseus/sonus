// Integration of SN-48's restyled import result (SonusNoticeCard) with the
// Import Health Report action from the functional branch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_notice_card.dart';
import 'package:sonus_next/features/import/application/models/import_execution_summary.dart';
import 'package:sonus_next/features/import/presentation/widgets/import_result_card.dart';

void main() {
  const summary = ImportExecutionSummary(
    batchId: 'batch',
    totalCount: 3,
    importedCount: 2,
    relinkedCount: 0,
    skippedCount: 1,
    failedCount: 0,
  );

  Future<void> pump(WidgetTester tester, Widget card) => tester.pumpWidget(
    MaterialApp(
      theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );

  const health = ValueKey<String>('import-health-button');

  testWidgets('keeps the SN-48 notice card and adds the health action', (
    tester,
  ) async {
    var opened = 0;

    await pump(
      tester,
      ImportResultCard(
        summary: summary,
        reviewCount: 1,
        onReview: () {},
        onReset: () {},
        onCheckHealth: () => opened++,
      ),
    );

    expect(find.byType(SonusNoticeCard), findsOneWidget);
    expect(find.text('Import complete'), findsOneWidget);
    expect(find.text('Check library health'), findsOneWidget);

    // Review first, then the health report, then "Import more music".
    final review = tester.getTopLeft(
      find.byKey(const ValueKey<String>('import-review-button')),
    );
    final check = tester.getTopLeft(find.byKey(health));
    final reset = tester.getTopLeft(
      find.byKey(const ValueKey<String>('import-reset-button')),
    );
    expect(review.dy, lessThan(check.dy));
    expect(check.dy, lessThan(reset.dy));

    await tester.tap(find.byKey(health));
    expect(opened, 1);
  });

  testWidgets('no health action unless the page provides one', (tester) async {
    await pump(tester, ImportResultCard(summary: summary, onReset: () {}));

    expect(find.byKey(health), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('import-reset-button')),
      findsOneWidget,
    );
  });
}
