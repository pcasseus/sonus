import 'dart:io';

import 'package:flutter/material.dart';

import 'sonus_artwork_frame.dart';
import 'sonus_decorations.dart';

/// Artwork from a local file in the theme's frame, decoded near its display
/// size, with the shared placeholder when the path is missing or unreadable.
class SonusArtworkImage extends StatelessWidget {
  const SonusArtworkImage({
    super.key,
    required this.path,
    required this.size,
    this.circular = false,
    this.placeholderIcon = Icons.music_note_rounded,
    this.semanticLabel,
  });

  final String? path;
  final double size;
  final bool circular;
  final IconData placeholderIcon;

  /// Read by screen readers; leave null when nearby text already names it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final trimmed = path?.trim();
    final placeholder = SonusArtworkPlaceholder(
      icon: placeholderIcon,
      iconSize: size * 0.45,
    );

    return SonusArtworkFrame(
      size: size,
      circular: circular,
      child: trimmed == null || trimmed.isEmpty
          ? placeholder
          : Image.file(
              File(trimmed),
              fit: BoxFit.cover,
              // Decoded at its display size, never at full resolution.
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              gaplessPlayback: true,
              semanticLabel: semanticLabel,
              excludeFromSemantics: semanticLabel == null,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
    );
  }
}
