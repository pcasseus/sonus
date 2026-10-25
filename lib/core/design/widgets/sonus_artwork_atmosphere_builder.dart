import 'dart:async';

import 'package:flutter/material.dart';

import '../sonus_artwork_palette.dart';
import '../sonus_atmosphere_colors.dart';
import '../sonus_theme.dart';

/// Builds with the artwork atmosphere for [artworkPath]: theme colours at
/// once, the artwork's colours once extracted, eased in (or switched at
/// once with reduced motion). Decoration Off, High contrast and Low
/// effects keep the theme colours, as on the Album Profile.
class SonusArtworkAtmosphereBuilder extends StatefulWidget {
  const SonusArtworkAtmosphereBuilder({
    super.key,
    required this.artworkPath,
    required this.builder,
    this.palette,
  });

  final String? artworkPath;

  /// Where artwork colours come from; the app-wide cache by default.
  final SonusArtworkPalette? palette;
  final Widget Function(BuildContext context, SonusAtmosphereColors colors)
  builder;

  @override
  State<SonusArtworkAtmosphereBuilder> createState() =>
      _SonusArtworkAtmosphereBuilderState();
}

class _SonusArtworkAtmosphereBuilderState
    extends State<SonusArtworkAtmosphereBuilder> {
  String? _requestedPath;
  Brightness? _requestedBrightness;
  SonusArtworkColors? _artworkColors;

  /// Never sets state synchronously, so it is safe to call while building.
  void _request(String? path, Brightness brightness) {
    if (path == _requestedPath && brightness == _requestedBrightness) return;
    _requestedPath = path;
    _requestedBrightness = brightness;

    final palette = widget.palette ?? SonusArtworkPalette.shared;
    unawaited(
      palette.colorsFor(path, brightness: brightness).then((colors) {
        if (!mounted ||
            path != _requestedPath ||
            brightness != _requestedBrightness ||
            colors == _artworkColors) {
          return;
        }
        setState(() => _artworkColors = colors);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    _request(widget.artworkPath?.trim(), Theme.of(context).brightness);

    final target = SonusArtworkAtmosphere.resolve(
      colors: tokens.colors,
      decoration: tokens.decoration,
      artwork: _artworkColors,
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
