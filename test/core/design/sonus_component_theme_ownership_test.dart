// Cleanup sprint, Group E (Stage 3, non-visual): the theme owns the app
// bar's Material defaults. Pages no longer repeat
// `surfaceTintColor: Colors.transparent`; these tests prove every bar
// resolves to the same values it had when each page set them itself.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/context/sonus_context_theme.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_profile_colors.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';

const _specs = <String, SonusAppearanceSpec Function(SonusThemeId)>{
  'standard': _standard,
  'high contrast': _highContrast,
  'Decoration Off': _decorationOff,
  'low effects': _lowEffects,
  'reduced motion': _reducedMotion,
};

SonusAppearanceSpec _standard(SonusThemeId id) =>
    SonusAppearanceSpec(themeId: id);
SonusAppearanceSpec _highContrast(SonusThemeId id) =>
    SonusAppearanceSpec(themeId: id, highContrast: true);
SonusAppearanceSpec _decorationOff(SonusThemeId id) =>
    SonusAppearanceSpec(themeId: id, decoration: SonusDecorationIntensity.off);
SonusAppearanceSpec _lowEffects(SonusThemeId id) =>
    SonusAppearanceSpec(themeId: id, lowEffects: true);
SonusAppearanceSpec _reducedMotion(SonusThemeId id) =>
    SonusAppearanceSpec(themeId: id, reduceMotion: true);

/// The tinted Profile context the Album and Artist Profiles build.
ThemeData _profileContext(ThemeData theme) {
  final colors = theme.extension<SonusColors>()!;
  final profile = SonusProfileColors.resolve(
    colors: colors,
    decoration: theme.extension<SonusDecorationTokens>()!,
    artwork: const SonusArtworkColors(
      accent: Color(0xFFFFB68F),
      container: Color(0xFFDA7639),
    ),
  );
  return SonusContextTheme.themeFor(
    theme,
    SonusContextColors.profile(profile, theme: colors),
  );
}

void main() {
  test('every theme and mode gives app bars no tint and no elevation', () {
    for (final id in SonusThemeId.values) {
      for (final MapEntry(key: mode, value: spec) in _specs.entries) {
        final theme = SonusThemeFactory.build(spec(id));
        final colors = theme.extension<SonusColors>()!;
        final bar = theme.appBarTheme;
        final reason = '${id.label}, $mode';

        expect(bar.surfaceTintColor, Colors.transparent, reason: reason);
        expect(bar.elevation, 0, reason: reason);
        expect(bar.scrolledUnderElevation, 0, reason: reason);
        expect(bar.backgroundColor, colors.background, reason: reason);
        expect(bar.foregroundColor, colors.textPrimary, reason: reason);
      }
    }
  });

  test('the tinted Profile context keeps the app bar theme as it is', () {
    for (final id in SonusThemeId.values) {
      final theme = SonusThemeFactory.build(SonusAppearanceSpec(themeId: id));
      final tinted = _profileContext(theme);
      expect(tinted.appBarTheme, theme.appBarTheme, reason: id.label);
    }
  });

  // What a page's bar actually draws, at rest and scrolled under. Every
  // screen runs under the Sonus theme (one MaterialApp; the Profile
  // context inherits its app bar theme), so these are the cases that ship.
  for (final (name, theme) in [
    ('Sonus theme', SonusThemeFactory.build(const SonusAppearanceSpec())),
    (
      'Sonus theme, Profile context',
      _profileContext(SonusThemeFactory.build(const SonusAppearanceSpec())),
    ),
  ]) {
    testWidgets('$name: the bar draws no surface tint', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            appBar: AppBar(title: const Text('Page')),
            body: ListView(
              controller: scroll,
              children: [
                for (var i = 0; i < 60; i++) ListTile(title: Text('$i')),
              ],
            ),
          ),
        ),
      );

      Material bar() => tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppBar),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(bar().surfaceTintColor, Colors.transparent);
      expect(bar().elevation, 0);

      scroll.jumpTo(400);
      await tester.pumpAndSettle();
      // Scrolled under: still no tint (the elevation is the theme's, 0 with
      // the Sonus theme, and the tint is what pages used to clear).
      expect(bar().surfaceTintColor, Colors.transparent);
      expect(bar().elevation, 0);
    });
  }

  // The boundary of the change: without the Sonus theme (some widget tests
  // build a bare MaterialApp), Flutter's Material 3 fallback tints the bar
  // with the scheme, so the theme, not each page, now owns the clear tint.
  testWidgets('bare Material 3 would tint the bar: the theme owns it', (
    tester,
  ) async {
    final bare = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: bare,
        home: Scaffold(appBar: AppBar(title: const Text('Page'))),
      ),
    );
    final bar = tester.widget<Material>(
      find
          .descendant(of: find.byType(AppBar), matching: find.byType(Material))
          .first,
    );
    expect(bar.surfaceTintColor, bare.colorScheme.surfaceTint);
  });
}
