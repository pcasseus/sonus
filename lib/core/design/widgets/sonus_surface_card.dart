import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// A plain Sonus surface: the theme's surface colour, card radius and a
/// hairline divider border. A semantics container, like a Material card.
class SonusSurfaceCard extends StatelessWidget {
  const SonusSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.raised = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Uses the raised surface, for content that should stand out.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;

    return Semantics(
      container: true,
      child: Material(
        color: raised ? colors.raisedSurface : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
          side: BorderSide(color: colors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
