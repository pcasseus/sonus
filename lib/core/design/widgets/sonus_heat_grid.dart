import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// One cell of a [SonusHeatGrid], e.g. a day of the month.
@immutable
class SonusHeatCell {
  const SonusHeatCell({
    this.key,
    required this.label,
    required this.value,
    required this.spokenLabel,
  });

  /// Identifies the cell's widget, e.g. in tests.
  final Key? key;

  /// Short visible label, e.g. the day number.
  final String label;

  /// Non-negative amount; zero means no activity.
  final double value;

  /// What a screen reader announces, e.g. "October 12, 5 streams".
  final String spokenLabel;
}

/// A calendar-style grid where each cell's activity is shown twice: by the
/// height of its fill and by a shade derived from the theme accent. Values
/// never rely on colour alone, and every cell has a spoken label.
///
/// Static by design: no animation.
class SonusHeatGrid extends StatelessWidget {
  const SonusHeatGrid({
    super.key,
    required this.cells,
    this.columns = 7,
    this.leadingBlanks = 0,
    this.columnLabels,
  });

  final List<SonusHeatCell> cells;
  final int columns;

  /// Empty cells before the first one, e.g. to start a month on its weekday.
  final int leadingBlanks;

  /// Optional header labels, one per column (e.g. weekday initials).
  final List<String>? columnLabels;

  /// Shade for [t] in 0..1, from a faint tint of the accent to the accent.
  static Color shadeFor(Color surface, Color accent, double t) {
    final start = Color.lerp(surface, accent, 0.25)!;

    return Color.lerp(start, accent, t.clamp(0, 1))!;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final maxValue = cells.fold<double>(0, (m, c) => math.max(m, c.value));
    final slots = <SonusHeatCell?>[
      for (var i = 0; i < leadingBlanks; i++) null,
      ...cells,
    ];
    final rowCount = (slots.length / columns).ceil();
    final labels = columnLabels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (labels != null)
          ExcludeSemantics(
            child: Row(
              children: [
                for (final label in labels)
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        for (var row = 0; row < rowCount; row++)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                for (var column = 0; column < columns; column++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _cellAt(row * columns + column, slots, maxValue),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cellAt(int index, List<SonusHeatCell?> slots, double maxValue) {
    final cell = index < slots.length ? slots[index] : null;

    if (cell == null) {
      return const AspectRatio(aspectRatio: 0.8, child: SizedBox.shrink());
    }

    return _HeatCell(
      cell: cell,
      intensity: maxValue <= 0 ? 0 : cell.value / maxValue,
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.cell, required this.intensity});

  final SonusHeatCell cell;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final radius = BorderRadius.circular(tokens.metrics.controlRadius / 2);

    // Its own node, so a screen reader can move cell by cell instead of
    // hearing the whole month as one announcement.
    return Semantics(
      key: cell.key,
      container: true,
      label: cell.spokenLabel,
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 0.8,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.divider),
            borderRadius: radius,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The label sits on the plain surface, so its contrast never
                // depends on the fill.
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                  child: Text(
                    cell.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      key: const ValueKey<String>('sonus-heat-fill'),
                      heightFactor: intensity <= 0
                          ? 0
                          : 0.15 + 0.85 * intensity,
                      widthFactor: 1,
                      child: ColoredBox(
                        color: SonusHeatGrid.shadeFor(
                          colors.surface,
                          colors.accentPrimary,
                          intensity,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
