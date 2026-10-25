import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';

/// A titled group of settings rows on one themed surface.
///
/// Rows are separated by dividers; the title is announced as a heading.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;

  /// Optional explanation shown under the group.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.metrics.spaceXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: tokens.metrics.spaceXs,
              bottom: tokens.metrics.spaceSm,
            ),
            child: Semantics(
              container: true,
              header: true,
              child: Text(
                title,
                style: textTheme.titleSmall?.copyWith(
                  color: tokens.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          // A semantics container, as a Card is: rows never merge into
          // the heading above.
          Semantics(
            container: true,
            child: Material(
              color: tokens.colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
                side: BorderSide(color: tokens.colors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: tokens.colors.divider),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.metrics.spaceXs,
                tokens.metrics.spaceSm,
                tokens.metrics.spaceXs,
                0,
              ),
              child: Text(
                footer!,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A settings row that opens a destination, with a one-line live summary.
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleKey,
    this.onTap,
    this.trailing,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Key for the summary text, so tests and tools can read it.
  final Key? subtitleKey;
  final VoidCallback? onTap;

  /// Replaces the chevron, e.g. with a count badge.
  final Widget? trailing;

  /// Marks the summary as needing attention. Shown with an icon as well as
  /// colour, so it is never conveyed by colour alone.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final scheme = Theme.of(context).colorScheme;
    final summary = subtitle;

    return ListTile(
      leading: Icon(icon, color: colors.textSecondary),
      title: Text(
        title,
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: summary == null
          ? null
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (warning)
                  Padding(
                    padding: const EdgeInsets.only(right: 4, top: 2),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: scheme.error,
                    ),
                  ),
                Expanded(
                  child: Text(
                    summary,
                    key: subtitleKey,
                    style: TextStyle(
                      color: warning ? scheme.error : colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: colors.textSecondary)),
      onTap: onTap,
    );
  }
}

/// A read-only fact row inside a [SettingsSection].
class SettingsInfoTile extends StatelessWidget {
  const SettingsInfoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return ListTile(
      leading: Icon(icon, color: colors.textSecondary),
      title: Text(title, style: TextStyle(color: colors.textPrimary)),
      subtitle: Text(body, style: TextStyle(color: colors.textSecondary)),
    );
  }
}

/// Opens [page] as a full-screen route.
void pushSettingsPage(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}
