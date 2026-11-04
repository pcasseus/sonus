import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_atmosphere_colors.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/widgets/sonus_artwork_atmosphere_builder.dart';

void main() {
  const red = SonusArtworkColors(
    accent: Color(0xFFE53935),
    container: Color(0xFF5C1A1A),
  );
  const blue = SonusArtworkColors(
    accent: Color(0xFF1E88E5),
    container: Color(0xFF0D2B52),
  );

  Future<List<SonusAtmosphereColors>> pump(
    WidgetTester tester,
    Widget Function(void Function(SonusAtmosphereColors) record) build,
  ) async {
    final seen = <SonusAtmosphereColors>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(
          const SonusAppearanceSpec(reduceMotion: true),
        ),
        home: build(seen.add),
      ),
    );
    return seen;
  }

  testWidgets('a fixed path tints with its artwork colours', (tester) async {
    final palette = _FakePalette({'/a.jpg': red});
    final seen = await pump(
      tester,
      (record) => SonusArtworkAtmosphereBuilder(
        artworkPath: ' /a.jpg ',
        palette: palette,
        builder: (context, colors) {
          record(colors);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(palette.requested, ['/a.jpg'], reason: 'trimmed, asked once');
    expect(seen.first.isTinted, isFalse, reason: 'theme colours at once');
    expect(seen.last.isTinted, isTrue);
  });

  testWidgets('a listenable path is requested as soon as it changes, '
      'without anything rebuilding', (tester) async {
    final palette = _FakePalette({'/a.jpg': red, '/b.jpg': blue});
    final path = ValueNotifier<String?>('/a.jpg');
    addTearDown(path.dispose);
    final seen = await pump(
      tester,
      (record) => SonusArtworkAtmosphereBuilder.listenable(
        artworkPath: path,
        palette: palette,
        builder: (context, colors) {
          record(colors);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();
    final first = seen.last;

    // Notified outside any build: the request goes out immediately.
    path.value = '/b.jpg';
    expect(palette.requested, ['/a.jpg', '/b.jpg']);

    await tester.pumpAndSettle();
    expect(seen.last.isTinted, isTrue);
    expect(seen.last.accent, isNot(first.accent), reason: 'now /b.jpg');
  });

  testWidgets('a listenable path stops being followed once disposed', (
    tester,
  ) async {
    final palette = _FakePalette({'/a.jpg': red, '/b.jpg': blue});
    final path = ValueNotifier<String?>('/a.jpg');
    addTearDown(path.dispose);
    await pump(
      tester,
      (record) => SonusArtworkAtmosphereBuilder.listenable(
        artworkPath: path,
        palette: palette,
        builder: (context, colors) => const SizedBox(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    path.value = '/b.jpg';

    expect(palette.requested, ['/a.jpg']);
  });
}

class _FakePalette extends SonusArtworkPalette {
  _FakePalette(this.colours);

  final Map<String?, SonusArtworkColors?> colours;
  final requested = <String?>[];

  @override
  Future<SonusArtworkColors?> colorsFor(
    String? artworkPath, {
    required Brightness brightness,
  }) async {
    requested.add(artworkPath);
    return colours[artworkPath];
  }
}
