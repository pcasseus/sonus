import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../sonus_artwork_palette.dart';
import '../sonus_atmosphere_colors.dart';
import '../sonus_theme.dart';
import 'sonus_artwork_colors_request.dart';

/// Builds with the artwork atmosphere for [artworkPath]: theme colours at
/// once, the artwork's colours once extracted, eased in (or switched at
/// once with reduced motion). Decoration Off, High contrast and Low
/// effects keep the theme colours, as on the Album Profile.
///
/// Pages whose artwork is decided by a controller that notifies without
/// rebuilding them use [SonusArtworkAtmosphereBuilder.listenable]: the
/// colours are then requested the moment the artwork changes, not a frame
/// later when something rebuilds.
class SonusArtworkAtmosphereBuilder extends StatefulWidget {
  const SonusArtworkAtmosphereBuilder({
    super.key,
    required this.artworkPath,
    required this.builder,
    this.palette,
  }) : artworkPathListenable = null;

  /// Follows [artworkPath] as it changes, requesting the new artwork's
  /// colours as soon as it is notified.
  const SonusArtworkAtmosphereBuilder.listenable({
    super.key,
    required ValueListenable<String?> artworkPath,
    required this.builder,
    this.palette,
  }) : artworkPath = null,
       artworkPathListenable = artworkPath;

  final String? artworkPath;

  /// The artwork to follow, when set (see [SonusArtworkAtmosphereBuilder.listenable]).
  final ValueListenable<String?>? artworkPathListenable;

  /// Where artwork colours come from; the app-wide cache by default.
  final SonusArtworkPalette? palette;
  final Widget Function(BuildContext context, SonusAtmosphereColors colors)
  builder;

  @override
  State<SonusArtworkAtmosphereBuilder> createState() =>
      _SonusArtworkAtmosphereBuilderState();
}

class _SonusArtworkAtmosphereBuilderState
    extends State<SonusArtworkAtmosphereBuilder>
    with SonusArtworkColorsRequest<SonusArtworkAtmosphereBuilder> {
  @override
  SonusArtworkPalette? get artworkPalette => widget.palette;

  @override
  ValueListenable<String?>? artworkPathListenableOf(
    SonusArtworkAtmosphereBuilder widget,
  ) => widget.artworkPathListenable;

  @override
  String? artworkPathOf(SonusArtworkAtmosphereBuilder widget) =>
      widget.artworkPath;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    requestArtworkColors(Theme.of(context).brightness);

    final target = SonusArtworkAtmosphere.resolve(
      colors: tokens.colors,
      decoration: tokens.decoration,
      artwork: artworkColors,
    );
    final reduceMotion =
        tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<SonusAtmosphereColors>(
      tween: SonusAtmosphereColorsTween(end: SonusAtmosphereColors.of(target)),
      duration: reduceMotion ? Duration.zero : tokens.motion.baseMedium,
      curve: tokens.motion.curve,
      builder: (context, colors, _) => widget.builder(context, colors),
    );
  }
}
