import 'package:flutter/material.dart';

import '../sonus_tokens.dart';

/// Gives [child] the page's [secondary] text colour where the context
/// theme does not: an untinted page (neutral artwork) over the artwork
/// environment keeps the theme, whose grey secondary text is too dark
/// there. Changes nothing when the colour is already the theme's.
class SonusSecondaryTextScope extends StatelessWidget {
  const SonusSecondaryTextScope({
    super.key,
    required this.secondary,
    required this.child,
  });

  final Color secondary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SonusColors>();
    if (colors == null || colors.textSecondary == secondary) return child;
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(onSurfaceVariant: secondary),
        extensions: [
          for (final extension in theme.extensions.values)
            if (extension is SonusColors)
              extension.copyWith(textSecondary: secondary)
            else
              extension,
        ],
      ),
      child: child,
    );
  }
}
