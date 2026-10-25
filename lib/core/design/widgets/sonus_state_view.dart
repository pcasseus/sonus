import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// A whole-area loading, empty or error state in the Sonus style.
///
/// The message is announced to screen readers, and the content scrolls when
/// it does not fit (small screens, large text), so nothing is ever clipped.
class SonusStateView extends StatelessWidget {
  const SonusStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.isError = false,
  }) : loading = false;

  /// A spinner with an optional label.
  const SonusStateView.loading({super.key, String? label})
    : icon = null,
      title = label,
      message = null,
      action = null,
      isError = false,
      loading = true;

  final IconData? icon;
  final String? title;
  final String? message;

  /// Usually a single button, such as "Try again" or "Import music".
  final Widget? action;
  final bool isError;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final title = this.title;
    final message = this.message;
    final action = this.action;
    final icon = this.icon;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(tokens.metrics.pageGutter + 8),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      CircularProgressIndicator(color: colors.accentPrimary)
                    else if (icon != null)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isError
                              ? theme.colorScheme.errorContainer
                              : colors.raisedSurface,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Icon(
                            icon,
                            size: 36,
                            color: isError
                                ? theme.colorScheme.onErrorContainer
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    if (title != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    if (action != null) ...[const SizedBox(height: 20), action],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
