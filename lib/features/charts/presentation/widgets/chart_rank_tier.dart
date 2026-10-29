import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../domain/entities/chart_entry.dart';

/// Emphasis by position (SN-50 E-Q9): a #1 spotlight, elevated #2–3,
/// restrained #4–10 and standard #11–100. Bubbling Under sits flat.
enum ChartRankTier {
  spotlight,
  elevated,
  restrained,
  standard,
  bubblingUnder;

  static ChartRankTier of(ChartEntry entry) {
    if (entry.isOffChartStanding) return bubblingUnder;
    if (entry.rank == 1) return spotlight;
    if (entry.rank <= 3) return elevated;
    if (entry.rank <= 10) return restrained;
    return standard;
  }
}

/// How a tier looks in the current theme. Surfaces and border widths carry
/// the emphasis with decoration Off; accent stripes are decoration and go
/// with it. High Contrast and Low Effects come through the theme tokens,
/// and nothing here animates.
class ChartTierStyle {
  const ChartTierStyle({
    required this.background,
    required this.border,
    required this.stripeWidth,
    required this.rankColor,
  });

  factory ChartTierStyle.of(SonusThemeData tokens, ChartRankTier tier) {
    final colors = tokens.colors;
    final marks = tokens.decoration.showMarks;

    return switch (tier) {
      ChartRankTier.spotlight => ChartTierStyle(
        background: colors.raisedSurface,
        border: BorderSide(color: colors.accentPrimary, width: 2),
        stripeWidth: marks ? 6 : 0,
        rankColor: colors.accentPrimary,
      ),
      ChartRankTier.elevated => ChartTierStyle(
        background: colors.raisedSurface,
        border: BorderSide(color: colors.border),
        stripeWidth: marks ? 4 : 0,
        rankColor: colors.textPrimary,
      ),
      ChartRankTier.restrained => ChartTierStyle(
        background: colors.surface,
        border: BorderSide(color: colors.border),
        stripeWidth: marks ? 2 : 0,
        rankColor: colors.textPrimary,
      ),
      ChartRankTier.standard => ChartTierStyle(
        background: colors.surface,
        border: BorderSide(color: colors.divider),
        stripeWidth: 0,
        rankColor: colors.textPrimary,
      ),
      ChartRankTier.bubblingUnder => ChartTierStyle(
        background: Colors.transparent,
        border: BorderSide(color: colors.divider),
        stripeWidth: 0,
        rankColor: colors.textSecondary,
      ),
    };
  }

  final Color background;
  final BorderSide border;

  /// The accent stripe at the card's leading edge; 0 for none.
  final double stripeWidth;
  final Color rankColor;
}
