import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../sonus_artwork_palette.dart';
import '../sonus_profile_colors.dart';
import '../sonus_theme.dart';
import 'sonus_artwork_colors_request.dart';

/// Builds with the profile colours for [artworkPath] (UI redesign P1, P2):
/// theme colours at once, then the artwork's, eased in (or switched at
/// once with reduced motion). Decoration Off, High contrast and Low effects
/// keep the theme's colours (see [SonusProfileColors.resolve]).
///
/// Pages whose artwork is decided by a controller that notifies without
/// rebuilding them use [SonusProfileAtmosphereBuilder.listenable].
class SonusProfileAtmosphereBuilder extends StatefulWidget {
  const SonusProfileAtmosphereBuilder({
    super.key,
    required this.artworkPath,
    required this.builder,
    this.palette,
  }) : artworkPathListenable = null;

  /// Follows [artworkPath] as it changes, requesting the new artwork's
  /// colours as soon as it is notified.
  const SonusProfileAtmosphereBuilder.listenable({
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

  final Widget Function(BuildContext context, SonusProfileColors colors)
  builder;

  @override
  State<SonusProfileAtmosphereBuilder> createState() =>
      _SonusProfileAtmosphereBuilderState();
}

class _SonusProfileAtmosphereBuilderState
    extends State<SonusProfileAtmosphereBuilder>
    with SonusArtworkColorsRequest<SonusProfileAtmosphereBuilder> {
  @override
  SonusArtworkPalette? get artworkPalette => widget.palette;

  @override
  ValueListenable<String?>? artworkPathListenableOf(
    SonusProfileAtmosphereBuilder widget,
  ) => widget.artworkPathListenable;

  @override
  String? artworkPathOf(SonusProfileAtmosphereBuilder widget) =>
      widget.artworkPath;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    // Profiles follow the theme's brightness (D3, as confirmed): pale tones
    // for a light theme, deep ones for a dark theme.
    requestArtworkColors(Theme.of(context).brightness);

    final target = SonusProfileColors.resolve(
      colors: tokens.colors,
      decoration: tokens.decoration,
      artwork: artworkColors,
    );
    final reduceMotion =
        tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<SonusProfileColors>(
      tween: SonusProfileColorsTween(end: target),
      duration: reduceMotion ? Duration.zero : tokens.motion.baseMedium,
      curve: tokens.motion.curve,
      builder: (context, colors, _) => widget.builder(context, colors),
    );
  }
}
