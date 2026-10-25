import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/presentation/widgets/chart_movement_indicator.dart';

void main() {
  final theme = SonusThemeFactory.build(
    const SonusAppearanceSpec(themeId: SonusThemeId.kickflip),
  );
  final colors = theme.extension<SonusColors>()!;

  Future<void> pump(WidgetTester tester, ChartEntry entry) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(child: ChartMovementIndicator(entry: entry)),
        ),
      ),
    );
  }

  Color iconColor(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon)).color!;

  for (final (movement, previous, text, icon, spoken) in [
    (ChartMovement.up, 5, '3', Icons.arrow_upward_rounded, 'Up 3 places'),
    (ChartMovement.down, 1, '1', Icons.arrow_downward_rounded, 'Down 1 place'),
    (ChartMovement.same, 2, null, Icons.remove_rounded, 'No change'),
    (ChartMovement.newEntry, null, 'NEW', null, 'New entry'),
    (ChartMovement.reentry, null, 'RE-ENTRY', null, 'Re-entry'),
  ]) {
    testWidgets('${movement.name} shows "$text" and reads "$spoken"', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final entry = _entry(movement: movement, previousFinalRank: previous);

      await pump(tester, entry);

      if (text != null) {
        expect(find.text(text), findsOneWidget);
        // Text keeps the primary colour; only the icon or border is tinted.
        expect(
          tester.widget<Text>(find.text(text)).style!.color,
          colors.textPrimary,
        );
      }

      if (icon != null) {
        expect(find.byIcon(icon), findsOneWidget);
      } else {
        expect(find.byType(Icon), findsNothing);
      }

      expect(
        tester.getSemantics(
          find.byKey(const ValueKey<String>('charts-movement-song_2')),
        ),
        matchesSemantics(label: spoken),
      );
      semantics.dispose();
    });
  }

  testWidgets('up and down icons use the theme chart colours', (tester) async {
    await pump(
      tester,
      _entry(movement: ChartMovement.up, previousFinalRank: 5),
    );
    expect(iconColor(tester), colors.chartUp);

    await pump(
      tester,
      _entry(movement: ChartMovement.down, previousFinalRank: 1),
    );
    expect(iconColor(tester), colors.chartDown);

    await pump(
      tester,
      _entry(movement: ChartMovement.same, previousFinalRank: 2),
    );
    expect(iconColor(tester), colors.chartSteady);
  });
}

ChartEntry _entry({required ChartMovement movement, int? previousFinalRank}) {
  return ChartEntry(
    entity: const ChartEntitySnapshot(
      entityId: 'song_2',
      title: 'Song 2',
      artistName: 'Artist',
    ),
    rank: 2,
    qualifiedStreamCount: 10,
    lastQualifiedAt: DateTime.utc(2026, 9, 28),
    previousFinalRank: previousFinalRank,
    peakRank: 1,
    peakAchievedAt: DateTime.utc(2026, 9, 20),
    weeksOnChart: 3,
    movement: movement,
  );
}
