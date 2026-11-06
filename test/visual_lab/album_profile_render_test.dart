// The real Album Profile with the approved Profile Lab rendering (artwork
// environment, frosted track glass, cover glow, quiet edition chips,
// translucent collapsed bar): measured on generated covers, and rendered
// to boards for review.
//
// Boards are written only with --dart-define=SONUS_LAB_OUT=<folder>
// (outside the repository); real covers only with SONUS_LAB_REAL_ART, to
// <out>/real/. The repository is public: no real artwork is committed.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_artwork_environment.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

import '../features/library/presentation/pages/album_profile_page_test.dart'
    as base;
import '../support/device_layout.dart';
import 'support/lab_board.dart';
import 'support/lab_harness.dart';
import 'support/lab_metrics.dart';

const String _out = String.fromEnvironment('SONUS_LAB_OUT');
const String _realArt = String.fromEnvironment('SONUS_LAB_REAL_ART');

Finder _key(String key) => find.byKey(ValueKey<String>(key));

/// A compact toolbar: the status bar plus one toolbar row.
double _barLimit(WidgetTester tester) =>
    tester.view.padding.top / tester.view.devicePixelRatio + kToolbarHeight + 1;

/// Illustrative fixture: Standard (two discs, an unavailable and a blocked
/// song, a featured artist) and Deluxe (more songs), each with its cover.
base.FakeEditionAwareLibraryQueryRepository _catalogue(
  String? standard,
  String? deluxe,
) {
  const titles = [
    'Harbour Theme',
    'Yes Tonight',
    'Glass Hours',
    'For the Night Bus',
    'Bad Enough Weather',
    'Healthy Habit',
  ];
  return base.FakeEditionAwareLibraryQueryRepository(
    album: base.createAlbum(
      title: 'Harbour Lights',
      artistName: 'Ayo Nova',
      primaryEditionId: 'edition-standard',
      primaryEditionTitle: 'Standard',
      releaseDate: DateTime(2026, 1, 16),
      genre: 'Pop',
      trackCount: 6,
    ),
    editions: [
      base.createLibraryEdition(
        editionId: 'edition-standard',
        title: 'Standard',
        type: AlbumEditionType.standard,
        isPrimary: true,
        releaseDate: DateTime(2026, 1, 16),
        genre: 'Pop',
        artworkPath: standard,
      ),
      base.createLibraryEdition(
        editionId: 'edition-deluxe',
        title: 'Harbour Lights Deluxe',
        type: AlbumEditionType.deluxe,
        releaseDate: DateTime(2026, 6, 20),
        genre: 'Pop',
        artworkPath: deluxe,
      ),
    ],
    editionTracks: {
      'edition-standard': [
        for (var i = 0; i < titles.length; i++)
          base.createTrack(
            songId: 's$i',
            title: titles[i],
            artistName: 'Ayo Nova',
            albumEditionId: 'edition-standard',
            trackNumber: i % 3 + 1,
            discNumber: i < 3 ? 1 : 2,
            durationSeconds: 150 + i * 23,
            featuredArtists: i == 1 ? const ['Kemi Ade'] : const [],
            isAvailable: i != 4,
            isSongBlocked: i == 5,
          ),
      ],
      'edition-deluxe': [
        for (var i = 0; i < 8; i++)
          base.createTrack(
            songId: 'd$i',
            title: i < titles.length ? titles[i] : 'Bonus Track ${i - 5}',
            artistName: 'Ayo Nova',
            albumEditionId: 'edition-deluxe',
            albumEditionTitle: 'Harbour Lights Deluxe',
            albumEditionType: AlbumEditionType.deluxe,
            trackNumber: i + 1,
            durationSeconds: 160 + i * 19,
          ),
      ],
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required String? standard,
  required String? deluxe,
  SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  LabDevice device = LabDevice.s26,
}) async {
  setDevice(tester, size: device.size, ratio: device.ratio);
  await tester.runAsync(() async {
    for (final path in [standard, deluxe]) {
      await SonusArtworkPalette.shared.colorsFor(
        path,
        brightness: Brightness.dark,
      );
    }
  });
  // A fresh page each time, as opening the album gives.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    base.buildSubject(
      repository: _catalogue(standard, deluxe),
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
    ),
  );
  await settleLab(tester);
}

ScrollableState _scrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(
              const PageStorageKey<String>('album-profile-scroll'),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    );

Future<void> _scroll(WidgetTester tester, double to) async {
  final position = _scrollable(tester).position;
  position.jumpTo(to.clamp(0.0, position.maxScrollExtent));
  await tester.pump();
  await settleLab(tester);
}

/// Selects the Deluxe edition in whichever form the selector takes (a
/// segmented control when the labels fit, chips otherwise).
Future<void> _selectDeluxe(WidgetTester tester) async {
  final segmented = find.descendant(
    of: _key('album-profile-edition-segmented-button'),
    matching: find.text('Deluxe'),
  );
  final chip = _key('album-profile-edition-choice-edition-deluxe');
  final target = segmented.evaluate().isNotEmpty ? segmented : chip;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await settleLab(tester);
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

/// Text under the app bar (status bar + toolbar) is covered by it once
/// scrolled; only text below the bar is measured.
List<TextSample> _visibleTexts(WidgetTester tester) {
  final barBottom =
      tester.view.padding.top / tester.view.devicePixelRatio + kToolbarHeight;
  return [
    for (final t in collectTextsIn(tester, 'album-profile-page'))
      if (t.rect.top >= barBottom + 4) t,
  ];
}

void main() {
  setUpAll(loadBaselineFonts);

  group('Album Profile: text readable on its ground', () {
    for (final variant in [
      LabVariant.cool,
      LabVariant.warm,
      LabVariant.neutral,
      LabVariant.bright,
    ]) {
      for (final (state, to) in const [('top', 0.0), ('collapsed', 900.0)]) {
        testWidgets('${variant.label}, $state', (tester) async {
          final (s, d) = _covers(variant);
          await _pump(tester, standard: s, deluxe: d);
          await _scroll(tester, to);
          expect(_key('sonus-artwork-environment-image'), findsOneWidget);
          final measured = measureTextsBeside(
            _visibleTexts(tester),
            (await captureLab(tester)).$1,
          );
          expect(measured.length, greaterThan(5));
          expect([
            for (final t in measured)
              if (!t.passes) '${t.text}: ${t.worst.toStringAsFixed(2)}',
          ], isEmpty);
        });
      }
    }
  });

  testWidgets('Standard and Deluxe: tracks, cover and environment follow', (
    tester,
  ) async {
    final (s, d) = _covers(LabVariant.cool);
    await _pump(tester, standard: s, deluxe: d);
    String? environmentPath() => tester
        .widget<SonusArtworkEnvironment>(find.byType(SonusArtworkEnvironment))
        .artworkPath;
    expect(environmentPath(), s);
    expect(_key('album-track-s0'), findsOneWidget);

    await _selectDeluxe(tester);
    expect(environmentPath(), d, reason: 'the page follows the new cover');
    expect(_key('album-track-d0'), findsOneWidget);
    expect(_key('album-track-s0'), findsNothing);
  });

  testWidgets('disc headings, metadata numbers and row states are kept', (
    tester,
  ) async {
    final (s, d) = _covers(LabVariant.cool);
    await _pump(tester, standard: s, deluxe: d, device: LabDevice.large);
    await _scroll(tester, 300);
    expect(find.text('Disc 1'), findsOneWidget);
    await _scroll(tester, 700);
    expect(find.text('Disc 2'), findsOneWidget);
    // The second disc numbers from 1 again, from the files' metadata.
    expect(
      find.descendant(of: _key('album-track-s3'), matching: find.text('1')),
      findsOneWidget,
    );
    // Unavailable songs stay off the album page, as before.
    expect(_key('album-track-s4'), findsNothing);
  });

  // The album hero scrolls away naturally: never a cover cropped behind
  // pinned metadata, never a second title or cover layer.
  group('the hero scrolls away, the toolbar stays compact', () {
    for (final (name, device, spec) in [
      ('S26', LabDevice.s26, const SonusAppearanceSpec()),
      ('360x780', LabDevice.small, const SonusAppearanceSpec()),
      ('1.3x text', LabDevice.s26.withText(1.3), const SonusAppearanceSpec()),
      ('2x text', LabDevice.s26.withText(2.0), const SonusAppearanceSpec()),
      (
        'High contrast',
        LabDevice.s26,
        const SonusAppearanceSpec(highContrast: true),
      ),
      (
        'Low effects',
        LabDevice.s26,
        const SonusAppearanceSpec(lowEffects: true),
      ),
      (
        'Reduce motion',
        LabDevice.s26,
        const SonusAppearanceSpec(reduceMotion: true),
      ),
    ]) {
      testWidgets(name, (tester) async {
        final (s, d) = _covers(LabVariant.cool);
        await _pump(tester, standard: s, deluxe: d, device: device, spec: spec);
        final cover = _key('album-profile-artwork-album-1');
        // Top: the full cover inside the hero, below the toolbar.
        final bar = tester.getRect(
          find.descendant(
            of: _key('album-profile-app-bar'),
            matching: find.byType(AppBar),
          ),
        );
        expect(
          find.descendant(of: _key('album-profile-hero'), matching: cover),
          findsOneWidget,
        );
        expect(tester.getRect(cover).top, greaterThanOrEqualTo(bar.bottom));
        final start = tester.getRect(cover);
        expect(bar.height, lessThanOrEqualTo(_barLimit(tester)));
        expect(tester.takeException(), isNull);
        for (final to in [80.0, 200.0, 360.0, 900.0]) {
          await _scroll(tester, to);
          expect(tester.takeException(), isNull);
          // The bar never grows.
          final now = tester.getRect(
            find.descendant(
              of: _key('album-profile-app-bar'),
              matching: find.byType(AppBar),
            ),
          );
          expect(now.height, lessThanOrEqualTo(_barLimit(tester)));
          expect(_key('album-profile-collapsing-hero'), findsNothing);
          // Natural scroll: the cover keeps its full size and moves exactly
          // with the page (never pinned, shrunk or cropped in place).
          if (cover.evaluate().isNotEmpty) {
            final rect = tester.getRect(cover);
            expect(rect.size.width, closeTo(start.width, 0.5), reason: '$to');
            expect(rect.size.height, closeTo(start.height, 0.5));
            final moved = _scrollable(tester).position.pixels;
            expect(rect.top, closeTo(start.top - moved, 0.5), reason: '$to');
          }
        }
        // Once the hero has gone the toolbar is filled (glass or solid).
        expect(
          tester.widget<ColoredBox>(_key('album-profile-toolbar-fill')).color.a,
          greaterThan(0.6),
        );
        // Fully scrolled: the title names the release in the toolbar.
        expect(
          tester
              .widget<AnimatedOpacity>(_key('album-profile-toolbar-title'))
              .opacity,
          1,
        );
      });
    }
  });

  testWidgets('switching to Deluxe while scrolled keeps the page coherent', (
    tester,
  ) async {
    final (s, d) = _covers(LabVariant.cool);
    await _pump(tester, standard: s, deluxe: d);
    await _selectDeluxe(tester);
    await _scroll(tester, 600);
    expect(
      _key('album-track-d0').evaluate().isNotEmpty ||
          _key('album-track-d5').evaluate().isNotEmpty,
      isTrue,
    );
    expect(_key('album-profile-collapsing-hero'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long title stays on one line in the toolbar', (tester) async {
    final (s, d) = _covers(LabVariant.cool);
    await _pump(tester, standard: s, deluxe: d, device: LabDevice.small);
    await _selectDeluxe(tester);
    await _scroll(tester, 900);
    final title = tester.widget<Text>(
      find.descendant(
        of: _key('album-profile-toolbar-title'),
        matching: find.byType(Text),
      ),
    );
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the end of the list scrolls clear of the mini-player room', (
    tester,
  ) async {
    final (s, d) = _covers(LabVariant.cool);
    await _pump(tester, standard: s, deluxe: d);
    final position = _scrollable(tester).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    await settleLab(tester);
    final last = _key('album-track-s5');
    expect(last, findsOneWidget);
    final bottomInset =
        tester.view.padding.bottom / tester.view.devicePixelRatio;
    expect(
      tester.getRect(last).bottom,
      lessThanOrEqualTo(LabDevice.s26.size.height - bottomInset),
    );
  });

  testWidgets('the header collapses into translucent glass', (tester) async {
    final (s, d) = _covers(LabVariant.cool);
    await _pump(tester, standard: s, deluxe: d);
    Color fill() =>
        tester.widget<ColoredBox>(_key('album-profile-toolbar-fill')).color;
    expect(fill().a, lessThan(0.05));
    await _scroll(tester, 900);
    expect(fill().a, closeTo(0.72, 0.01));
    expect(
      find.ancestor(
        of: _key('album-profile-toolbar-fill'),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
  });

  testWidgets('track menus still open with their actions', (tester) async {
    final (s, d) = _covers(LabVariant.cool);
    await _pump(tester, standard: s, deluxe: d);
    await _scroll(tester, 300);
    await tester.tap(_key('album-track-menu-s0'));
    await tester.pumpAndSettle();
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
  });

  group('High contrast keeps a restrained backdrop', () {
    for (final variant in LabVariant.values) {
      for (final (state, to) in const [('top', 0.0), ('collapsed', 900.0)]) {
        testWidgets('${variant.label}, $state', (tester) async {
          final (s, d) = _covers(variant);
          await _pump(
            tester,
            standard: s,
            deluxe: d,
            spec: const SonusAppearanceSpec(highContrast: true),
          );
          await _scroll(tester, to);
          expect(_key('sonus-artwork-environment-image'), findsOneWidget);
          expect(_key('sonus-artwork-environment-light'), findsNothing);
          final measured = measureTextsBeside(
            _visibleTexts(tester),
            (await captureLab(tester)).$1,
          );
          expect(measured.length, greaterThan(5));
          expect([
            for (final t in measured)
              if (!t.passes) '${t.text}: ${t.worst.toStringAsFixed(2)}',
          ], isEmpty);
        });
      }
    }
  });

  group('Low effects and Decoration Off keep the solid page', () {
    for (final spec in const [
      SonusAppearanceSpec(lowEffects: true),
      SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      SonusAppearanceSpec(highContrast: true, lowEffects: true),
    ]) {
      testWidgets('$spec', (tester) async {
        final (s, d) = _covers(LabVariant.cool);
        await _pump(tester, standard: s, deluxe: d, spec: spec);
        expect(_key('sonus-artwork-environment-image'), findsNothing);
      });
    }
  });

  testWidgets('boards: the real Album Profile', skip: _out.isEmpty, (
    tester,
  ) async {
    Future<ui.Image> shot(
      (String?, String?) covers,
      double to, {
      bool deluxe = false,
      LabDevice device = LabDevice.s26,
      SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    }) async {
      await _pump(
        tester,
        standard: covers.$1,
        deluxe: covers.$2,
        device: device,
        spec: spec,
      );
      if (deluxe) await _selectDeluxe(tester);
      await settleLab(tester);
      await settleLab(tester);
      await _scroll(tester, to);
      return (await captureLab(tester, pixelRatio: 2)).$2;
    }

    final rows = <List<BoardCell>>[
      for (final v in LabVariant.values)
        [
          BoardCell('${v.label} · Standard', await shot(_covers(v), 0)),
          BoardCell(
            '${v.label} · Deluxe',
            await shot(_covers(v), 0, deluxe: true),
          ),
          BoardCell('${v.label} · Collapsed', await shot(_covers(v), 900)),
        ],
    ];
    await writeBoard(
      tester,
      '$_out/board_album_profile.png',
      'Album Profile (production) with the Lab rendering · generated covers',
      rows,
    );

    if (_realArt.isEmpty) return;
    String? f(String name) {
      final file = File('$_realArt/$name');
      return file.existsSync() ? file.path : null;
    }

    final locket = (f('locket_locket.png'), f('locket_locket_deluxe.png'));
    final sun = (
      f('midnight_sun_midnight_sun.png'),
      f('midnight_sun_midnight_sun.png'),
    );
    await writeBoard(
      tester,
      '$_out/real/board_album_profile_real.png',
      'Album Profile (production) · real covers (local only)',
      [
        [
          BoardCell('locket · Standard', await shot(locket, 0)),
          BoardCell('locket · Deluxe', await shot(locket, 0, deluxe: true)),
          BoardCell('locket · Collapsed', await shot(locket, 900)),
        ],
        [
          BoardCell('Midnight Sun · Standard', await shot(sun, 0)),
          BoardCell('Midnight Sun · Collapsed', await shot(sun, 900)),
          BoardCell(
            'locket · 360x780',
            await shot(locket, 0, device: LabDevice.small),
          ),
        ],
        [
          BoardCell(
            'locket · 2x text',
            await shot(locket, 0, device: LabDevice.s26.withText(2.0)),
          ),
          BoardCell(
            'locket · High contrast',
            await shot(
              locket,
              0,
              spec: const SonusAppearanceSpec(highContrast: true),
            ),
          ),
          BoardCell(
            'locket · Low effects',
            await shot(
              locket,
              0,
              spec: const SonusAppearanceSpec(lowEffects: true),
            ),
          ),
        ],
      ],
    );
  });
}
