import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/models/chart_movement.dart';
import '../models/chart_entry_movement.dart';

/// A chart entry's movement since last week: an icon in the theme's chart
/// colour plus a number or word, so movement never relies on colour alone.
///
/// The colour goes on the icon only. Chart colours are guaranteed 3:1, which
/// suits icons; the text keeps the primary text colour for 4.5:1.
class ChartMovementIndicator extends StatelessWidget {
  const ChartMovementIndicator({super.key, required this.entry, this.movement});

  final ChartEntry entry;

  /// Charts 2.0 C2: the row's movement and achievement. Without it the
  /// indicator shows the stored movement as before.
  final ChartEntryMovement? movement;

  static const Color _gold = Color(0xFFFFC53D);
  static const Color _blue = Color(0xFF4DA3FF);

  /// Monochrome stays greyscale: gold and blue become light and mid grey.
  static bool _greyscale(Color accent) =>
      (accent.r - accent.g).abs() < 0.02 && (accent.g - accent.b).abs() < 0.02;

  Widget _c2(BuildContext context, ChartEntryMovement m) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final grey = _greyscale(colors.accentPrimary);
    final gold = grey ? colors.textPrimary : _gold;
    final blue = grey ? colors.textSecondary : _blue;
    final base = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget badge(
      String text,
      IconData icon,
      Color colour,
      bool lit,
    ) => DecoratedBox(
      key: ValueKey<String>(
        'charts-achievement-${entry.entity.entityId}-${lit ? 'lit' : 'plain'}',
      ),
      decoration: BoxDecoration(
        color: lit ? colour.withValues(alpha: 0.18) : null,
        border: Border.all(
          color: lit ? colour : colors.border,
          width: lit ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: lit ? colour : colors.textSecondary),
            const SizedBox(width: 2),
            Text(
              text,
              style: base?.copyWith(
                color: lit ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );

    final achievement = switch (m.achievement) {
      ChartAchievement.newEntry => badge(
        'NEW',
        Icons.star_rounded,
        colors.chartNew,
        m.highlighted,
      ),
      ChartAchievement.reentry => badge(
        'RE-ENTRY',
        Icons.replay_rounded,
        blue,
        m.highlighted,
      ),
      ChartAchievement.newPeak => badge(
        m.provisional ? 'PEAK · LIVE' : 'NEW PEAK',
        Icons.workspace_premium_rounded,
        gold,
        true,
      ),
      ChartAchievement.none => null,
    };

    final (IconData? icon, Color colour) = switch (m.kind) {
      ChartMoveKind.up ||
      ChartMoveKind.promoted => (Icons.arrow_upward_rounded, colors.chartUp),
      ChartMoveKind.down ||
      ChartMoveKind.demoted => (Icons.arrow_downward_rounded, colors.chartDown),
      ChartMoveKind.same => (null, colors.chartSteady),
      _ => (null, colors.textSecondary),
    };
    final showMove =
        m.kind != ChartMoveKind.debut &&
        m.kind != ChartMoveKind.reentry &&
        m.kind != ChartMoveKind.unknown;
    final percent = m.percentLabel;
    final note = m.crossChartNote;

    return Semantics(
      key: ValueKey<String>('charts-movement-${entry.entity.entityId}'),
      label: m.spokenLabel(entry.rank),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showMove)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, size: 16, color: colour),
                Text(m.shortLabel, style: base?.copyWith(color: colour)),
              ],
            ),
          if (percent != null || note != null)
            Text(
              note ?? percent!,
              key: ValueKey<String>(
                'charts-movement-detail-${entry.entity.entityId}',
              ),
              style: TextStyle(color: colors.textSecondary, fontSize: 10),
            ),
          if (achievement != null) ...[
            if (showMove) const SizedBox(height: 2),
            achievement,
          ],
        ],
      ),
    );
  }

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
    final c2 = movement;
    if (c2 != null) return _c2(context, c2);
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
