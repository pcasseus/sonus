import 'package:flutter/material.dart';

import '../sonus_theme.dart';
import 'sonus_comparison_indicator.dart';

/// A single statistic: a label, a large tabular value, and optionally an
/// earlier-period value and a [SonusComparison].
///
/// It reads as one sentence for screen readers, e.g. "Streams, 120,
/// previous month 95, up 26 percent".
class SonusMetricTile extends StatelessWidget {
  const SonusMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.previousLabel,
    this.comparison,
    this.featured = false,
  });

  final String label;
  final String value;

  /// Context such as "Sep: 95"; shown under the value.
  final String? previousLabel;
  final SonusComparison? comparison;

  /// Featured tiles use the display statistic style and a raised surface.
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final comparison = this.comparison;
    final previousLabel = this.previousLabel;

    final valueStyle =
        (featured ? tokens.text.featuredStat : tokens.text.numeric).copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return Semantics(
      container: true,
      label: [
        label,
        value,
        ?previousLabel,
        ?comparison?.spokenLabel,
      ].join(', '),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: featured ? colors.raisedSurface : colors.surface,
          border: Border.all(color: colors.divider),
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.metrics.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: tokens.metrics.spaceXs),
              // Wraps at spaces ("82h 30m") rather than shrinking, so the
              // user's text size is respected.
              Text(value, style: valueStyle),
              if (previousLabel != null) ...[
                SizedBox(height: tokens.metrics.spaceXs),
                Text(
                  previousLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (comparison != null) ...[
                SizedBox(height: tokens.metrics.spaceSm),
                SonusComparisonIndicator(comparison: comparison),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
