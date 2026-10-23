import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// Clips artwork to the theme's artwork radius and, while decoration is on,
/// draws a hairline frame so artwork reads as a physical object on every
/// surface.
///
/// The frame is a foreground border: it adds no layout and no shadow, so it
/// is cheap inside scrolling rails.
class SonusArtworkFrame extends StatelessWidget {
  const SonusArtworkFrame({
    super.key,
    required this.size,
    required this.child,
    this.circular = false,
  });

  final double size;
  final Widget child;

  /// Artist portraits stay circular in every theme.
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final radius = circular
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(tokens.metrics.artworkRadius);

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: tokens.decoration.showMarks
              ? Border.all(color: tokens.colors.artworkFrame)
              : null,
        ),
        child: ClipRRect(borderRadius: radius, child: child),
      ),
    );
  }
}
