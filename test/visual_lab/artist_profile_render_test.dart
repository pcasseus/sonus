// The real Artist Profile with the approved Profile Lab rendering
// (artwork environment, frosted glass, local grounds): measured on
// generated artwork, and rendered to boards for review.
//
// Boards are written only with --dart-define=SONUS_LAB_OUT=<folder>
// (outside the repository); real artwork only with SONUS_LAB_REAL_ART, to
// <out>/real/. The repository is public: no real artwork is committed.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';

import '../features/library/presentation/pages/artist_profile_page_test.dart'
    as base;
import '../support/device_layout.dart';
import 'support/lab_board.dart';
import 'support/lab_harness.dart';
import 'support/lab_metrics.dart';

const String _out = String.fromEnvironment('SONUS_LAB_OUT');
const String _realArt = String.fromEnvironment('SONUS_LAB_REAL_ART');

Finder _key(String key) => find.byKey(ValueKey<String>(key));

LibraryTrack _track(String id, String title, String albumId, String? art) =>
    LibraryTrack(
      songId: id,
      title: title,
      artistId: 'artist-1',
      artistName: 'Ayo Nova',
      albumId: albumId,
      albumTitle: albumId == 'album-1' ? 'Harbour Lights' : 'Paper Moons',
      albumEditionId: 'edition-$albumId',
      albumEditionTitle: 'Standard',
      albumEditionType: AlbumEditionType.values.first,
      trackNumber: 1,
      durationSeconds: 200,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: DateTime(2026, 1, 1),
      filePath: '/music/$id.mp3',
      isAvailable: true,
      artworkPath: art,
    );

/// Illustrative fixture: an artist with a banner, a portrait, two
/// releases and ranked songs.
(base.FakeLibraryQueryRepository, base.FakeQualifiedPlayRepository) _catalogue({
  required String? banner,
  required String? portrait,
  required List<String?> covers,
}) {
  final titles = [
    'Glass Hours',
    'Slow Static',
    'Velvet Signal',
    'Northern Window',
    'Little Earthquake Season',
    'Harbour Song',
    'Paper Moon',
  ];
  final tracks = [
    for (var i = 0; i < titles.length; i++)
      _track(
        's$i',
        titles[i],
        i < 4 ? 'album-1' : 'album-2',
        covers[(i < 4 ? 0 : 1) % covers.length],
      ),
  ];
  final repository = base.FakeLibraryQueryRepository(
    artist: base.createArtist(
      name: 'Ayo Nova',
      headerArtworkPath: banner,
      topArtistsArtworkPath: portrait,
      albumCount: 2,
      songCount: tracks.length,
    ),
    albums: [
      base.createAlbum(
        albumId: 'album-1',
        title: 'Harbour Lights',
        artistName: 'Ayo Nova',
        artworkPath: covers[0],
      ),
      base.createAlbum(
        albumId: 'album-2',
        title: 'Paper Moons',
        artistName: 'Ayo Nova',
        artworkPath: covers[1 % covers.length],
      ),
    ],
    tracks: tracks,
  );
  final plays = base.FakeQualifiedPlayRepository([
    for (var i = 0; i < tracks.length; i++)
      for (var n = 0; n < 9 - i; n++)
        base.qualifiedPlay(
          tracks[i].songId,
          albumId: tracks[i].albumId,
          at: DateTime.utc(2026, 1, 1 + n),
        ),
  ]);
  return (repository, plays);
}

Future<void> _pump(
  WidgetTester tester, {
  required String? banner,
  required String? portrait,
  required List<String?> covers,
  SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  LabDevice device = LabDevice.s26,
}) async {
  setDevice(tester, size: device.size, ratio: device.ratio);
  await tester.runAsync(() async {
    for (final path in [banner, portrait]) {
      await SonusArtworkPalette.shared.colorsFor(
        path,
        brightness: Brightness.dark,
      );
    }
  });
  final (repository, plays) = _catalogue(
    banner: banner,
    portrait: portrait,
    covers: covers,
  );
  // A fresh page each time, as opening the profile gives (no state kept
  // from an earlier render).
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    base.buildSubject(
      repository: repository,
      qualifiedPlays: plays,
      theme: labTheme(spec),
      appBuilder: (context, child) => RepaintBoundary(
        key: labCaptureKey,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(device.textScale)),
          child: child!,
        ),
      ),
      home: const ArtistProfilePage(
        artistId: 'artist-1',
        initialArtistName: 'Ayo Nova',
      ),
    ),
  );
  await settleLab(tester);
}

Future<void> _scroll(WidgetTester tester, double by) async {
  if (by == 0) return;
  final scrollable = find.byType(Scrollable).first;
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(
    (state.position.pixels + by).clamp(0.0, state.position.maxScrollExtent),
  );
  await tester.pump();
  await settleLab(tester);
}

/// For probes: the page with generated [v] artwork, scrolled [by].
Future<void> pumpForProbe(WidgetTester tester, LabVariant v, double by) async {
  final art = LabArtworkFiles.ensure();
  await _pump(
    tester,
    banner: art.banner(v),
    portrait: art.portrait(v),
    covers: [art.cover('cool'), art.cover('hue_0')],
  );
  await _scroll(tester, by);
}

void main() {
  setUpAll(loadBaselineFonts);

  (String?, String?, List<String?>) generated(LabVariant v) {
    final art = LabArtworkFiles.ensure();
    return (
      art.banner(v),
      art.portrait(v),
      [art.cover('cool'), art.cover('hue_0')],
    );
  }

  group('Artist Profile: text readable on its ground', () {
    for (final variant in LabVariant.values) {
      for (final (state, by) in const [('top', 0.0), ('scrolled', 560.0)]) {
        testWidgets('${variant.label}, $state', (tester) async {
          final (banner, portrait, covers) = generated(variant);
          await _pump(
            tester,
            banner: banner,
            portrait: portrait,
            covers: covers,
          );
          await _scroll(tester, by);
          expect(_key('sonus-artwork-environment-image'), findsOneWidget);
          // Text under the app bar (status bar + toolbar) is covered by it
          // once scrolled; only text below the bar is measured.
          final barBottom =
              tester.view.padding.top / tester.view.devicePixelRatio +
              kToolbarHeight;
          final samples = [
            for (final t in collectTextsIn(tester, 'artist-profile-page'))
              if (t.rect.top >= barBottom + 4) t,
          ];
          final (pixels, _) = await captureLab(tester);
          final measured = measureTextsBeside(samples, pixels);
          expect(measured.length, greaterThan(6));
          final failing = [
            for (final t in measured)
              if (!t.passes) '${t.text}: ${t.worst.toStringAsFixed(2)}',
          ];
          expect(failing, isEmpty);
        });
      }
    }
  });

  // Workstream C: the Lab composition in the real page. Every control
  // does something real; nothing is a placeholder.
  group('Artist Profile composition', () {
    Future<void> open(WidgetTester tester, {LabDevice? device}) async {
      final (banner, portrait, covers) = generated(LabVariant.cool);
      await _pump(
        tester,
        banner: banner,
        portrait: portrait,
        covers: covers,
        device: device ?? LabDevice.s26,
      );
    }

    testWidgets('section tabs scroll to their real sections and follow', (
      tester,
    ) async {
      await open(tester);
      final tabs = _key('artist-profile-section-tabs');
      expect(tabs, findsOneWidget);
      expect(
        find.descendant(of: tabs, matching: find.text('Overview')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tabs, matching: find.text('Releases')),
        findsOneWidget,
      );
      // No collaborations in this catalogue: no tab for them.
      expect(
        find.descendant(of: tabs, matching: find.text('Collaborations')),
        findsNothing,
      );
      expect(
        tester.getSemantics(_key('artist-profile-section-tab-0')),
        isSemantics(isSelected: true, isButton: true),
      );
      final tab = tester.getSize(_key('artist-profile-section-tab-1'));
      expect(tab.height, greaterThanOrEqualTo(47.99));

      await tester.tap(_key('artist-profile-section-tab-1'));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final shelf = tester.getRect(_key('artist-profile-albums'));
      final barBottom =
          tester.view.padding.top / tester.view.devicePixelRatio +
          kToolbarHeight;
      // Just below the toolbar, or as far as a short page goes.
      expect(
        shelf.top <= barBottom + 40 ||
            position.pixels >= position.maxScrollExtent - 0.5,
        isTrue,
        reason:
            'shelf $shelf at ${position.pixels}/${position.maxScrollExtent}',
      );
      expect(shelf.top, greaterThanOrEqualTo(barBottom - 0.5));

      // Back near the top the tabs follow the position: Overview again.
      position.jumpTo(120);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 10));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(_key('artist-profile-section-tab-0')),
        isSemantics(isSelected: true, isButton: true),
      );
      await tester.tap(_key('artist-profile-section-tab-0'));
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
    });

    testWidgets('statistics plate, glass toolbar and release carousel', (
      tester,
    ) async {
      await open(tester);
      expect(_key('artist-profile-stats-plate'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('artist-profile-stats-plate'),
          matching: _key('artist-profile-listening'),
        ),
        findsOneWidget,
      );
      expect(_key('artist-profile-toolbar-glass'), findsNothing);
      await _scroll(tester, 2000);
      expect(_key('artist-profile-toolbar-glass'), findsOneWidget);
      final releases = find.descendant(
        of: _key('artist-profile-albums-grid'),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.widget<Scrollable>(releases.first).axisDirection,
        AxisDirection.right,
      );
      expect(_key('artist-album-album-1'), findsOneWidget);
      expect(_key('artist-album-album-2'), findsOneWidget);
    });

    for (final device in [
      LabDevice.small,
      LabDevice.s26.withText(1.3),
      LabDevice.s26.withText(2.0),
      LabDevice.small.withText(2.0),
    ]) {
      testWidgets('lays out at ${device.name}', (tester) async {
        await open(tester, device: device);
        expect(tester.takeException(), isNull);
        final tab = tester.getSize(_key('artist-profile-section-tab-1'));
        expect(tab.height, greaterThanOrEqualTo(47.99));
        await tester.tap(_key('artist-profile-section-tab-1'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(_key('artist-profile-albums'), findsOneWidget);
      });
    }
  });

  group('Artist Profile: the glass reads as its own material', () {
    for (final variant in LabVariant.values) {
      testWidgets(variant.label, (tester) async {
        final (banner, portrait, covers) = generated(variant);
        await _pump(tester, banner: banner, portrait: portrait, covers: covers);
        await _scroll(tester, 520);
        final glass = tester.getRect(_key('artist-profile-top-tracks-glass'));
        final (pixels, _) = await captureLab(tester);
        // Bare plate inside the right edge, against the page just outside.
        final band = Rect.fromLTRB(
          glass.right - 10,
          glass.top + 20,
          glass.right - 4,
          (glass.bottom - 20).clamp(glass.top + 21, 800),
        );
        final outside = Rect.fromLTRB(
          glass.right + 3,
          band.top,
          (glass.right + 9).clamp(0, 383),
          band.bottom,
        );
        double median(Rect r) =>
            percentile(pixelsIn(pixels, r, step: 1).map(lStar).toList(), 0.5);
        expect((median(band) - median(outside)).abs(), greaterThan(2.5));
      });
    }
  });

  // High contrast keeps a restrained artwork backdrop (no light, glass or
  // glow) behind its solid panels; every text and icon still reads.
  group('Artist Profile: High contrast keeps a restrained backdrop', () {
    for (final variant in LabVariant.values) {
      for (final (state, by) in const [('top', 0.0), ('scrolled', 560.0)]) {
        testWidgets('${variant.label}, $state', (tester) async {
          final (banner, portrait, covers) = generated(variant);
          await _pump(
            tester,
            banner: banner,
            portrait: portrait,
            covers: covers,
            spec: const SonusAppearanceSpec(highContrast: true),
          );
          await _scroll(tester, by);
          expect(_key('sonus-artwork-environment-image'), findsOneWidget);
          expect(_key('sonus-artwork-environment-light'), findsNothing);
          final barBottom =
              tester.view.padding.top / tester.view.devicePixelRatio +
              kToolbarHeight;
          final measured = measureTextsBeside([
            for (final t in collectTextsIn(tester, 'artist-profile-page'))
              if (t.rect.top >= barBottom + 4) t,
          ], (await captureLab(tester)).$1);
          expect(measured.length, greaterThan(6));
          expect([
            for (final t in measured)
              if (!t.passes) '${t.text}: ${t.worst.toStringAsFixed(2)}',
          ], isEmpty);
        });
      }
    }
  });

  group('Artist Profile: Low effects and Decoration Off draw no artwork', () {
    for (final spec in const [
      SonusAppearanceSpec(lowEffects: true),
      SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      SonusAppearanceSpec(highContrast: true, lowEffects: true),
    ]) {
      testWidgets('$spec', (tester) async {
        final (banner, portrait, covers) = generated(LabVariant.cool);
        await _pump(
          tester,
          banner: banner,
          portrait: portrait,
          covers: covers,
          spec: spec,
        );
        expect(_key('sonus-artwork-environment-image'), findsNothing);
        expect(_key('artist-profile-identity-scrim'), findsNothing);
      });
    }
  });

  testWidgets('boards: the real Artist Profile', skip: _out.isEmpty, (
    tester,
  ) async {
    Future<ui.Image> shot(
      (String?, String?, List<String?>) art,
      double by, {
      LabDevice device = LabDevice.s26,
      SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    }) async {
      await _pump(
        tester,
        banner: art.$1,
        portrait: art.$2,
        covers: art.$3,
        device: device,
        spec: spec,
      );
      // Large real photos take longer to decode than generated ones.
      await settleLab(tester);
      await settleLab(tester);
      await _scroll(tester, by);
      return (await captureLab(tester, pixelRatio: 2)).$2;
    }

    final rows = <List<BoardCell>>[];
    for (final v in LabVariant.values) {
      rows.add([
        for (final (label, by) in const [
          ('Top', 0.0),
          ('Scrolled', 560.0),
          ('Lower', 1100.0),
        ])
          BoardCell('${v.label} · $label', await shot(generated(v), by)),
      ]);
    }
    await writeBoard(
      tester,
      '$_out/board_artist_profile.png',
      'Artist Profile (production) with the Lab rendering · generated artwork',
      rows,
    );

    if (_realArt.isEmpty) return;
    String? f(String name) {
      final file = File('$_realArt/$name');
      return file.existsSync() ? file.path : null;
    }

    final covers = [
      f('locket_locket.png'),
      f('locket_locket_deluxe.png'),
      f('midnight_sun_midnight_sun.png'),
    ];
    final real = [
      (
        'Cool real',
        (f('madison_banner.png'), f('madison_portrait.png'), covers),
      ),
      (
        'Warm real',
        (
          f('zara_banner.png'),
          f('zara_portrait.png'),
          covers.reversed.toList(),
        ),
      ),
      (
        'Neutral real',
        (f('locket_locket_deluxe.png'), f('locket_locket_deluxe.png'), covers),
      ),
    ];
    final realRows = <List<BoardCell>>[];
    for (final (name, art) in real) {
      realRows.add([
        for (final (label, by) in const [
          ('Top', 0.0),
          ('Scrolled', 560.0),
          ('Lower', 1100.0),
        ])
          BoardCell('$name · $label', await shot(art, by)),
      ]);
    }
    final (_, cool) = real.first;
    realRows.add([
      BoardCell(
        'Cool real · 360x780',
        await shot(cool, 0, device: LabDevice.small),
      ),
      BoardCell(
        'Cool real · 1.3x text',
        await shot(cool, 0, device: LabDevice.s26.withText(1.3)),
      ),
      BoardCell(
        'Cool real · 2x text',
        await shot(cool, 0, device: LabDevice.s26.withText(2.0)),
      ),
    ]);
    realRows.add([
      BoardCell(
        'Cool real · High contrast',
        await shot(
          cool,
          0,
          spec: const SonusAppearanceSpec(highContrast: true),
        ),
      ),
      BoardCell(
        'Cool real · Low effects',
        await shot(cool, 0, spec: const SonusAppearanceSpec(lowEffects: true)),
      ),
    ]);
    await writeBoard(
      tester,
      '$_out/real/board_artist_profile_real.png',
      'Artist Profile (production) · real artwork (local only)',
      realRows,
    );
  });
}
