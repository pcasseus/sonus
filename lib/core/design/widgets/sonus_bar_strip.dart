import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// One bar of a [SonusBarStrip].
@immutable
class SonusBar {
  const SonusBar({
    required this.value,
    required this.spokenLabel,
    this.axisLabel,
  });

  /// Non-negative amount; bars are scaled to the largest value.
  final double value;

  /// What a screen reader announces, e.g. "8 PM, 30 streams".
  final String spokenLabel;

  /// Optional label under the bar, e.g. "6 PM"; leave null to keep the axis
  /// uncluttered.
  final String? axisLabel;
}

/// A compact row of bars, such as listening by hour of day.
///
/// Bar height carries the value. The highlighted bar is the tallest-looking
/// accent bar and is announced as [highlightLabel]; callers also state the
/// peak in text (e.g. "Most active hour: 8 PM"), so it never relies on
/// colour alone. Static: no animation.
class SonusBarStrip extends StatelessWidget {
  const SonusBarStrip({
    super.key,
    required this.bars,
    this.height = 96,
    this.highlightIndex,
    this.highlightLabel = 'Peak',
  });

  final List<SonusBar> bars;

  /// Height of the bar area at 1x text.
  final double height;
  final int? highlightIndex;
  final String highlightLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final textStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: colors.textSecondary);
    final maxValue = bars.fold<double>(0, (m, b) => math.max(m, b.value));
    final hasAxisLabels = bars.any((bar) => bar.axisLabel != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (index, bar) in bars.indexed)
                Expanded(
                  // Each bar is its own node for screen readers.
                  child: Semantics(
                    container: true,
                    label: index == highlightIndex
                        ? '${bar.spokenLabel}, $highlightLabel'
                        : bar.spokenLabel,
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor: maxValue <= 0
                            ? 0.02
                            : math.max(0.02, bar.value / maxValue),
                        child: DecoratedBox(
                          key: index == highlightIndex
                              ? const ValueKey<String>('sonus-bar-highlight')
                              : null,
                          decoration: BoxDecoration(
                            color: index == highlightIndex
                                ? colors.accentPrimary
                                : Color.lerp(
                                    colors.surface,
                                    colors.accentPrimary,
                                    0.55,
                                  ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasAxisLabels) ...[
          const SizedBox(height: 4),
          ExcludeSemantics(
            child: Row(
              children: [
                for (final bar in bars)
                  Expanded(
                    // A label may be wider than its bar; it paints past the
                    // bar's column instead of wrapping.
                    child: bar.axisLabel == null
                        ? const SizedBox.shrink()
                        : Text(
                            bar.axisLabel!,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: textStyle,
                          ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
