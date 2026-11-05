// Theme architecture T0: the contextual colours layer. A tinted context
// re-themes its subtree (tokens and Material components, including the
// menus, dialogs and sheets it opens); an untinted one changes nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/context/sonus_context_theme.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_contrast.dart';
import 'package:sonus_next/core/design/sonus_profile_colors.dart';
import 'package:sonus_next/core/design/sonus_theme.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';

const coolBlue = SonusArtworkColors(
  accent: Color(0xFF9BCDEA),
  container: Color(0xFF6597B2),
);
const warmOrange = SonusArtworkColors(
  accent: Color(0xFFFFB68F),
  container: Color(0xFFDA7639),
);

(ThemeData, SonusContextColors) contextFor(
  SonusAppearanceSpec spec,
  SonusArtworkColors? artwork,
) {
  final theme = SonusThemeFactory.build(spec);
  final colors = theme.extension<SonusColors>()!;
  final profile = SonusProfileColors.resolve(
    colors: colors,
    decoration: theme.extension<SonusDecorationTokens>()!,
    artwork: artwork,
  );
  return (theme, SonusContextColors.profile(profile, theme: colors));
}

void main() {
  test('an untinted context leaves the theme exactly as it is', () {
    for (final spec in const [
      SonusAppearanceSpec(),
      SonusAppearanceSpec(highContrast: true),
      SonusAppearanceSpec(lowEffects: true),
      SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
    ]) {
      final (theme, context) = contextFor(spec, coolBlue);
      if (spec == const SonusAppearanceSpec()) {
        expect(context.isTinted, isTrue);
        continue;
      }
      // Accessibility keeps profiles flat, so the context is the theme.
      expect(context.isTinted, isFalse);
      expect(
        identical(SonusContextTheme.themeFor(theme, context), theme),
        isTrue,
      );
    }
    final (theme, none) = contextFor(const SonusAppearanceSpec(), null);
    expect(none.isTinted, isFalse);
    expect(identical(SonusContextTheme.themeFor(theme, none), theme), isTrue);
  });

  test('a tinted context re-themes tokens and components, keeping every '
      'other extension', () {
    final (theme, context) = contextFor(const SonusAppearanceSpec(), coolBlue);
    final tinted = SonusContextTheme.themeFor(theme, context);
    final colors = tinted.extension<SonusColors>()!;

    expect(colors.background, context.background);
    expect(colors.surface, context.surface);
    expect(colors.accentPrimary, context.accent);
    expect(
      colors.accentPrimary,
      isNot(theme.extension<SonusColors>()!.accentPrimary),
    );
    expect(tinted.colorScheme.primary, context.accent);
    expect(tinted.popupMenuTheme.color, context.raisedSurface);
    expect(tinted.dialogTheme.backgroundColor, context.raisedSurface);
    expect(tinted.bottomSheetTheme.backgroundColor, context.raisedSurface);
    expect(tinted.progressIndicatorTheme.color, context.accent);

    // Every other token set is the theme's own.
    for (final type in [
      SonusTextStyles,
      SonusMetrics,
      SonusDecorationTokens,
      SonusMotion,
    ]) {
      expect(
        tinted.extensions[type],
        same(theme.extensions[type]),
        reason: '$type',
      );
    }
  });

  test('cool artwork gives a cool context, warm artwork a warm one', () {
    double hue(Color c) => HSLColor.fromColor(c).hue;
    final (_, cool) = contextFor(const SonusAppearanceSpec(), coolBlue);
    final (_, warm) = contextFor(const SonusAppearanceSpec(), warmOrange);
    expect(hue(cool.background), inInclusiveRange(180, 230));
    expect(hue(warm.background), inInclusiveRange(10, 40));
    expect(hue(cool.raisedSurface), inInclusiveRange(180, 230));
    expect(hue(warm.raisedSurface), inInclusiveRange(10, 40));
  });

  test('text stays readable on every context ground in every theme', () {
    for (final themeId in SonusThemeId.values) {
      for (final artwork in [coolBlue, warmOrange]) {
        final (_, context) = contextFor(
          SonusAppearanceSpec(themeId: themeId),
          artwork,
        );
        for (final ground in [
          context.background,
          context.surface,
          context.raisedSurface,
        ]) {
          expect(
            SonusContrast.ratio(context.textPrimary, ground),
            greaterThanOrEqualTo(4.5),
            reason: '${themeId.label} primary',
          );
          expect(
            SonusContrast.ratio(context.textSecondary, ground),
            greaterThanOrEqualTo(4.5),
            reason: '${themeId.label} secondary',
          );
        }
      }
    }
  });

  Widget host(ThemeData theme, SonusContextColors context, Widget child) =>
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SonusContextTheme(colors: context, child: child),
        ),
      );

  testWidgets('widgets inside read the page colours through SonusTheme', (
    tester,
  ) async {
    final (theme, context) = contextFor(const SonusAppearanceSpec(), coolBlue);
    late SonusContextColors seen;
    late Color tokenSurface;

    await tester.pumpWidget(
      host(
        theme,
        context,
        Builder(
          builder: (inner) {
            seen = SonusContextTheme.of(inner);
            tokenSurface = SonusTheme.of(inner).colors.surface;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(seen, context);
    expect(tokenSurface, context.surface);
  });

  testWidgets('outside any context, the theme is the context', (tester) async {
    final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
    late SonusContextColors seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (inner) {
            seen = SonusContextTheme.of(inner);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.isTinted, isFalse);
    expect(seen.surface, theme.extension<SonusColors>()!.surface);
  });

  testWidgets('dialogs, sheets and menus opened inside take the page colours', (
    tester,
  ) async {
    final (theme, context) = contextFor(
      const SonusAppearanceSpec(),
      warmOrange,
    );

    await tester.pumpWidget(
      host(
        theme,
        context,
        Builder(
          builder: (inner) => Column(
            children: [
              TextButton(
                onPressed: () => showDialog<void>(
                  context: inner,
                  builder: (_) => const AlertDialog(
                    key: ValueKey('dialog'),
                    content: Text('Dialog'),
                  ),
                ),
                child: const Text('open dialog'),
              ),
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: inner,
                  builder: (_) =>
                      const SizedBox(key: ValueKey('sheet'), height: 80),
                ),
                child: const Text('open sheet'),
              ),
              PopupMenuButton<int>(
                key: const ValueKey('menu'),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 1, child: Text('Item')),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    Color materialOf(Finder inside) => tester
        .widgetList<Material>(
          find.ancestor(of: inside, matching: find.byType(Material)),
        )
        .first
        .color!;

    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    expect(materialOf(find.text('Dialog')), context.raisedSurface);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    expect(
      materialOf(find.byKey(const ValueKey('sheet'))),
      context.raisedSurface,
    );
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('menu')));
    await tester.pumpAndSettle();
    expect(materialOf(find.text('Item')), context.raisedSurface);
  });
}
