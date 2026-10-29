import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/models/chart_movement.dart';

/// A chart entry's movement since last week: an icon in the theme's chart
/// colour plus a number or word, so movement never relies on colour alone.
///
/// The colour goes on the icon only. Chart colours are guaranteed 3:1, which
/// suits icons; the text keeps the primary text colour for 4.5:1.
class ChartMovementIndicator extends StatelessWidget {
  const ChartMovementIndicator({super.key, required this.entry});

  final ChartEntry entry;

  /// What a screen reader announces, e.g. "Up 2 places".
  static String semanticLabelFor(ChartEntry entry) {
    final distance = _distance(entry);

    return switch (entry.movement) {
      ChartMovement.up => 'Up $distance ${_places(distance)}',
      ChartMovement.down => 'Down $distance ${_places(distance)}',
      ChartMovement.newEntry => 'New entry',
      ChartMovement.reentry => 'Re-entry',
      ChartMovement.same => 'No change',
    };
  }

  static int _distance(ChartEntry entry) {
    final previous = entry.previousFinalRank;

    return previous == null ? 0 : (previous - entry.rank).abs();
  }

  static String _places(int distance) => distance == 1 ? 'place' : 'places';

  static bool _isBadge(ChartMovement movement) =>
      movement == ChartMovement.newEntry || movement == ChartMovement.reentry;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final (
      IconData icon,
      Color iconColor,
      String text,
    ) = switch (entry.movement) {
      ChartMovement.up => (
        Icons.arrow_upward_rounded,
        colors.chartUp,
        '${_distance(entry)}',
      ),
      ChartMovement.down => (
        Icons.arrow_downward_rounded,
        colors.chartDown,
        '${_distance(entry)}',
      ),
      ChartMovement.newEntry => (Icons.star_rounded, colors.chartNew, 'NEW'),
      ChartMovement.reentry => (
        Icons.replay_rounded,
        colors.chartReentry,
        'RE-ENTRY',
      ),
      ChartMovement.same => (Icons.remove_rounded, colors.chartSteady, ''),
    };

    final Widget visual;

    if (_isBadge(entry.movement)) {
      // New and re-entry are words with their own icon; each has its own
      // chart colour on the border and icon, never on the text (E-Q16).
      visual = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: iconColor, width: 1.5),
          borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 2),
              Text(text, style: textStyle),
            ],
          ),
        ),
      );
    } else {
      visual = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          if (text.isNotEmpty) ...[
            const SizedBox(width: 2),
            Text(text, style: textStyle),
          ],
        ],
      );
    }

    return Semantics(
      key: ValueKey<String>('charts-movement-${entry.entity.entityId}'),
      label: semanticLabelFor(entry),
      excludeSemantics: true,
      child: visual,
    );
  }
}
