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
    (ChartMovement.newEntry, null, 'NEW', Icons.star_rounded, 'New entry'),
    (ChartMovement.reentry, null, 'RE-ENTRY', Icons.replay_rounded, 'Re-entry'),
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

      expect(find.byIcon(icon), findsOneWidget);

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

  testWidgets('NEW and RE-ENTRY have their own colours and icons', (
    tester,
  ) async {
    Color borderColor() {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.byType(Icon),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return ((box.decoration as BoxDecoration).border! as Border).top.color;
    }

    await pump(tester, _entry(movement: ChartMovement.newEntry));
    expect(iconColor(tester), colors.chartNew);
    expect(borderColor(), colors.chartNew);

    await pump(tester, _entry(movement: ChartMovement.reentry));
    expect(iconColor(tester), colors.chartReentry);
    expect(borderColor(), colors.chartReentry);
    expect(colors.chartReentry, isNot(colors.chartNew));
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
