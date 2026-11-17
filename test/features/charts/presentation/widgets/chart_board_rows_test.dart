// Chart Studio polish (App Update 1.3): the signature gradient treatment is
// reserved for the open entry, and every tier stays the same size.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_entry_movement.dart';
import 'package:sonus_next/features/charts/presentation/widgets/chart_board_rows.dart';

final _entry = ChartEntry(
  entity: const ChartEntitySnapshot(
    entityId: 's1',
    title: 'Song',
    artistName: 'Artist',
  ),
  rank: 4,
  qualifiedStreamCount: 10,
  lastQualifiedAt: DateTime.utc(2026, 11, 15),
  peakRank: 4,
  peakAchievedAt: DateTime.utc(2026, 11, 15),
  weeksOnChart: 2,
  previousFinalRank: 4,
  movement: ChartMovement.same,
);

Finder _key(String key) => find.byKey(ValueKey<String>(key));

Future<void> _pump(
  WidgetTester tester, {
  SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  ChartRowTier tier = ChartRowTier.compact,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: SonusThemeFactory.build(spec),
      home: Scaffold(
        body: ListView(
          children: [
            ChartCompactRow(
              entry: _entry,
              movement: ChartEntryMovement.of(
                _entry,
                live: false,
                now: DateTime.utc(2026, 11, 16),
              ),
              title: 'Song',
              subtitle: 'Artist',
              artworkPath: null,
              fallbackIcon: Icons.music_note_rounded,
              tier: tier,
              details: (_) => const SizedBox(height: 120),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_key('charts-row-expand-s1'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only the open entry gets the flowing gradient', (tester) async {
    await _pump(tester);
    expect(_key('charts-tile-flow-s1'), findsNothing);

    await _open(tester);
    expect(_key('charts-tile-flow-s1'), findsOneWidget);

    await tester.tap(_key('charts-row-collapse-s1'));
    await tester.pumpAndSettle();
    expect(_key('charts-tile-flow-s1'), findsNothing);
  });

  for (final (name, spec) in const [
    ('High contrast', SonusAppearanceSpec(highContrast: true)),
    ('Low effects', SonusAppearanceSpec(lowEffects: true)),
    (
      'Decoration off',
      SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
    ),
    ('Monochrome', SonusAppearanceSpec(themeId: SonusThemeId.monochrome)),
  ]) {
    testWidgets('$name: the open entry is plain, without ribbons', (
      tester,
    ) async {
      await _pump(tester, spec: spec);
      await _open(tester);
      expect(_key('charts-tile-flow-s1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('every tier is the same size, open or closed', (tester) async {
    final heights = <ChartRowTier, double>{};
    for (final tier in ChartRowTier.values) {
      await _pump(tester, tier: tier);
      heights[tier] = tester.getSize(_key('charts-tile-s1')).height;
    }
    expect(heights.values.toSet(), hasLength(1));
  });
}
