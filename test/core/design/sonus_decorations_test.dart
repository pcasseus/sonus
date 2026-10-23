import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_artwork_frame.dart';
import 'package:sonus_next/core/design/widgets/sonus_decorations.dart';

const _markKey = ValueKey<String>('sonus-motif-mark');
const _textureKey = ValueKey<String>('sonus-surface-texture');

Widget _themed(SonusAppearanceSpec spec, Widget child) {
  return MaterialApp(
    theme: SonusThemeFactory.build(spec),
    // Each pump should show the new spec, not a frame of the transition.
    themeAnimationDuration: Duration.zero,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('every motif paints without errors', (tester) async {
    for (final themeId in SonusThemeId.values) {
      for (final decoration in SonusDecorationIntensity.values) {
        await tester.pumpWidget(
          _themed(
            SonusAppearanceSpec(themeId: themeId, decoration: decoration),
            const Column(
              children: [
                SonusSectionHeading(title: 'Popular This Week'),
                SizedBox(width: 200, height: 80, child: SonusSurfaceTexture()),
              ],
            ),
          ),
        );

        expect(tester.takeException(), isNull, reason: '$themeId $decoration');
        expect(
          find.byKey(_markKey),
          decoration == SonusDecorationIntensity.off
              ? findsNothing
              : findsOneWidget,
          reason: '$themeId $decoration',
        );
      }
    }
  });

  testWidgets('section heading is a header and its mark is hidden from '
      'assistive technology', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _themed(
        const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.expressive,
        ),
        const SonusSectionHeading(title: 'Top Artists'),
      ),
    );

    expect(
      tester.getSemantics(find.text('Top Artists')),
      matchesSemantics(label: 'Top Artists', isHeader: true),
    );
    expect(
      find.descendant(
        of: find.byType(ExcludeSemantics),
        matching: find.byKey(_markKey),
      ),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('texture shows only for textured themes at Standard or above', (
    tester,
  ) async {
    Future<Finder> pumpTexture(SonusAppearanceSpec spec) async {
      await tester.pumpWidget(
        _themed(
          spec,
          const SizedBox(width: 200, height: 80, child: SonusSurfaceTexture()),
        ),
      );
      return find.byKey(_textureKey);
    }

    expect(await pumpTexture(const SonusAppearanceSpec()), findsOneWidget);
    expect(
      await pumpTexture(
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.subtle),
      ),
      findsNothing,
    );
    expect(
      await pumpTexture(const SonusAppearanceSpec(lowEffects: true)),
      findsNothing,
    );
    expect(
      await pumpTexture(
        const SonusAppearanceSpec(themeId: SonusThemeId.monochrome),
      ),
      findsNothing,
    );
  });

  testWidgets('artwork frame clips to the theme radius and stays circular for '
      'portraits', (tester) async {
    await tester.pumpWidget(
      _themed(
        const SonusAppearanceSpec(themeId: SonusThemeId.kickflip),
        const Row(
          children: [
            SonusArtworkFrame(
              key: ValueKey<String>('square'),
              size: 80,
              child: SonusArtworkPlaceholder(),
            ),
            SonusArtworkFrame(
              key: ValueKey<String>('round'),
              size: 80,
              circular: true,
              child: SonusArtworkPlaceholder(),
            ),
          ],
        ),
      ),
    );

    ClipRRect clipOf(String key) => tester.widget<ClipRRect>(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(ClipRRect),
      ),
    );

    expect(clipOf('square').borderRadius, BorderRadius.circular(6));
    expect(clipOf('round').borderRadius, BorderRadius.circular(40));
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('square'))),
      const Size(80, 80),
    );
  });

  group('SonusTheme.of', () {
    testWidgets('falls back to the ambient scheme without a Sonus theme', (
      tester,
    ) async {
      late SonusThemeData tokens;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          ),
          home: Builder(
            builder: (context) {
              tokens = SonusTheme.of(context);
              return const SonusSectionHeading(title: 'Plain');
            },
          ),
        ),
      );

      final scheme = Theme.of(tester.element(find.text('Plain'))).colorScheme;

      expect(tokens.colors.accentPrimary, scheme.primary);
      expect(tokens.decoration.showMarks, isFalse);
      expect(find.byKey(_markKey), findsNothing);
    });

    testWidgets('follows the device reduced-motion request', (tester) async {
      late SonusThemeData tokens;

      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                tokens = SonusTheme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(tokens.motion.reduced, isTrue);
      expect(tokens.motion.medium, Duration.zero);
    });
  });
}
