// T0 parity: the profile, cinematic and atmosphere resolvers keep exactly
// the outputs they had before they were moved onto the shared artwork-tint
// engine (lib/core/design/artwork/sonus_artwork_tint.dart). Every theme,
// every decoration level, High contrast and Low effects, with real and
// synthetic artwork. The expected fingerprints were recorded from the code
// before the refactor (commit 0dedca6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_cinematic_colors.dart';
import 'package:sonus_next/core/design/sonus_profile_colors.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';

const recording = bool.fromEnvironment('RECORD_PARITY');

/// Artwork as SonusArtworkPalette extracts it (real library values and
/// synthetic shapes), plus none.
const artworks = <SonusArtworkColors?>[
  null,
  SonusArtworkColors(accent: Color(0xFF9BCDEA), container: Color(0xFF6597B2)),
  SonusArtworkColors(accent: Color(0xFFB6C8DC), container: Color(0xFF374858)),
  SonusArtworkColors(accent: Color(0xFFFFB68F), container: Color(0xFFDA7639)),
  SonusArtworkColors(accent: Color(0xFFFFFFFF), container: Color(0xFFECE913)),
  SonusArtworkColors(accent: Color(0xFFFFB4AA), container: Color(0xFFBD2821)),
  SonusArtworkColors(accent: Color(0xFFFFB3B4), container: Color(0xFFFD5463)),
  SonusArtworkColors(accent: Color(0xFFA6F2AE), container: Color(0xFF6FCF7A)),
  SonusArtworkColors(accent: Color(0xFF8FD99A), container: Color(0xFF1C5228)),
  SonusArtworkColors(accent: Color(0xFFF4F6F8), container: Color(0xFFE8ECF0)),
  SonusArtworkColors(accent: Color(0xFF101010), container: Color(0xFF050505)),
];

List<SonusAppearanceSpec> specs() => [
  for (final themeId in SonusThemeId.values)
    for (final decoration in SonusDecorationIntensity.values)
      SonusAppearanceSpec(themeId: themeId, decoration: decoration),
  const SonusAppearanceSpec(highContrast: true),
  const SonusAppearanceSpec(lowEffects: true),
  const SonusAppearanceSpec(
    decoration: SonusDecorationIntensity.expressive,
    highContrast: true,
  ),
];

String hex(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0');

/// FNV-1a 64-bit over the text, as hex: a stable fingerprint.
String fnv(String text) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toUnsigned(64).toRadixString(16);
}

String profile(SonusColors colors, SonusDecorationTokens decoration) => [
  for (final artwork in artworks)
    () {
      final p = SonusProfileColors.resolve(
        colors: colors,
        decoration: decoration,
        artwork: artwork,
      );
      final parts = [
        p.background,
        p.backgroundDeep,
        p.surface,
        p.edge,
        p.glow,
        p.light,
        p.accent,
        p.onAccent,
        p.textPrimary,
        p.textSecondary,
      ].map(hex).join(',');
      return '$parts:${p.strength.toStringAsFixed(6)}';
    }(),
].join('|');

String cinematic(SonusDecorationTokens decoration) => [
  for (final artwork in artworks)
    () {
      final c = SonusCinematicColors.resolve(
        decoration: decoration,
        artwork: artwork,
      );
      final parts = [
        c.background,
        c.backgroundDeep,
        c.surface,
        c.edge,
        c.glow,
        c.accent,
        c.onAccent,
        c.textPrimary,
        c.textSecondary,
      ].map(hex).join(',');
      return '$parts:${c.strength.toStringAsFixed(6)}';
    }(),
].join('|');

String atmosphere(SonusColors colors, SonusDecorationTokens decoration) => [
  for (final artwork in artworks)
    () {
      final a = SonusArtworkAtmosphere.resolve(
        colors: colors,
        decoration: decoration,
        artwork: artwork,
      );
      final parts = [
        a.background,
        a.surface,
        a.accent,
        a.onAccent,
      ].map(hex).join(',');
      return '$parts:${a.strength.toStringAsFixed(6)}';
    }(),
].join('|');

Map<String, String> fingerprints() {
  final result = <String, String>{};
  for (final spec in specs()) {
    final theme = SonusThemeFactory.build(spec);
    final colors = theme.extension<SonusColors>()!;
    final decoration = theme.extension<SonusDecorationTokens>()!;
    final key =
        '${spec.themeId.name}/${spec.decoration.name}'
        '${spec.highContrast ? '/hc' : ''}${spec.lowEffects ? '/le' : ''}';
    result[key] = [
      fnv(profile(colors, decoration)),
      fnv(cinematic(decoration)),
      fnv(atmosphere(colors, decoration)),
    ].join(' ');
  }
  return result;
}

/// Recorded before the refactor (0dedca6): profile cinematic atmosphere.
const expected = <String, String>{
  'concreteSpray/off': '7009c6dffb9e5461 -45ae9337d5cb6e30 -66346956b5005a78',
  'concreteSpray/subtle': '30478c9ea84e287f 16682d083a57d7 3cffd9bd7eb1c26b',
  'concreteSpray/standard':
      '66b8856cabd8ecfb -53d8bfa253a2d36e 4454c4aca8b44eb7',
  'concreteSpray/expressive':
      '73645bbb970fb9de -16a3a7c7493c50f9 -3dd9a6f28f4e3d1b',
  'kickflip/off': '-15db423482bd2e64 -45ae9337d5cb6e30 -7d88e74290d0e9ba',
  'kickflip/subtle': '63b7d9673c9168fa 16682d083a57d7 14f1ee14959efae',
  'kickflip/standard': '680575df8c0746e9 -53d8bfa253a2d36e -35b7137ea33ba986',
  'kickflip/expressive': '-fcc6a81ccf3ddb6 -16a3a7c7493c50f9 76a94f4d79205d17',
  'afterHours/off': '60907cc14795633 -45ae9337d5cb6e30 -67343f0a6cf14829',
  'afterHours/subtle': '34caa4e3034cb3c4 16682d083a57d7 7c3852cd086576e8',
  'afterHours/standard':
      '-3a0db12602b74351 -53d8bfa253a2d36e -7a4a1c64b017ddfa',
  'afterHours/expressive':
      '-4b8535958c4259d6 -16a3a7c7493c50f9 -3d65d8daee206cf1',
  'y2kReplay/off': '-73daebb4453289a4 -45ae9337d5cb6e30 3fbd837726d9c4b',
  'y2kReplay/subtle': '533a0a1b5e067b6b 16682d083a57d7 7adf6e0dac5193a6',
  'y2kReplay/standard': '2d9433a196b07100 -53d8bfa253a2d36e -cbf5c2ac21da0ed',
  'y2kReplay/expressive':
      '31b190cc0d385de9 -16a3a7c7493c50f9 -6e63db5481b7b5a9',
  'neonMixtape/off': '-328dfe076f45eed7 -45ae9337d5cb6e30 a47d881f62df2e7',
  'neonMixtape/subtle': '2946ef7d430955de 16682d083a57d7 2a44bd15e04c136b',
  'neonMixtape/standard':
      '5afe7da97a6ccb54 -53d8bfa253a2d36e -1d79241dd7aa3f94',
  'neonMixtape/expressive':
      '-a5bbd37613e7f63 -16a3a7c7493c50f9 30619725f55c84d5',
  'haze2017/off': '235ce15adc1bee79 -45ae9337d5cb6e30 -7e217dfb6201f24c',
  'haze2017/subtle': '-50ad1773f716257e 16682d083a57d7 8ce0abc65468938',
  'haze2017/standard': '-7d2fa334296bf835 -53d8bfa253a2d36e 71b1df8394d6ef8b',
  'haze2017/expressive':
      '-1673b699c8570a41 -16a3a7c7493c50f9 -4248bd8ce71beb44',
  'monochrome/off': '6429ff5d0c77eeab -45ae9337d5cb6e30 2b7c73773eac1f6f',
  'monochrome/subtle': '-76818f0a5634e260 16682d083a57d7 71d6a33c15b89dad',
  'monochrome/standard':
      '-11782cc2ffbf6722 -53d8bfa253a2d36e -5e1eb1490609d558',
  'monochrome/expressive':
      '-683f03a37fc4b95c -16a3a7c7493c50f9 7afbfe8299a66e3f',
  'daylight/off': '-5e3c1e765dee32ee -45ae9337d5cb6e30 6f5c39aa47a64bcd',
  'daylight/subtle': '3e8a900f2033c8e1 16682d083a57d7 -185ea9aa6948935f',
  'daylight/standard': '-4a7461965b848707 -53d8bfa253a2d36e -7f065fcd3940ef98',
  'daylight/expressive': '5aef3830536729e -16a3a7c7493c50f9 -22bb07168716d28d',
  'evergreen/off': '-6d8ef93991e39e40 -45ae9337d5cb6e30 6a432e65ef8d3b7e',
  'evergreen/subtle': '410a49faddebaf68 16682d083a57d7 -70a004ab9a32fb22',
  'evergreen/standard': '18917296dd2130ce -53d8bfa253a2d36e -540e8dd5797a1946',
  'evergreen/expressive': '78c4af518878ce24 -16a3a7c7493c50f9 46d33bbbdc0951b2',
  'concreteSpray/standard/hc':
      '-4597a38c3d47107e -45ae9337d5cb6e30 -66346956b5005a78',
  'concreteSpray/standard/le':
      '7009c6dffb9e5461 -45ae9337d5cb6e30 -66346956b5005a78',
  'concreteSpray/expressive/hc':
      '-4597a38c3d47107e -45ae9337d5cb6e30 -66346956b5005a78',
};

void main() {
  test('resolver outputs are unchanged by the shared engine', () {
    final actual = fingerprints();
    if (recording) {
      // ignore: avoid_print
      for (final MapEntry(:key, :value) in actual.entries) {
        // ignore: avoid_print
        print("  '$key': '$value',");
      }
      return;
    }
    expect(actual.keys.toSet(), expected.keys.toSet());
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(actual[key], value, reason: key);
    }
  });
}
