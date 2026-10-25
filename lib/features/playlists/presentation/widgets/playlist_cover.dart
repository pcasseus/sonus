import 'package:flutter/material.dart';

import '../../../../core/design/sonus_contrast.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_artwork_image.dart';

/// A playlist's cover: its first song's artwork when one is known,
/// otherwise a generated cover in the theme's accent colours.
///
/// The generated cover is a gradient only while decoration allows it, and
/// a flat surface with Decoration Off, High contrast or Low effects.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.size, this.artworkPath});

  final double size;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final path = artworkPath?.trim();

    if (path != null && path.isNotEmpty) {
      return SonusArtworkImage(
        path: path,
        size: size,
        placeholderIcon: Icons.queue_music_rounded,
      );
    }

    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final gradient = tokens.decoration.allowGradients;
    // The icon takes whichever text colour reads best on the cover.
    final ground = gradient ? colors.decorationPrimary : colors.raisedSurface;
    final iconColor =
        SonusContrast.ratio(colors.textPrimary, ground) >=
            SonusContrast.ratio(colors.onArtworkScrim, ground)
        ? colors.textPrimary
        : colors.onArtworkScrim;

    return SonusArtworkFrame(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: gradient ? null : colors.raisedSurface,
          gradient: gradient
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.decorationPrimary,
                    colors.decorationSecondary,
                  ],
                )
              : null,
        ),
        child: Center(
          child: Icon(
            Icons.queue_music_rounded,
            size: size * 0.44,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}
