import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/widgets/sonus_brand_mark.dart';

void main() {
  testWidgets('every concept paints in every style and size', (tester) async {
    for (final concept in SonusBrandConcept.values) {
      for (final style in SonusBrandMarkStyle.values) {
        for (final size in [24.0, 48.0, 108.0]) {
          await tester.pumpWidget(
            _wrap(SonusBrandMark(concept: concept, style: style, size: size)),
          );

          expect(tester.takeException(), isNull, reason: '$concept $style');
          expect(
            tester.getSize(find.byType(SonusBrandMark)),
            Size.square(size),
          );
        }
      }
    }
  });

  testWidgets('is announced once as the Sonus logo', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SonusBrandMark(concept: SonusBrandConcept.waveformS),
      ),
    );

    expect(
      tester.getSemantics(find.byType(SonusBrandMark)),
      matchesSemantics(label: 'Sonus', isImage: true),
    );
    semantics.dispose();
  });

  testWidgets(
    'accent style uses Concrete & Spray; monochrome uses one colour',
    (tester) async {
      final palette = SonusThemeCatalog.of(SonusThemeId.concreteSpray).palette;

      SonusBrandMarkPainter painter() {
        return tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(SonusBrandMark),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as SonusBrandMarkPainter;
      }

      await tester.pumpWidget(
        _wrap(const SonusBrandMark(concept: SonusBrandConcept.signal)),
      );
      final accent = painter();
      expect(accent.primary, palette.primary);
      expect(accent.secondary, palette.secondary);

      await tester.pumpWidget(
        _wrap(
          const SonusBrandMark(
            concept: SonusBrandConcept.signal,
            style: SonusBrandMarkStyle.monochrome,
            color: Colors.white,
          ),
        ),
      );
      final mono = painter();
      expect(mono.primary, Colors.white);
      expect(mono.secondary, Colors.white);
    },
  );

  testWidgets('theme style follows the active theme accents', (tester) async {
    for (final themeId in SonusThemeId.values) {
      final theme = SonusThemeFactory.build(
        SonusAppearanceSpec(themeId: themeId),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: const Center(
            child: SonusBrandMark(
              concept: SonusBrandConcept.selected,
              style: SonusBrandMarkStyle.theme,
            ),
          ),
        ),
      );

      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(SonusBrandMark),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as SonusBrandMarkPainter;
      expect(painter.primary, theme.colorScheme.primary, reason: themeId.label);
      expect(
        painter.secondary,
        theme.colorScheme.secondary,
        reason: themeId.label,
      );
    }
  });

  test('Waveform S is the selected brand mark', () {
    expect(SonusBrandConcept.selected, SonusBrandConcept.waveformS);
  });

  test('concepts have distinct review labels', () {
    expect(
      SonusBrandConcept.values.map((c) => c.label).toSet(),
      hasLength(SonusBrandConcept.values.length),
    );
  });
}

Widget _wrap(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: child),
);
