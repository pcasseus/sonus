import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// Which way a value moved against its comparison period.
enum SonusComparisonDirection { up, down, unchanged, isNew }

/// A comparison against an earlier period, already formatted by the caller.
///
/// The component never calculates: callers pass values from their own
/// models (for example an analytics `percentChange`), so presentation can
/// never drift from the source of truth.
@immutable
class SonusComparison {
  const SonusComparison({
    required this.direction,
    required this.text,
    required this.spokenLabel,
  });

  final SonusComparisonDirection direction;

  /// Visible text such as "+20.0%", "New" or "No change".
  final String text;

  /// What a screen reader announces, e.g. "Up 20 percent on last month".
  final String spokenLabel;
}

/// Shows a [SonusComparison] as an icon plus text.
///
/// The theme's chart colour goes on the icon only (chart colours are
/// guaranteed 3:1, enough for icons); the text keeps the secondary text
/// colour for 4.5:1, and the icon shape and words carry the meaning, so
/// direction never relies on colour alone.
class SonusComparisonIndicator extends StatelessWidget {
  const SonusComparisonIndicator({super.key, required this.comparison});

  final SonusComparison comparison;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    final (IconData icon, Color iconColor) = switch (comparison.direction) {
      SonusComparisonDirection.up => (
        Icons.arrow_upward_rounded,
        colors.chartUp,
      ),
      SonusComparisonDirection.down => (
        Icons.arrow_downward_rounded,
        colors.chartDown,
      ),
      SonusComparisonDirection.unchanged => (
        Icons.remove_rounded,
        colors.chartSteady,
      ),
      SonusComparisonDirection.isNew => (
        Icons.fiber_new_rounded,
        colors.chartNew,
      ),
    };

    return Semantics(
      label: comparison.spokenLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              comparison.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
