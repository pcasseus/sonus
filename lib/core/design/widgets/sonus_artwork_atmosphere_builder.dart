import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../sonus_artwork_palette.dart';
import '../sonus_atmosphere_colors.dart';
import '../sonus_theme.dart';

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
    extends State<SonusArtworkAtmosphereBuilder> {
  String? _requestedPath;
  Brightness? _requestedBrightness;
  SonusArtworkColors? _artworkColors;

  String? get _artworkPath =>
      (widget.artworkPathListenable?.value ?? widget.artworkPath)?.trim();

  @override
  void initState() {
    super.initState();
    widget.artworkPathListenable?.addListener(_onArtworkChanged);
  }

  @override
  void didUpdateWidget(SonusArtworkAtmosphereBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.artworkPathListenable,
      widget.artworkPathListenable,
    )) {
      oldWidget.artworkPathListenable?.removeListener(_onArtworkChanged);
      widget.artworkPathListenable?.addListener(_onArtworkChanged);
    }
  }

  @override
  void dispose() {
    widget.artworkPathListenable?.removeListener(_onArtworkChanged);
    super.dispose();
  }

  /// Requests the new artwork's colours straight away, for the brightness
  /// last built with. A theme change rebuilds and requests again.
  void _onArtworkChanged() {
    final brightness = _requestedBrightness;
    if (brightness == null) return;
    _request(_artworkPath, brightness);
  }

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
    _request(_artworkPath, Theme.of(context).brightness);

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
