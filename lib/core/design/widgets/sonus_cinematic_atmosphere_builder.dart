import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../sonus_artwork_palette.dart';
import '../sonus_cinematic_colors.dart';
import '../sonus_theme.dart';
import 'sonus_artwork_colors_request.dart';

/// Builds with the cinematic colours for [artworkPath] (UI redesign D3):
/// dark and artwork-driven in every theme, including Daylight. The base
/// colours show at once; the artwork's colours, always extracted for a dark
/// background, ease in once ready (or switch at once with reduced motion).
/// Decoration Off, High contrast and Low effects keep flat, untinted
/// colours (see [SonusCinematicColors.resolve]).
///
/// For screens whose artwork changes without a rebuild (the centred artist
/// in a reel), use [SonusCinematicAtmosphereBuilder.listenable].
class SonusCinematicAtmosphereBuilder extends StatefulWidget {
  const SonusCinematicAtmosphereBuilder({
    super.key,
    required this.artworkPath,
    required this.builder,
    this.palette,
  }) : artworkPathListenable = null;

  /// Follows [artworkPath] as it changes, requesting the new artwork's
  /// colours as soon as it is notified.
  const SonusCinematicAtmosphereBuilder.listenable({
    super.key,
    required ValueListenable<String?> artworkPath,
    required this.builder,
    this.palette,
  }) : artworkPath = null,
       artworkPathListenable = artworkPath;

  final String? artworkPath;

  /// The artwork to follow, when set.
  final ValueListenable<String?>? artworkPathListenable;

  /// Where artwork colours come from; the app-wide cache by default.
  final SonusArtworkPalette? palette;

  final Widget Function(BuildContext context, SonusCinematicColors colors)
  builder;

  @override
  State<SonusCinematicAtmosphereBuilder> createState() =>
      _SonusCinematicAtmosphereBuilderState();
}

class _SonusCinematicAtmosphereBuilderState
    extends State<SonusCinematicAtmosphereBuilder>
    with SonusArtworkColorsRequest<SonusCinematicAtmosphereBuilder> {
  @override
  SonusArtworkPalette? get artworkPalette => widget.palette;

  @override
  ValueListenable<String?>? artworkPathListenableOf(
    SonusCinematicAtmosphereBuilder widget,
  ) => widget.artworkPathListenable;

  @override
  String? artworkPathOf(SonusCinematicAtmosphereBuilder widget) =>
      widget.artworkPath;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    // The cinematic screens are dark in every theme, so the artwork's
    // colours are always extracted for a dark background.
    requestArtworkColors(Brightness.dark);

    final target = SonusCinematicColors.resolve(
      decoration: tokens.decoration,
      artwork: artworkColors,
    );

    return TweenAnimationBuilder<SonusCinematicColors>(
      tween: SonusCinematicColorsTween(end: target),
      duration: tokens.motion.medium,
      curve: tokens.motion.curve,
      builder: (context, colors, _) => widget.builder(context, colors),
    );
  }
}
