// Album Profile Lab: the Album Profile in the Profile Lab architecture, on
// generated artwork. Boards are written only with
// --dart-define=SONUS_LAB_OUT=<folder> (outside the repository); real
// covers only with SONUS_LAB_REAL_ART, to <out>/real/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/prototypes/profile_lab/album_lab_page.dart';
import 'package:sonus_next/prototypes/profile_lab/profile_lab_atmosphere.dart';

import '../support/device_layout.dart';
import 'support/lab_board.dart';
import 'support/lab_harness.dart';
import 'support/lab_metrics.dart';

const String _out = String.fromEnvironment('SONUS_LAB_OUT');
const String _realArt = String.fromEnvironment('SONUS_LAB_REAL_ART');

Finder _key(String key) => find.byKey(ValueKey<String>(key));

/// Illustrative content only.
LabAlbum _album({required String? standard, required String? deluxe}) {
  const base = [
    ('Harbour Theme', 89),
    ('Yes Tonight', 177),
    ('Glass Hours', 244),
    ('For the Night Bus', 189),
    ('Bad Enough Weather', 223),
    ('Healthy Habit', 116),
  ];
  List<LabAlbumTrack> tracks(int extra) => [
    for (var i = 0; i < base.length; i++)
      LabAlbumTrack(
        base[i].$1,
        Duration(seconds: base[i].$2),
        isPlaying: i == 0,
      ),
    for (var i = 0; i < extra; i++)
      LabAlbumTrack('Bonus Track ${i + 1}', Duration(seconds: 150 + i * 17)),
  ];
  return LabAlbum(
    title: 'Harbour Lights',
    artistName: 'Ayo Nova',
    year: 2026,
    genre: 'Pop',
    editions: [
      LabEdition(name: 'Standard', coverPath: standard, tracks: tracks(0)),
      LabEdition(name: 'Deluxe', coverPath: deluxe, tracks: tracks(3)),
    ],
  );
}

(String?, String?) _covers(LabVariant v) {
  final art = LabArtworkFiles.ensure();
  return switch (v) {
    LabVariant.cool => (art.cover('cool'), art.cover('hue_0')),
    LabVariant.warm => (art.cover('warm'), art.cover('hue_2')),
    LabVariant.neutral => (art.cover('neutral'), art.cover('neutral')),
    LabVariant.bright => (art.banner(v), art.banner(v)),
  };
}

Future<ScrollController> _pump(
  WidgetTester tester,
  LabAlbum album, {
  LabDevice device = LabDevice.s26,
  SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  LabLayers layers = LabLayers.all,
  int edition = 0,
  SonusArtworkPalette? palette,
}) async {
  setDevice(tester, size: device.size, ratio: device.ratio);
  await tester.runAsync(() async {
    for (final e in album.editions) {
      await SonusArtworkPalette.shared.colorsFor(
        e.coverPath,
        brightness: Brightness.dark,
      );
    }
  });
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: labTheme(spec),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => RepaintBoundary(
        key: labCaptureKey,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(device.textScale)),
          child: child!,
        ),
      ),
      home: AlbumLabPage(
        album: album,
        initialEdition: edition,
        layers: layers,
        scrollController: scroll,
        artworkPalette: palette,
      ),
    ),
  );
  await settleLab(tester);
  return scroll;
}

Future<void> _scrollTo(
  WidgetTester tester,
  ScrollController scroll,
  double offset,
) async {
  scroll.jumpTo(offset.clamp(0.0, scroll.position.maxScrollExtent));
  await tester.pump();
  await settleLab(tester);
}

/// Offsets: the top, the track list under the toolbar (collapsed header).
const _states = [('Top', 0.0), ('Tracks (collapsed header)', 470.0)];

void main() {
  setUpAll(loadBaselineFonts);

  group('every phone and text size lays out without overflow', () {
    for (final device in [
      for (final phone in LabDevice.phones) ...[
        phone,
        phone.withText(1.3),
        phone.withText(2.0),
      ],
    ]) {
      testWidgets(device.name, (tester) async {
        final (s, d) = _covers(LabVariant.cool);
        for (final edition in [0, 1]) {
          final scroll = await _pump(
            tester,
            _album(standard: s, deluxe: d),
            device: device,
            edition: edition,
          );
          for (final (_, offset) in _states) {
            await _scrollTo(tester, scroll, offset);
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  });

  group('text is readable on the ground actually under it', () {
    for (final variant in LabVariant.values) {
      for (final (state, offset) in _states) {
        testWidgets('${variant.label}, $state', (tester) async {
          final (s, d) = _covers(variant);
          final album = _album(standard: s, deluxe: d);
          final scroll = await _pump(tester, album);
          await _scrollTo(tester, scroll, offset);
          final at = scroll.offset;
          final samples = collectTextsIn(tester, 'album-lab-page');
          final inkless = await _pump(
            tester,
            album,
            layers: LabLayers.all.copyWith(ink: false),
          );
          await _scrollTo(tester, inkless, at);
          final measured = measureTexts(samples, (await captureLab(tester)).$1);
          expect(measured.length, greaterThan(6));
          expect([
            for (final t in measured)
              if (!t.passes) '${t.text}: ${t.worst.toStringAsFixed(2)}',
          ], isEmpty);
        });
      }
    }
  });

  testWidgets('editions switch the cover, the tracks and the atmosphere', (
    tester,
  ) async {
    final (s, d) = _covers(LabVariant.cool);
    final palette = _RecordingPalette();
    await _pump(
      tester,
      _album(standard: s, deluxe: d),
      palette: palette,
    );
    expect(find.text('6 tracks · 17 min'), findsOneWidget);
    expect(palette.requested.last, s);

    await tester.tap(_key('album-lab-edition-1'));
    await settleLab(tester);
    expect(find.text('9 tracks · 25 min'), findsOneWidget);
    expect(_key('album-lab-tracks-Deluxe'), findsOneWidget);
    expect(palette.requested.last, d, reason: 'atmosphere follows the cover');
    final selected = tester.getSemantics(_key('album-lab-edition-1'));
    expect(selected, isSemantics(isSelected: true, isButton: true));
  });

  testWidgets('the header collapses into the toolbar title', (tester) async {
    final (s, d) = _covers(LabVariant.cool);
    final scroll = await _pump(tester, _album(standard: s, deluxe: d));
    AnimatedOpacity title() =>
        tester.widget<AnimatedOpacity>(_key('album-lab-toolbar-title'));
    expect(title().opacity, 0);
    await _scrollTo(tester, scroll, 470);
    expect(title().opacity, 1);
  });

  testWidgets('touch targets are at least 48dp', (tester) async {
    final (s, d) = _covers(LabVariant.cool);
    await _pump(tester, _album(standard: s, deluxe: d));
    for (final key in [
      'album-lab-play',
      'album-lab-shuffle',
      'album-lab-favourite',
      'album-lab-edition-0',
      'album-lab-edition-1',
    ]) {
      expect(tester.getSize(_key(key)).height, greaterThanOrEqualTo(47.99));
    }
    final buttons = find.byType(IconButton);
    for (var i = 0; i < buttons.evaluate().length; i++) {
      expect(tester.getSize(buttons.at(i)).height, greaterThanOrEqualTo(48));
    }
  });

  group('High contrast: restrained backdrop, readable text', () {
    for (final variant in LabVariant.values) {
      testWidgets(variant.label, (tester) async {
        final (s, d) = _covers(variant);
        final album = _album(standard: s, deluxe: d);
        const spec = SonusAppearanceSpec(highContrast: true);
        await _pump(tester, album, spec: spec);
        expect(_key('lab-backdrop-image'), findsOneWidget);
        expect(_key('lab-backdrop-lights'), findsNothing);
        final samples = collectTextsIn(tester, 'album-lab-page');
        await _pump(
          tester,
          album,
          spec: spec,
          layers: LabLayers.all.copyWith(ink: false),
        );
        final measured = measureTexts(samples, (await captureLab(tester)).$1);
        expect([
          for (final t in measured)
            if (!t.passes) '${t.text}: ${t.worst.toStringAsFixed(2)}',
        ], isEmpty);
      });
    }
  });

  testWidgets('Low effects draws no imagery behind content', (tester) async {
    final (s, d) = _covers(LabVariant.cool);
    await _pump(
      tester,
      _album(standard: s, deluxe: d),
      spec: const SonusAppearanceSpec(lowEffects: true),
    );
    expect(_key('lab-backdrop-image'), findsNothing);
  });

  testWidgets('boards: Album Profile Lab', skip: _out.isEmpty, (tester) async {
    Future<ui.Image> shot(
      LabAlbum album,
      double offset, {
      int edition = 0,
      LabDevice device = LabDevice.s26,
      SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    }) async {
      final scroll = await _pump(
        tester,
        album,
        edition: edition,
        device: device,
        spec: spec,
      );
      await settleLab(tester);
      await _scrollTo(tester, scroll, offset);
      return (await captureLab(tester, pixelRatio: 2)).$2;
    }

    final rows = <List<BoardCell>>[];
    for (final v in LabVariant.values) {
      final (s, d) = _covers(v);
      final album = _album(standard: s, deluxe: d);
      rows.add([
        BoardCell('${v.label} · Standard · Top', await shot(album, 0)),
        BoardCell(
          '${v.label} · Deluxe · Top',
          await shot(album, 0, edition: 1),
        ),
        BoardCell('${v.label} · Collapsed', await shot(album, 470)),
      ]);
    }
    final (s, d) = _covers(LabVariant.cool);
    final cool = _album(standard: s, deluxe: d);
    rows.add([
      BoardCell('360x780', await shot(cool, 0, device: LabDevice.small)),
      BoardCell(
        '1.3x text',
        await shot(cool, 0, device: LabDevice.s26.withText(1.3)),
      ),
      BoardCell(
        '2x text',
        await shot(cool, 0, device: LabDevice.s26.withText(2.0)),
      ),
      BoardCell(
        'High contrast',
        await shot(
          cool,
          0,
          spec: const SonusAppearanceSpec(highContrast: true),
        ),
      ),
    ]);
    await writeBoard(
      tester,
      '$_out/board_album_lab.png',
      'Album Profile Lab · generated artwork',
      rows,
    );

    if (_realArt.isEmpty) return;
    String? f(String name) {
      final file = File('$_realArt/$name');
      return file.existsSync() ? file.path : null;
    }

    final real = [
      (
        'locket',
        _album(
          standard: f('locket_locket.png'),
          deluxe: f('locket_locket_deluxe.png'),
        ),
      ),
      (
        'Midnight Sun',
        _album(
          standard: f('midnight_sun_midnight_sun.png'),
          deluxe: f('midnight_sun_midnight_sun.png'),
        ),
      ),
    ];
    final realRows = [
      for (final (name, album) in real)
        [
          BoardCell('$name · Standard', await shot(album, 0)),
          BoardCell('$name · Deluxe', await shot(album, 0, edition: 1)),
          BoardCell('$name · Collapsed', await shot(album, 470)),
        ],
    ];
    await writeBoard(
      tester,
      '$_out/real/board_album_lab_real.png',
      'Album Profile Lab · real covers (local only)',
      realRows,
    );
  });
}

class _RecordingPalette extends SonusArtworkPalette {
  final requested = <String?>[];

  @override
  Future<SonusArtworkColors?> colorsFor(
    String? artworkPath, {
    required Brightness brightness,
  }) async {
    requested.add(artworkPath);
    return null;
  }
}
