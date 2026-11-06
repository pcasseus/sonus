import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';

class ArtistProfileSectionHeading extends StatelessWidget {
  const ArtistProfileSectionHeading({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    this.accent,
  });

  final String title;

  /// A short bar before the title in the page's accent (UI redesign P1);
  /// none when null.
  final Color? accent;

  /// Shown as a badge after the title when given.
  final int? count;

  /// A short explanation under the title.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SonusTheme.of(context);
    final count = this.count;
    final subtitle = this.subtitle;
    final accent = this.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (accent != null) ...[
              ExcludeSemantics(
                child: Container(
                  key: const ValueKey<String>('section-heading-accent'),
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Semantics(
                header: true,
                // One line that shrinks to fit, so a long heading never
                // breaks mid-word at large text sizes.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: tokens.colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
            ),
            if (count != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  // V1: tinted by the page's accent where one is given.
                  color: accent != null && tokens.decoration.allowGradients
                      ? Color.alphaBlend(
                          accent.withValues(alpha: 0.30),
                          tokens.colors.surface,
                        )
                      : tokens.colors.raisedSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    '$count',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
