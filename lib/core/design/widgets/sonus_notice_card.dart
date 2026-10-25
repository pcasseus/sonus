import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// What a notice is about. Each tone has its own icon as well as colour,
/// so its meaning never rests on colour alone.
enum SonusNoticeTone { info, success, warning, error }

/// A titled status message with optional actions, for imports, recovery,
/// sync and other utility screens. Safety-critical wording is passed in
/// unchanged; the card only styles it. Announced to screen readers when it
/// appears.
class SonusNoticeCard extends StatelessWidget {
  const SonusNoticeCard({
    super.key,
    required this.tone,
    required this.title,
    this.message,
    this.actions = const [],
    this.children = const [],
  });

  final SonusNoticeTone tone;
  final String title;
  final String? message;

  /// Extra content under the message, such as a list of counts.
  final List<Widget> children;

  /// Full-width buttons, stacked.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = this.message;

    final (IconData icon, Color iconColor, Color edge) = switch (tone) {
      SonusNoticeTone.info => (
        Icons.info_outline_rounded,
        colors.textSecondary,
        colors.divider,
      ),
      SonusNoticeTone.success => (
        Icons.check_circle_outline_rounded,
        colors.accentPrimary,
        colors.divider,
      ),
      SonusNoticeTone.warning => (
        Icons.warning_amber_rounded,
        scheme.error,
        scheme.error,
      ),
      SonusNoticeTone.error => (
        Icons.error_outline_rounded,
        scheme.error,
        scheme.error,
      ),
    };

    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
          side: BorderSide(
            color: edge,
            width: edge == colors.divider ? 1 : 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: iconColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ],
              ...children,
              for (final action in actions) ...[
                const SizedBox(height: 12),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
