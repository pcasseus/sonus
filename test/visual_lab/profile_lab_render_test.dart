// Artist Profile Lab: screenshot boards and measured results for visual
// review. Writes nothing unless an output folder is given, so the normal
// test suite never produces files:
//
//   flutter test test/visual_lab/profile_lab_render_test.dart \
//     --dart-define=SONUS_LAB_OUT=C:/dev/sonus/test_runs/profile_lab
//
// Optional, local only (never committed; the repository is public):
//   --dart-define=SONUS_LAB_REFERENCE=<the approved reference image>
//   --dart-define=SONUS_LAB_REAL_ART=<folder of real covers and photos>
// Real-artwork renders are written under <out>/real/.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/prototypes/profile_lab/profile_lab_atmosphere.dart';
import 'package:sonus_next/prototypes/profile_lab/profile_lab_models.dart';

import 'support/lab_board.dart';
import 'support/lab_harness.dart';
import 'support/lab_metrics.dart';

const String _out = String.fromEnvironment('SONUS_LAB_OUT');
const String _reference = String.fromEnvironment('SONUS_LAB_REFERENCE');
const String _realArt = String.fromEnvironment('SONUS_LAB_REAL_ART');

const double _boardRatio = 2;

void main() {
  final skip = _out.isEmpty ? 'set --dart-define=SONUS_LAB_OUT=<folder>' : null;
  final metrics = <String, Object>{};
  setUpAll(loadBaselineFonts);

  tearDownAll(() {
    if (_out.isEmpty || metrics.isEmpty) return;
    File('$_out/metrics.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(metrics));
  });

  Future<ui.Image> shot(
    WidgetTester tester,
    LabArtistProfile profile,
    LabState state, {
    LabDevice device = LabDevice.s26,
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    LabLayers layers = LabLayers.all,
    String? measureAs,
  }) async {
    final scroll = await pumpLab(
      tester,
      profile: profile,
      device: device,
      spec: spec,
      layers: layers,
    );
    await scrollLab(tester, scroll, state);
    final (_, image) = await captureLab(tester, pixelRatio: _boardRatio);
    if (measureAs != null) {
      metrics[measureAs] = await _measure(
        tester,
        profile,
        scroll,
        state,
        device,
        spec,
      );
    }
    return image;
  }

  testWidgets('board: variants x states at S26 Ultra', skip: skip != null, (
    tester,
  ) async {
    final rows = <List<BoardCell>>[];
    for (final variant in LabVariant.values) {
      final profile = labProfile(variant);
      rows.add([
        for (final state in LabState.values)
          BoardCell(
            '${variant.label} · ${state.label}',
            await shot(
              tester,
              profile,
              state,
              measureAs: '${variant.name}_${state.name}',
            ),
          ),
      ]);
    }
    await writeBoard(
      tester,
      '$_out/board_variants_s26.png',
      'Artist Profile Lab · generated artwork · S26 Ultra 384×832',
      rows,
    );
  });

  testWidgets('board: phones and text sizes', skip: skip != null, (
    tester,
  ) async {
    final profile = labProfile(LabVariant.cool);
    final cells = <BoardCell>[];
    for (final device in [
      ...LabDevice.phones,
      LabDevice.s26.withText(1.3),
      LabDevice.s26.withText(2.0),
    ]) {
      cells.add(
        BoardCell(
          device.name,
          await shot(tester, profile, LabState.top, device: device),
        ),
      );
    }
    final collapsed = <BoardCell>[];
    for (final device in LabDevice.phones) {
      collapsed.add(
        BoardCell(
          '${device.name} · collapsed',
          await shot(tester, profile, LabState.collapsed, device: device),
        ),
      );
    }
    // 2x text: every state, on the S26 and the small phone (clearance).
    final large = <List<BoardCell>>[];
    for (final device in [
      LabDevice.s26.withText(2.0),
      LabDevice.small.withText(2.0),
    ]) {
      large.add([
        for (final state in LabState.values)
          BoardCell(
            '${device.name} · ${state.label}',
            await shot(tester, profile, state, device: device),
          ),
      ]);
    }
    await writeBoard(
      tester,
      '$_out/board_sizes.png',
      'Phones and text sizes · cool artwork',
      [cells, collapsed, ...large],
      cellHeight: 900,
    );
  });

  testWidgets('board: accessibility modes', skip: skip != null, (tester) async {
    final rows = <List<BoardCell>>[];
    for (final variant in [LabVariant.cool, LabVariant.bright]) {
      final profile = labProfile(variant);
      rows.add([
        for (final (name, spec) in const [
          ('Standard', SonusAppearanceSpec()),
          ('High contrast', SonusAppearanceSpec(highContrast: true)),
          ('Low effects', SonusAppearanceSpec(lowEffects: true)),
          (
            'Decoration Off',
            SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
          ),
        ])
          BoardCell(
            '${variant.label} · $name',
            await shot(
              tester,
              profile,
              LabState.top,
              spec: spec,
              measureAs: spec == const SonusAppearanceSpec()
                  ? null
                  : '${variant.name}_${name.toLowerCase().replaceAll(' ', '_')}',
            ),
          ),
      ]);
    }
    await writeBoard(
      tester,
      '$_out/board_modes.png',
      'Accessibility and effects modes',
      rows,
    );
  });

  testWidgets('board: layers, built up', skip: skip != null, (tester) async {
    final rows = <List<BoardCell>>[];
    for (final variant in [LabVariant.cool, LabVariant.warm]) {
      final profile = labProfile(variant);
      final steps = [
        ('1 Ground only', LabLayers.groundOnly),
        (
          '2 + blurred artwork',
          LabLayers.groundOnly.copyWith(backdropImage: true),
        ),
        (
          '3 + light',
          LabLayers.groundOnly.copyWith(backdropImage: true, lights: true),
        ),
        (
          '4 + photo, scrims',
          LabLayers.groundOnly.copyWith(
            backdropImage: true,
            lights: true,
            heroPhoto: true,
            scrims: true,
          ),
        ),
        ('5 + glass, pictures (full)', LabLayers.all),
      ];
      rows.add([
        for (final (name, layers) in steps)
          BoardCell(
            '${variant.label} · $name',
            await shot(tester, profile, LabState.middle, layers: layers),
          ),
      ]);
    }
    await writeBoard(
      tester,
      '$_out/board_layers.png',
      'Layers, back to front (scrolled to Top Tracks)',
      rows,
      cellHeight: 900,
    );
  });

  testWidgets('board: comparison with the reference', skip: skip != null, (
    tester,
  ) async {
    final row = <BoardCell>[];
    final reference = _reference.isEmpty
        ? null
        : await loadImageFile(tester, _reference);
    if (reference != null) {
      // The reference holds two phones; the Artist Profile is the left one.
      row.add(
        BoardCell(
          'Reference (approved direction)',
          reference,
          source: Rect.fromLTWH(
            0,
            0,
            reference.width / 2,
            reference.height.toDouble(),
          ),
        ),
      );
    }
    final real = _realProfiles();
    // The reference beside the lab on comparable (real) artwork first.
    for (final (name, profile) in real.take(2)) {
      row.add(
        BoardCell('Lab · $name', await shot(tester, profile, LabState.top)),
      );
    }
    for (final variant in [LabVariant.cool, LabVariant.warm]) {
      row.add(
        BoardCell(
          'Lab · ${variant.label} (generated)',
          await shot(tester, labProfile(variant), LabState.top),
        ),
      );
    }
    final realRow = <BoardCell>[];
    for (final (name, profile) in real) {
      for (final state in LabState.values) {
        realRow.add(
          BoardCell(
            '$name · ${state.label}',
            await shot(
              tester,
              profile,
              state,
              measureAs: 'real_${name.toLowerCase()}_${state.name}',
            ),
          ),
        );
      }
    }
    // A board that shows the reference or real artwork stays local.
    final local = reference != null || realRow.isNotEmpty;
    await writeBoard(
      tester,
      local ? '$_out/real/board_reference.png' : '$_out/board_reference.png',
      'Reference and the lab, side by side',
      [row],
    );
    if (realRow.isNotEmpty) {
      await writeBoard(
        tester,
        '$_out/real/board_real_artwork.png',
        'Real artwork (local only, never committed)',
        [for (var i = 0; i < realRow.length; i += 3) realRow.sublist(i, i + 3)],
      );
      // Real artwork on a small phone, with large text, and in the
      // accessibility modes.
      final (name, cool) = real.first;
      final sizes = <BoardCell>[
        for (final (device, state) in [
          (LabDevice.small, LabState.top),
          (LabDevice.small, LabState.middle),
          (LabDevice.s26.withText(1.3), LabState.top),
          (LabDevice.s26.withText(2.0), LabState.top),
          (LabDevice.s26.withText(2.0), LabState.middle),
        ])
          BoardCell(
            '$name · ${device.name} · ${state.label}',
            await shot(tester, cool, state, device: device),
          ),
      ];
      final modes = <List<BoardCell>>[
        for (final (label, spec) in const [
          ('High contrast', SonusAppearanceSpec(highContrast: true)),
          ('Low effects', SonusAppearanceSpec(lowEffects: true)),
        ])
          [
            for (final (n, p) in real)
              BoardCell(
                '$n · $label',
                await shot(tester, p, LabState.top, spec: spec),
              ),
          ],
      ];
      await writeBoard(
        tester,
        '$_out/real/board_real_sizes_modes.png',
        'Real artwork: small phone, large text, High contrast, Low effects',
        [sizes, ...modes],
        cellHeight: 900,
      );
    }
  });
}

/// Real artwork from a local folder (the audit's read-only copies), when
/// given; empty otherwise.
List<(String, LabArtistProfile)> _realProfiles() {
  if (_realArt.isEmpty) return const [];
  String? file(String name) {
    final f = File('$_realArt/$name');
    return f.existsSync() ? f.path : null;
  }

  final covers = [
    file('locket_locket.png'),
    file('locket_locket_deluxe.png'),
    file('midnight_sun_midnight_sun.png'),
  ];
  return [
    if (file('madison_banner.png') != null)
      (
        'Cool real',
        labProfile(
          LabVariant.cool,
          bannerPath: file('madison_banner.png'),
          portraitPath: file('madison_portrait.png'),
          covers: covers,
        ),
      ),
    if (file('zara_banner.png') != null)
      (
        'Warm real',
        labProfile(
          LabVariant.warm,
          bannerPath: file('zara_banner.png'),
          portraitPath: file('zara_portrait.png'),
          covers: covers.reversed.toList(),
        ),
      ),
    if (file('locket_locket_deluxe.png') != null)
      (
        'Neutral real',
        labProfile(
          LabVariant.neutral,
          bannerPath: file('locket_locket_deluxe.png'),
          portraitPath: file('locket_locket_deluxe.png'),
          covers: covers,
        ),
      ),
  ];
}

/// The measured results for the current page and state.
Future<Map<String, Object>> _measure(
  WidgetTester tester,
  LabArtistProfile profile,
  ScrollController scroll,
  LabState state,
  LabDevice device,
  SonusAppearanceSpec spec,
) async {
  final screen = Offset.zero & device.size;
  final offset = scroll.offset;
  Future<LabPixels> render(LabLayers layers) async {
    final s = await pumpLab(
      tester,
      profile: profile,
      device: device,
      spec: spec,
      layers: layers,
    );
    s.jumpTo(offset);
    await tester.pump();
    await settleLab(tester);
    return (await captureLab(tester)).$1;
  }

  final full = await render(LabLayers.all);
  final samples = collectTexts(tester);
  final inkless = await render(LabLayers.all.copyWith(ink: false));
  final texts = measureTexts(samples, inkless);
  final noImagery = await render(
    LabLayers.all.copyWith(ink: false).withoutImagery,
  );
  final backdrop = await render(
    LabLayers.groundOnly.copyWith(
      backdropImage: true,
      lights: true,
      ink: false,
    ),
  );
  final ground = await render(LabLayers.groundOnly.copyWith(ink: false));
  final bare = await render(const LabLayers(ink: false, thumbnails: false));
  final bareNoGlass = await render(
    const LabLayers(ink: false, thumbnails: false, glass: false),
  );
  final glass = <String, Object>{};
  for (final key in [
    'lab-top-tracks-card',
    'lab-stats',
    'lab-tabs',
    'lab-collaboration-0',
  ]) {
    final f = find.byKey(ValueKey<String>(key));
    if (f.evaluate().isEmpty) continue;
    final rect = tester.getRect(f);
    if (rect.top < 100 || rect.bottom > device.size.height) continue;
    glass[key] = GlassSeparation.of(bare, bareNoGlass, rect).toJson();
  }
  final failing = texts.where((t) => !t.passes).toList();
  texts.sort((a, b) => a.worst.compareTo(b.worst));
  return {
    'offset': offset.round(),
    'imagery_coverage': _r(imageryCoverage(inkless, noImagery, screen)),
    'backdrop': LightnessRange.of(backdrop, screen).toJson(),
    'page_inkless': LightnessRange.of(inkless, screen).toJson(),
    'backdrop_vs_ground_meanDeltaE': _r(meanDeltaE(backdrop, ground, screen)),
    'glass': glass,
    'texts_measured': texts.length,
    'texts_below_requirement': failing.length,
    'weakest_texts': [for (final t in texts.take(5)) t.toJson()],
    'full_page': LightnessRange.of(full, screen).toJson(),
  };
}

double _r(double v) => (v * 1000).round() / 1000;
