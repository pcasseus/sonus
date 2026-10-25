import 'package:flutter/material.dart';

import '../sonus_theme.dart';
import 'sonus_decorations.dart';

/// The large title at the top of a main destination (Library, Tracks,
/// Search, Playlists), with an optional summary line and trailing actions.
class SonusPageHeader extends StatelessWidget {
  const SonusPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleKey,
    this.trailing,
    this.padding,
  });

  final String title;
  final String? subtitle;

  /// Keeps an existing test key on the summary line.
  final Key? subtitleKey;

  /// Buttons beside the title, such as sort or create.
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final gutter = tokens.metrics.pageGutter;
    final subtitle = this.subtitle;
    final trailing = this.trailing;

    return Padding(
      padding: padding ?? EdgeInsets.fromLTRB(gutter, 20, gutter, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  // One line that shrinks to fit rather than breaking a
                  // short title mid-word at large text sizes.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                ),
                if (tokens.decoration.showMarks) ...[
                  SizedBox(height: tokens.metrics.spaceXs),
                  const SonusMotifMark(),
                ],
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    key: subtitleKey,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }
}
