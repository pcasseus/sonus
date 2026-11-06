// Artist Profile Lab: measured acceptance of the prototype's rendering, on
// generated artwork (cool, warm, neutral, near-white). These pin what the
// boards were approved with; the look itself is judged on the boards and,
// later, on the device. Hue or saturation alone is never the measure.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/prototypes/profile_lab/profile_lab_atmosphere.dart';
import 'package:sonus_next/prototypes/profile_lab/profile_lab_page.dart';

import '../support/device_layout.dart' show s26UltraSize;
import 'support/lab_harness.dart';
import 'support/lab_metrics.dart';

Finder _key(String key) => find.byKey(ValueKey<String>(key));

/// Thresholds from the first approved-for-review renders (see the boards'
/// metrics.json). The production profile measured a page-wide luminance
/// ratio of about 1.38:1 with no imagery behind content.
abstract final class LabTargets {
  static const double minimumBackdropSpread = 12; // L* units, P5..P95
  static const double minimumBackdropRatio = 1.8;
  static const double minimumImageryTop = 0.35;
  static const double minimumImageryScrolled = 0.15;
  static const double minimumGlassDelta = 2.5; // L* units
}

void main() {
  setUpAll(loadBaselineFonts);

  Future<LabPixels> render(
    WidgetTester tester,
    LabVariant variant,
    LabState state, {
    LabLayers layers = LabLayers.all,
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  }) async {
    final scroll = await pumpLab(
      tester,
      profile: labProfile(variant),
      layers: layers,
      spec: spec,
    );
    await scrollLab(tester, scroll, state);
    return (await captureLab(tester)).$1;
  }

  /// Every shown text in [state], measured on the ground under it.
  Future<List<TextContrast>> texts(
    WidgetTester tester,
    LabVariant variant,
    LabState state, {
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  }) async {
    final scroll = await pumpLab(
      tester,
      profile: labProfile(variant),
      spec: spec,
    );
    await scrollLab(tester, scroll, state);
    final offset = scroll.offset;
    final samples = collectTexts(tester);
    final inkless = await pumpLab(
      tester,
      profile: labProfile(variant),
      spec: spec,
      layers: LabLayers.all.copyWith(ink: false),
    );
    inkless.jumpTo(offset);
    await tester.pump();
    await settleLab(tester);
    return measureTexts(samples, (await captureLab(tester)).$1);
  }

  group('every phone and text size lays out without overflow', () {
    for (final device in [
      for (final phone in LabDevice.phones) ...[
        phone,
        phone.withText(1.3),
        phone.withText(2.0),
      ],
    ]) {
      testWidgets(device.name, (tester) async {
        for (final variant in [LabVariant.cool, LabVariant.bright]) {
          final scroll = await pumpLab(
            tester,
            profile: labProfile(variant),
            device: device,
          );
          for (final state in LabState.values) {
            await scrollLab(tester, scroll, state);
            expect(tester.takeException(), isNull, reason: '$variant $state');
          }
        }
      });
    }
  });

  group('text is readable on the ground actually under it', () {
    for (final variant in LabVariant.values) {
      for (final state in LabState.values) {
        testWidgets('${variant.label}, ${state.label}', (tester) async {
          final measured = await texts(tester, variant, state);
          expect(measured.length, greaterThan(8));
          final failing = [
            for (final t in measured)
              if (!t.passes) '${t.text}: ${t.worst.toStringAsFixed(2)}',
          ];
          expect(failing, isEmpty);
        });
      }
    }
  });

  group('the backdrop is a lit environment, not one flat tint', () {
    for (final variant in LabVariant.values) {
      testWidgets(variant.label, (tester) async {
        final backdrop = await render(
          tester,
          variant,
          LabState.middle,
          layers: LabLayers.groundOnly.copyWith(
            backdropImage: true,
            lights: true,
            ink: false,
          ),
        );
        final range = LightnessRange.of(backdrop, Offset.zero & s26UltraSize);
        expect(range.spread, greaterThan(LabTargets.minimumBackdropSpread));
        expect(
          range.luminanceRatio,
          greaterThan(LabTargets.minimumBackdropRatio),
        );
        // Tone-mapped: never a bright page, even for near-white artwork.
        expect(range.p95, lessThan(60));
      });
    }
  });

  group('imagery covers the page', () {
    for (final variant in LabVariant.values) {
      for (final (state, minimum) in [
        (LabState.top, LabTargets.minimumImageryTop),
        (LabState.middle, LabTargets.minimumImageryScrolled),
      ]) {
        testWidgets('${variant.label}, ${state.label}', (tester) async {
          final withImagery = await render(
            tester,
            variant,
            state,
            layers: LabLayers.all.copyWith(ink: false),
          );
          final without = await render(
            tester,
            variant,
            state,
            layers: LabLayers.all.copyWith(ink: false).withoutImagery,
          );
          expect(
            imageryCoverage(withImagery, without, Offset.zero & s26UltraSize),
            greaterThan(minimum),
          );
        });
      }
    }
  });

  group('glass reads as its own material', () {
    for (final variant in LabVariant.values) {
      testWidgets(variant.label, (tester) async {
        const bare = LabLayers(ink: false, thumbnails: false);
        final withGlass = await render(
          tester,
          variant,
          LabState.middle,
          layers: bare,
        );
        final card = tester.getRect(_key('lab-top-tracks-card'));
        final withoutGlass = await render(
          tester,
          variant,
          LabState.middle,
          layers: bare.copyWith(glass: false),
        );
        final separation = GlassSeparation.of(
          withGlass,
          withoutGlass,
          // The whole plate, as far as it is on screen above the player.
          Rect.fromLTRB(
            card.left,
            card.top,
            card.right,
            card.bottom.clamp(
              card.top,
              tester.getRect(_key('lab-mini-player')).top,
            ),
          ),
        );
        expect(separation.delta, greaterThan(LabTargets.minimumGlassDelta));
      });
    }
  });

  group('geometry', () {
    for (final device in LabDevice.phones) {
      testWidgets(device.name, (tester) async {
        final scroll = await pumpLab(
          tester,
          profile: labProfile(LabVariant.cool),
          device: device,
        );
        final photo = tester.getRect(_key('lab-hero-photo'));
        expect(photo.top, 0);
        expect(photo.height, LabGeometry.heroPhotoHeight(device.size));
        final portrait = tester.getRect(_key('lab-portrait'));
        // The identity rises into the photo's lower part.
        expect(portrait.top, lessThan(photo.bottom));
        expect(portrait.bottom, greaterThan(photo.bottom - 40));
        expect(
          tester.getRect(_key('lab-name')).right,
          lessThanOrEqualTo(device.size.width - 20),
        );
        for (final key in ['lab-shuffle', 'lab-favourite', 'lab-play']) {
          expect(tester.getSize(_key(key)).height, greaterThanOrEqualTo(48));
        }
        await scrollLab(tester, scroll, LabState.middle);
        for (var i = 0; i < 5; i++) {
          expect(
            tester.getSize(_key('lab-track-$i')).height,
            greaterThanOrEqualTo(LabGeometry.trackRowHeight),
          );
        }
        // Every icon button (row menus, toolbar, player) is a full target.
        final buttons = find.byType(IconButton);
        for (var i = 0; i < buttons.evaluate().length; i++) {
          final size = tester.getSize(buttons.at(i));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        await scrollLab(tester, scroll, LabState.collapsed);
        final top = tester.view.padding.top / tester.view.devicePixelRatio;
        expect(
          tester.getSize(_key('lab-toolbar')).height,
          top + LabGeometry.toolbarHeight,
        );
        expect(
          tester.widget<AnimatedOpacity>(_key('lab-toolbar-title')).opacity,
          1,
        );
      });
    }
  });

  group('nothing stays under the mini-player', () {
    for (final device in [
      for (final phone in LabDevice.phones) ...[
        phone,
        phone.withText(1.3),
        phone.withText(2.0),
      ],
    ]) {
      testWidgets(device.name, (tester) async {
        final scroll = await pumpLab(
          tester,
          profile: labProfile(LabVariant.cool),
          device: device,
        );
        final player = tester.getRect(_key('lab-mini-player'));
        // At the top of the page every control is above the player.
        for (final key in [
          'lab-shuffle',
          'lab-play',
          'lab-favourite',
          'lab-tabs',
        ]) {
          expect(
            tester.getRect(_key(key)).bottom,
            lessThanOrEqualTo(player.top),
            reason: key,
          );
        }
        // At the end, the last content scrolls fully above it.
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump();
        expect(
          tester.getRect(_key('lab-collaborations')).bottom,
          lessThanOrEqualTo(player.top),
        );
      });
    }
  });

  testWidgets('S26: Top Tracks and Releases share one screen', (tester) async {
    final scroll = await pumpLab(tester, profile: labProfile(LabVariant.cool));
    await scrollLab(tester, scroll, LabState.middle);
    final toolbar = tester.getRect(_key('lab-toolbar'));
    final player = tester.getRect(_key('lab-mini-player'));
    final card = tester.getRect(_key('lab-top-tracks-card'));
    final releases = tester.getRect(_key('lab-releases-header'));
    expect(card.top, greaterThanOrEqualTo(toolbar.bottom));
    expect(releases.bottom, lessThanOrEqualTo(player.top));
  });

  group('accessibility modes give the flat, solid page', () {
    for (final (name, spec) in const [
      ('High contrast', SonusAppearanceSpec(highContrast: true)),
      ('Low effects', SonusAppearanceSpec(lowEffects: true)),
      (
        'Decoration Off',
        SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      ),
    ]) {
      testWidgets(name, (tester) async {
        final measured = await texts(
          tester,
          LabVariant.cool,
          LabState.top,
          spec: spec,
        );
        expect(_key('lab-backdrop-image'), findsNothing);
        expect(_key('lab-backdrop-lights'), findsNothing);
        // The hero photo stays (it is content); everything else is solid.
        final offPhoto = measured.where(
          (t) => t.rect.top > LabGeometry.heroPhotoHeight(s26UltraSize),
        );
        expect(offPhoto, isNotEmpty);
        for (final t in offPhoto) {
          expect(t.worst, greaterThanOrEqualTo(t.required), reason: t.text);
        }
      });
    }
  });

  testWidgets('Reduce motion switches the toolbar title at once', (
    tester,
  ) async {
    await pumpLab(
      tester,
      profile: labProfile(LabVariant.cool),
      spec: const SonusAppearanceSpec(reduceMotion: true),
    );
    expect(
      tester.widget<AnimatedOpacity>(_key('lab-toolbar-title')).duration,
      Duration.zero,
    );
  });

  testWidgets('real Material icons render (not the test font squares)', (
    tester,
  ) async {
    final pixels = await render(tester, LabVariant.cool, LabState.top);
    final heart = tester.getRect(
      find.descendant(of: _key('lab-favourite'), matching: find.byType(Icon)),
    );
    final ground = pixels.at(
      ((heart.left - 6) * pixels.scale).round(),
      (heart.center.dy * pixels.scale).round(),
    );
    expect(glyphCoverage(pixels, heart, ground), lessThan(0.5));
  });

  test('no production code imports the lab', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (path.contains('lib/prototypes/')) continue;
      if (file.readAsStringSync().contains('prototypes/')) offenders.add(path);
    }
    expect(offenders, isEmpty);
  });
}
