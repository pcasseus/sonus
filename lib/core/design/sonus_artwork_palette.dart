import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'sonus_contrast.dart';
import 'sonus_tokens.dart';

/// Colours taken from one piece of artwork, toned for the theme's
/// brightness.
@immutable
class SonusArtworkColors {
  const SonusArtworkColors({required this.accent, required this.container});

  /// A clear tone of the artwork's main colour, usable as an accent.
  final Color accent;

  /// A deep tone of the same colour, used to tint backgrounds.
  final Color container;

  @override
  bool operator ==(Object other) =>
      other is SonusArtworkColors &&
      other.accent == accent &&
      other.container == container;

  @override
  int get hashCode => Object.hash(accent, container);
}

/// Extracts [SonusArtworkColors] from an already-sized image, or returns
/// null when the artwork has no usable colour.
typedef SonusArtworkColorExtractor =
    Future<SonusArtworkColors?> Function(
      ImageProvider image,
      Brightness brightness,
    );

/// Artwork colours for atmospheric styling, with a bounded in-memory cache.
///
/// Artwork is decoded at [decodeWidth] pixels, never at full resolution.
/// Results are cached by path, file size and modification time, so
/// replacing a cover invalidates its entry. Missing, unreadable and
/// greyscale artwork yield null: callers fall back to theme colours.
/// Nothing is persisted.
class SonusArtworkPalette {
  SonusArtworkPalette({
    this.capacity = 48,
    this.decodeWidth = 96,
    SonusArtworkColorExtractor? extractor,
  }) : assert(capacity > 0),
       _extractor = extractor ?? extractFromImage;

  /// The app-wide cache, used when no palette is provided above a page.
  static final SonusArtworkPalette shared = SonusArtworkPalette();

  /// Most artworks remembered at once; the least recently used is dropped.
  final int capacity;

  /// Width artwork is decoded at before colours are measured.
  final int decodeWidth;

  final SonusArtworkColorExtractor _extractor;
  // Insertion-ordered, so the first key is the least recently used.
  final _entries = <_CacheKey, Future<SonusArtworkColors?>>{};

  /// Number of cached artworks.
  int get cachedCount => _entries.length;

  /// Colours for the artwork at [artworkPath], or null to use the theme.
  Future<SonusArtworkColors?> colorsFor(
    String? artworkPath, {
    required Brightness brightness,
  }) async {
    final path = artworkPath?.trim();
    if (path == null || path.isEmpty) return null;

    final FileStat stat;
    try {
      stat = await File(path).stat();
    } on FileSystemException catch (error, stackTrace) {
      _log('Artwork could not be read', error, stackTrace);
      return null;
    }
    if (stat.type != FileSystemEntityType.file) return null;

    final key = _CacheKey(
      path: path,
      size: stat.size,
      modified: stat.modified,
      brightness: brightness,
    );

    final cached = _entries.remove(key);
    if (cached != null) {
      // Re-inserted below: most recently used last.
      _entries[key] = cached;
      return cached;
    }

    final result = _extract(path, brightness);
    _entries[key] = result;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return result;
  }

  /// Forgets every cached artwork.
  void clear() => _entries.clear();

  Future<SonusArtworkColors?> _extract(
    String path,
    Brightness brightness,
  ) async {
    try {
      return await _extractor(
        ResizeImage(FileImage(File(path)), width: decodeWidth),
        brightness,
      );
    } on Object catch (error, stackTrace) {
      _log('Artwork colours could not be extracted', error, stackTrace);
      return null;
    }
  }

  /// The default extractor: Flutter's Material colour extraction, after a
  /// greyscale check.
  ///
  /// Material's scoring ignores low-chroma colours and falls back to a
  /// stock blue for black, white or grey covers, which would tint a
  /// monochrome cover blue; such artwork is reported as having no colour.
  static Future<SonusArtworkColors?> extractFromImage(
    ImageProvider image,
    Brightness brightness,
  ) async {
    if (await _isGreyscale(image)) return null;

    final scheme = await ColorScheme.fromImageProvider(
      provider: image,
      brightness: brightness,
      // Fidelity keeps the artwork's own chroma instead of muting it.
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return SonusArtworkColors(
      accent: scheme.primary,
      container: scheme.primaryContainer,
    );
  }

  /// Share of pixels that must carry colour for artwork to count as
  /// coloured.
  static const double minimumColourfulShare = 0.05;

  static Future<bool> _isGreyscale(ImageProvider provider) async {
    final image = await _decode(provider);
    final bytes = await image.toByteData();
    if (bytes == null) return true;

    var visible = 0;
    var colourful = 0;
    for (var offset = 0; offset + 3 < bytes.lengthInBytes; offset += 4) {
      if (bytes.getUint8(offset + 3) < 128) continue;
      visible++;
      final r = bytes.getUint8(offset);
      final g = bytes.getUint8(offset + 1);
      final b = bytes.getUint8(offset + 2);
      final high = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final low = r < g ? (r < b ? r : b) : (g < b ? g : b);
      if (high - low > 24) colourful++;
    }
    return visible == 0 || colourful / visible < minimumColourfulShare;
  }

  static Future<ui.Image> _decode(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        stream.removeListener(listener);
        throw TimeoutException('Artwork did not decode in time');
      },
    );
  }

  static void _log(String message, Object error, StackTrace stackTrace) {
    // The artwork path is not logged: it can name the user's own folders.
    developer.log(
      '$message (${error.runtimeType})',
      name: 'sonus.design.artwork_palette',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

@immutable
class _CacheKey {
  const _CacheKey({
    required this.path,
    required this.size,
    required this.modified,
    required this.brightness,
  });

  final String path;
  final int size;
  final DateTime modified;
  final Brightness brightness;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      other.path == path &&
      other.size == size &&
      other.modified == modified &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(path, size, modified, brightness);
}

/// Theme colours tinted by artwork, ready for an atmospheric page.
///
/// The active theme stays the foundation: artwork only nudges its
/// background, surface and accent. Strength follows the Decoration
/// setting; Off, High contrast and Low effects (which disallow gradients)
/// leave the theme untouched. Text keeps at least 4.5:1 against the tinted
/// background and surface, or never less than the theme itself offers, and
/// the accent keeps at least 3:1 against both.
@immutable
class SonusArtworkAtmosphere {
  const SonusArtworkAtmosphere._({
    required this.background,
    required this.surface,
    required this.accent,
    required this.onAccent,
    required this.strength,
  });

  /// Resolves the atmosphere for [artwork] on the theme [colors] under
  /// [decoration].
  factory SonusArtworkAtmosphere.resolve({
    required SonusColors colors,
    required SonusDecorationTokens decoration,
    SonusArtworkColors? artwork,
  }) {
    final target = artwork == null || !decoration.allowGradients
        ? 0.0
        : strengthFor(decoration.intensity);

    // Weaken the tint until text stays as readable as the theme demands.
    var strength = target;
    while (strength > 0 && !_textReadable(colors, artwork!, strength)) {
      strength = (strength - 0.02).clamp(0.0, 1.0);
    }

    if (artwork == null || strength == 0) {
      return SonusArtworkAtmosphere._(
        background: colors.background,
        surface: colors.surface,
        accent: colors.accentPrimary,
        onAccent: colors.onAccentPrimary,
        strength: 0,
      );
    }

    final background = _tint(colors.background, artwork, strength);
    final surface = _tint(colors.surface, artwork, strength * 0.8);
    final accent = _accent(colors, decoration, artwork, background, surface);

    return SonusArtworkAtmosphere._(
      background: background,
      surface: surface,
      accent: accent,
      onAccent: accent == colors.accentPrimary
          ? colors.onAccentPrimary
          : _onColour(accent),
      strength: strength,
    );
  }

  /// Page background.
  final Color background;

  /// Cards and the track-list area.
  final Color surface;

  /// Selected controls and accent details.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// How strongly the artwork tints the theme, from 0 (not at all) to 1.
  final double strength;

  /// Whether the artwork changes anything.
  bool get isTinted => strength > 0;

  /// Tint strength for each Decoration level.
  static double strengthFor(SonusDecorationIntensity intensity) =>
      switch (intensity) {
        SonusDecorationIntensity.off => 0,
        SonusDecorationIntensity.subtle => 0.1,
        SonusDecorationIntensity.standard => 0.2,
        SonusDecorationIntensity.expressive => 0.32,
      };

  static Color _tint(Color base, SonusArtworkColors artwork, double amount) =>
      Color.lerp(base, artwork.container, amount)!;

  static bool _textReadable(
    SonusColors colors,
    SonusArtworkColors artwork,
    double strength,
  ) {
    final pairs = [
      (
        colors.textPrimary,
        colors.background,
        _tint(colors.background, artwork, strength),
      ),
      (
        colors.textSecondary,
        colors.background,
        _tint(colors.background, artwork, strength),
      ),
      (
        colors.textPrimary,
        colors.surface,
        _tint(colors.surface, artwork, strength * 0.8),
      ),
      (
        colors.textSecondary,
        colors.surface,
        _tint(colors.surface, artwork, strength * 0.8),
      ),
    ];
    for (final (text, themeGround, tinted) in pairs) {
      final required = SonusContrast.ratio(text, themeGround).clamp(1.0, 4.5);
      if (SonusContrast.ratio(text, tinted) < required) return false;
    }
    return true;
  }

  static Color _accent(
    SonusColors colors,
    SonusDecorationTokens decoration,
    SonusArtworkColors artwork,
    Color background,
    Color surface,
  ) {
    // Subtle keeps the theme's own accent: blending two unrelated hues
    // gives a muddy colour, so only the background and surface are tinted.
    if (decoration.intensity == SonusDecorationIntensity.subtle) {
      return colors.accentPrimary;
    }
    final candidate = artwork.accent;
    final distinct =
        SonusContrast.ratio(candidate, background) >= 3 &&
        SonusContrast.ratio(candidate, surface) >= 3;
    return distinct ? candidate : colors.accentPrimary;
  }

  /// Black or white, whichever reads better on [colour] (always ≥ 4.5:1).
  static Color _onColour(Color colour) {
    const dark = Color(0xFF000000);
    const light = Color(0xFFFFFFFF);
    return SonusContrast.ratio(dark, colour) >=
            SonusContrast.ratio(light, colour)
        ? dark
        : light;
  }
}
