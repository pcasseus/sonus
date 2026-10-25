import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_artwork_image.dart';
import 'package:sonus_next/core/design/widgets/sonus_decorations.dart';
import 'package:sonus_next/core/design/widgets/sonus_form_section.dart';
import 'package:sonus_next/core/design/widgets/sonus_page_header.dart';
import 'package:sonus_next/core/design/widgets/sonus_state_view.dart';
import 'package:sonus_next/core/design/widgets/sonus_track_tile.dart';

// SN-48H/K2 shared components.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double textScale = 1,
    Size size = const Size(411, 800),
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(spec),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  group('progress style token', () {
    test('every theme exposes its own progress treatment', () {
      for (final id in SonusThemeId.values) {
        final decoration = SonusThemeFactory.build(
          SonusAppearanceSpec(themeId: id),
        ).extension<SonusDecorationTokens>()!;
        expect(
          decoration.progressStyle,
          SonusThemeCatalog.of(id).progressStyle,
          reason: id.label,
        );
      }
    });
  });

  group('SonusArtworkImage', () {
    testWidgets('decodes near its display size', (tester) async {
      await pump(
        tester,
        const SonusArtworkImage(path: '/art/cover.png', size: 44),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      expect((image.image as ResizeImage).width, lessThanOrEqualTo(44 * 3));
    });

    testWidgets('shows the placeholder without a path', (tester) async {
      await pump(tester, const SonusArtworkImage(path: '  ', size: 44));

      expect(find.byType(Image), findsNothing);
      expect(find.byType(SonusArtworkPlaceholder), findsOneWidget);
    });
  });

  group('SonusStateView', () {
    testWidgets('announces its message and fits 320dp at 2x', (tester) async {
      await pump(
        tester,
        SonusStateView(
          icon: Icons.library_music_outlined,
          title: 'No songs yet',
          message: 'Import music to see your songs here, sorted your way.',
          action: FilledButton(onPressed: () {}, child: const Text('Import')),
        ),
        size: const Size(320, 480),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('No songs yet'), findsOneWidget);
      final semantics = tester.getSemantics(find.byType(SonusStateView));
      expect(semantics, isNotNull);
    });

    testWidgets('loading shows a spinner and its label', (tester) async {
      await pump(tester, const SonusStateView.loading(label: 'Loading'));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading'), findsOneWidget);
    });
  });

  group('SonusPageHeader', () {
    testWidgets('keeps the title on one line at 320dp and 2x', (tester) async {
      await pump(
        tester,
        const SonusPageHeader(
          title: 'Playlists',
          subtitle: '12 playlists',
          trailing: Icon(Icons.add),
        ),
        size: const Size(320, 600),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSemantics(find.text('Playlists')).flagsCollection.isHeader,
        isTrue,
      );
    });
  });

  group('SonusTrackTile', () {
    testWidgets('shows number, artwork, title, subtitle and duration', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        SonusTrackTile(
          title: 'Fixture Song',
          subtitle: 'Fixture Artist',
          leadingNumber: '3',
          duration: '3:41',
          onTap: () => taps++,
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('3:41'), findsOneWidget);
      expect(find.text('Fixture Artist'), findsOneWidget);
      await tester.tap(find.text('Fixture Song'));
      expect(taps, 1);
    });

    testWidgets('large text drops the number and moves the duration', (
      tester,
    ) async {
      await pump(
        tester,
        const SonusTrackTile(
          title: 'An Exceptionally Long Fixture Title That Wraps',
          subtitle: 'Fixture Artist',
          leadingNumber: '12',
          duration: '3:41',
          trailing: SizedBox(width: 48, height: 48),
        ),
        size: const Size(320, 800),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('12'), findsNothing);
      expect(find.text('Fixture Artist • 3:41'), findsOneWidget);
    });

    testWidgets('a disabled row ignores taps', (tester) async {
      var taps = 0;
      await pump(
        tester,
        SonusTrackTile(
          title: 'Missing Song',
          enabled: false,
          onTap: () => taps++,
        ),
      );

      await tester.tap(find.text('Missing Song'));
      expect(taps, 0);
    });

    testWidgets('the current song is labelled for screen readers', (
      tester,
    ) async {
      await pump(
        tester,
        const SonusTrackTile(title: 'Playing Song', isCurrent: true),
      );

      expect(find.bySemanticsLabel(RegExp('Now playing')), findsOneWidget);
    });

    test('formats durations', () {
      expect(sonusFormatDuration(0), '0:00');
      expect(sonusFormatDuration(221), '3:41');
      expect(sonusFormatDuration(3725), '1:02:05');
      expect(sonusFormatDuration(-4), '0:00');
    });
  });

  group('SonusFormSection', () {
    testWidgets('titles its group as a header', (tester) async {
      await pump(
        tester,
        const SonusFormSection(
          title: 'Details',
          subtitle: 'Title and credits',
          icon: Icons.edit_outlined,
          children: [Text('Field')],
        ),
      );

      expect(
        tester.getSemantics(find.text('Details')).flagsCollection.isHeader,
        isTrue,
      );
      expect(find.text('Field'), findsOneWidget);
    });
  });
}
