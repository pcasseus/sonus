import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';

/// A song's version beside a title that stays as recorded (App Update 1.3,
/// REF-1.3-01): a finalized chart week or a Moment. Presentation only: the
/// recorded title, rank and identity are unchanged. Outlined text, so it
/// never relies on colour, and it scales with the text size.
class ChartVersionBadge extends StatelessWidget {
  const ChartVersionBadge({super.key, required this.label});

  /// The version qualifier, such as "Remix" or "Acoustic Live".
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.textSecondary),
        borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
