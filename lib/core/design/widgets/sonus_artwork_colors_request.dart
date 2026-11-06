import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../sonus_artwork_palette.dart';

/// Requests an artwork's colours for a State and keeps the latest result,
/// shared by the artwork atmosphere builders.
///
/// The artwork is a fixed path or, through [artworkPathListenableOf], one
/// that changes without a rebuild: then its colours are requested as soon
/// as it is notified. Requests never set state synchronously, so they are
/// safe while building, and a result for artwork that has since changed is
/// dropped.
mixin SonusArtworkColorsRequest<W extends StatefulWidget> on State<W> {
  /// The palette of [widget]; the app-wide cache when null.
  SonusArtworkPalette? get artworkPalette;

  /// The artwork path that [widget] (or an older widget) follows, if any.
  ValueListenable<String?>? artworkPathListenableOf(W widget);

  /// The fixed artwork path of [widget], used without a listenable.
  String? artworkPathOf(W widget);

  /// The artwork colours received last; null for none (no artwork, or
  /// none worth tinting with).
  SonusArtworkColors? get artworkColors => _artworkColors;

  String? _requestedPath;
  Brightness? _requestedBrightness;
  SonusArtworkColors? _artworkColors;

  /// The artwork path now, trimmed.
  String? get currentArtworkPath =>
      (artworkPathListenableOf(widget)?.value ?? artworkPathOf(widget))?.trim();

  @override
  void initState() {
    super.initState();
    artworkPathListenableOf(widget)?.addListener(_onArtworkChanged);
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = artworkPathListenableOf(oldWidget);
    final after = artworkPathListenableOf(widget);
    if (!identical(before, after)) {
      before?.removeListener(_onArtworkChanged);
      after?.addListener(_onArtworkChanged);
    }
  }

  @override
  void dispose() {
    artworkPathListenableOf(widget)?.removeListener(_onArtworkChanged);
    super.dispose();
  }

  /// Requests the new artwork's colours straight away, for the brightness
  /// last requested. A theme change rebuilds and requests again.
  void _onArtworkChanged() {
    final brightness = _requestedBrightness;
    if (brightness == null) return;
    requestArtworkColors(brightness);
  }

  /// Asks for the colours of [currentArtworkPath] for [brightness], unless
  /// they were already asked for. Never sets state synchronously.
  void requestArtworkColors(Brightness brightness) {
    final path = currentArtworkPath;
    if (path == _requestedPath && brightness == _requestedBrightness) return;
    _requestedPath = path;
    _requestedBrightness = brightness;

    final palette = artworkPalette ?? SonusArtworkPalette.shared;
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
}
