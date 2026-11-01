import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_contrast.dart';
import '../../../../core/design/sonus_tokens.dart';
import '../../application/models/pulse/pulse_period_data.dart';

/// A colour in OKLCH: perceptual lightness (0–1), chroma and hue (degrees).
@immutable
class Oklch {
  const Oklch(this.l, this.c, this.h);

  final double l;
  final double c;
  final double h;

  factory Oklch.fromColor(Color color) {
    double lin(double v) => v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    final r = lin(color.r);
    final g = lin(color.g);
    final b = lin(color.b);
    final l = math.pow(
      0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
      1 / 3,
    );
    final m = math.pow(
      0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
      1 / 3,
    );
    final s = math.pow(
      0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
      1 / 3,
    );
    final okL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    final okA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    final okB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    final c = math.sqrt(okA * okA + okB * okB);
    final h = (math.atan2(okB, okA) * 180 / math.pi + 360) % 360;
    return Oklch(okL, c, h);
  }

  /// To sRGB, lowering chroma until the colour fits the sRGB gamut.
  Color toColor() {
    var chroma = c;
    for (var i = 0; i < 24; i++) {
      final rgb = _toLinearRgb(l, chroma, h);
      if (rgb.every((v) => v >= -1e-4 && v <= 1 + 1e-4)) {
        return _fromLinear(rgb);
      }
      chroma *= 0.88;
    }
    return _fromLinear(_toLinearRgb(l, 0, h));
  }

  static List<double> _toLinearRgb(double l, double c, double h) {
    final rad = h * math.pi / 180;
    final a = c * math.cos(rad);
    final b = c * math.sin(rad);
    final l1 = math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
    final m1 = math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
    final s1 = math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3).toDouble();
    return [
      4.0767416621 * l1 - 3.3077115913 * m1 + 0.2309699292 * s1,
      -1.2684380046 * l1 + 2.6097574011 * m1 - 0.3413193965 * s1,
      -0.0041960863 * l1 - 0.7034186147 * m1 + 1.7076147010 * s1,
    ];
  }

  static Color _fromLinear(List<double> rgb) {
    double gamma(double v) {
      final x = v.clamp(0.0, 1.0);
      return x <= 0.0031308
          ? 12.92 * x
          : 1.055 * math.pow(x, 1 / 2.4).toDouble() - 0.055;
    }

    return Color.from(
      alpha: 1,
      red: gamma(rgb[0]),
      green: gamma(rgb[1]),
      blue: gamma(rgb[2]),
    );
  }
}

/// How a Pulse family is filled (spec §7.5).
enum PulseFill {
  /// 64-step gradients.
  gradient,

  /// Decoration Off and Low effects: five solid steps.
  stepped,

  /// High contrast: one solid colour per metric.
  solid,
}

/// Bar pattern per metric, so Monochrome families differ by more than tone.
enum PulseBarPattern { solid, stripe, dotted }

/// One metric's colour family.
@immutable
class PulseRamp {
  const PulseRamp({
    required this.steps,
    required this.fill,
    required this.pattern,
  });

  /// From the base (inner ring) to the brightest tip.
  final List<Color> steps;
  final PulseFill fill;
  final PulseBarPattern pattern;

  Color get base => steps.first;
  Color get tip => steps.last;
  Color get mid => steps[steps.length ~/ 2];

  /// The comparison ghost's colour: the lightest step.
  Color get lightest => tip;

  /// The colour at [t] (0 = base, 1 = brightest).
  Color at(double t) {
    final index = (t.clamp(0.0, 1.0) * (steps.length - 1)).round();
    return steps[index];
  }
}

/// Every colour the Pulse hero and its metric bars use, derived from the
/// active Sonus theme (spec §7). Nothing is stored and the global theme is
/// never changed; an artwork accent is temporary and comes from
/// [SonusArtworkAtmosphere].
@immutable
class PulsePalette {
  const PulsePalette._({
    required this.minutes,
    required this.streams,
    required this.allPlays,
    required this.surface,
    required this.text,
    required this.textSecondary,
    required this.chartUp,
    required this.chartDown,
    required this.haloStrength,
    required this.allowGlow,
    required this.highContrast,
    required this.isMonochrome,
    required this.itemAccent,
    required this.itemOutlineOnly,
  });

  static const int gradientSteps = 64;
  static const int solidSteps = 5;

  /// Graphics contrast every ramp step keeps against [surface].
  static const double minimumContrast = 3;

  final PulseRamp minutes;
  final PulseRamp streams;

  /// Tiles and ranking bars only; never on the ring.
  final PulseRamp allPlays;
  final Color surface;
  final Color text;
  final Color textSecondary;
  final Color chartUp;
  final Color chartDown;

  /// Halo opacity: the atmosphere scale for the Decoration level, or 0
  /// under Decoration Off, Low effects or High contrast. Atmosphere only.
  final double haloStrength;
  final bool allowGlow;
  final bool highContrast;
  final bool isMonochrome;

  /// The selected item's colour: the artwork accent when one applies,
  /// otherwise null (theme colours).
  final Color? itemAccent;

  /// High contrast shows artwork colour only as an outline.
  final bool itemOutlineOnly;

  PulseRamp rampFor(PulseMeasure measure) => switch (measure) {
    PulseMeasure.minutes => minutes,
    PulseMeasure.streams => streams,
    PulseMeasure.allPlays => allPlays,
  };

  /// The halo colour: the item's artwork colour while one is selected,
  /// else the measure's mid colour.
  Color haloFor(PulseMeasure measure) => itemAccent ?? rampFor(measure).mid;

  /// The selected item's part of each spoke.
  Color itemColorFor(PulseMeasure measure) =>
      itemOutlineOnly ? text : (itemAccent ?? text);

  factory PulsePalette.resolve({
    required SonusColors colors,
    required SonusDecorationTokens decoration,
    bool highContrast = false,
    SonusArtworkColors? artwork,
  }) {
    final fill = highContrast
        ? PulseFill.solid
        : decoration.allowGradients
        ? PulseFill.gradient
        : PulseFill.stepped;
    final surface = colors.surface;
    final light =
        SonusContrast.ratio(surface, Colors.white) <
        SonusContrast.ratio(surface, Colors.black);
    final tokens = [
      colors.accentPrimary,
      colors.accentSecondary,
      colors.accentTertiary,
    ].map(Oklch.fromColor);
    final monochrome = tokens.every((c) => c.c < 0.02);
    final primary = Oklch.fromColor(colors.accentPrimary);
    final secondary = Oklch.fromColor(colors.accentSecondary);
    final tertiary = Oklch.fromColor(colors.accentTertiary);

    PulseRamp family(
      Oklch start,
      Oklch end,
      PulseBarPattern pattern, {
      required double lightFrom,
      required double lightTo,
    }) => PulseRamp(
      steps: _ramp(
        start,
        end,
        surface: surface,
        fill: fill,
        monochrome: monochrome,
        lightFrom: light ? 1 - lightFrom : lightFrom,
        lightTo: light ? 1 - lightTo : lightTo,
      ),
      fill: fill,
      pattern: monochrome ? pattern : PulseBarPattern.solid,
    );

    final PulseRamp minutes;
    final PulseRamp streams;
    final PulseRamp allPlays;
    if (monochrome) {
      // Spec §7.2: greyscale by tone and pattern; no tint.
      minutes = family(
        primary,
        primary,
        PulseBarPattern.solid,
        lightFrom: 0.42,
        lightTo: 0.98,
      );
      streams = family(
        secondary,
        secondary,
        PulseBarPattern.stripe,
        lightFrom: 0.42,
        lightTo: 0.84,
      );
      allPlays = family(
        tertiary,
        tertiary,
        PulseBarPattern.dotted,
        lightFrom: 0.62,
        lightTo: 0.98,
      );
    } else {
      minutes = family(
        primary,
        tertiary,
        PulseBarPattern.solid,
        lightFrom: 0.58,
        lightTo: 0.88,
      );
      streams = family(
        secondary,
        tertiary,
        PulseBarPattern.solid,
        lightFrom: 0.58,
        lightTo: 0.88,
      );
      // All plays shares Minutes' hues in reverse (spec §7.1), so where
      // primary and tertiary are close it sits on a lighter band to stay
      // distinct. It is never on the ring, only in tiles and bars.
      allPlays = family(
        tertiary,
        primary,
        PulseBarPattern.solid,
        lightFrom: 0.70,
        lightTo: 0.94,
      );
    }

    final atmosphere = SonusArtworkAtmosphere.resolve(
      colors: colors,
      decoration: decoration,
      artwork: artwork,
    );
    // The accent shows whenever artwork has colour; under high contrast or
    // without gradients it stays an outline / solid, never a tint.
    final Color? accent = artwork == null
        ? null
        : atmosphere.isTinted
        ? atmosphere.accent
        : _readableAccent(artwork.accent, surface);

    return PulsePalette._(
      minutes: minutes,
      streams: streams,
      allPlays: allPlays,
      surface: surface,
      text: colors.textPrimary,
      textSecondary: colors.textSecondary,
      chartUp: colors.chartUp,
      chartDown: colors.chartDown,
      haloStrength: highContrast || !decoration.allowGradients
          ? 0
          : SonusArtworkAtmosphere.strengthFor(decoration.intensity),
      allowGlow: decoration.allowGlow && !highContrast,
      highContrast: highContrast,
      isMonochrome: monochrome,
      itemAccent: accent,
      itemOutlineOnly: highContrast && accent != null,
    );
  }

  static List<Color> _ramp(
    Oklch start,
    Oklch end, {
    required Color surface,
    required PulseFill fill,
    required bool monochrome,
    required double lightFrom,
    required double lightTo,
  }) {
    final count = switch (fill) {
      PulseFill.gradient => gradientSteps,
      PulseFill.stepped => solidSteps,
      PulseFill.solid => 1,
    };
    var hueDelta = ((end.h - start.h + 540) % 360) - 180;
    // Near-identical hues: vary lightness only (spec §7.2).
    if (hueDelta.abs() < 12) hueDelta = 0;
    return List.unmodifiable([
      for (var i = 0; i < count; i++)
        _ensureContrast(
          Oklch(
            // A single solid colour sits high on the ramp.
            count == 1 ? lightTo : _lerp(lightFrom, lightTo, i / (count - 1)),
            monochrome
                ? 0
                : math.max(
                    0.12,
                    _lerp(start.c, end.c, count == 1 ? 0.5 : i / (count - 1)),
                  ),
            (start.h + hueDelta * (count == 1 ? 0.5 : i / (count - 1)) + 360) %
                360,
          ),
          surface,
        ),
    ]);
  }

  /// Moves lightness away from [surface] until the step keeps 3:1.
  static Color _ensureContrast(Oklch colour, Color surface) {
    final surfaceL = Oklch.fromColor(surface).l;
    final direction = colour.l >= surfaceL ? 1.0 : -1.0;
    var current = colour;
    var result = current.toColor();
    for (var i = 0; i < 60; i++) {
      if (SonusContrast.ratio(result, surface) >= minimumContrast) break;
      current = Oklch(
        (current.l + 0.01 * direction).clamp(0.0, 1.0),
        current.c,
        current.h,
      );
      result = current.toColor();
    }
    return result;
  }

  static Color _readableAccent(Color accent, Color surface) =>
      _ensureContrast(Oklch.fromColor(accent), surface);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
