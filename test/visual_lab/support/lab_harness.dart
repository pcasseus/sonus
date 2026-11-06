// Render harness for the Artist Profile Lab: illustrative content, the
// real Sonus theme with real fonts, pumping, scrolling and pixel capture.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/prototypes/profile_lab/profile_lab_atmosphere.dart';
import 'package:sonus_next/prototypes/profile_lab/profile_lab_models.dart';
import 'package:sonus_next/prototypes/profile_lab/profile_lab_page.dart';

import '../../support/device_layout.dart';
import 'lab_artwork.dart';

export '../../visual_baselines/support/baseline_fonts.dart'
    show loadBaselineFonts;
export 'lab_artwork.dart';

/// Illustrative content only (names, counts and titles are invented).
LabArtistProfile labProfile(
  LabVariant variant, {
  String? bannerPath,
  String? portraitPath,
  List<String?>? covers,
}) {
  final art = LabArtworkFiles.ensure();
  final cover =
      covers ??
      [
        art.cover('cool'),
        art.cover('hue_0'),
        art.cover('warm'),
        art.cover('neutral'),
        art.cover('hue_1'),
        art.cover('hue_2'),
      ];
  String? c(int i) => cover[i % cover.length];
  final tracks = [
    LabTrack(
      title: 'Glass Hours',
      releaseTitle: 'Harbour Lights',
      streams: 18,
      artworkPath: c(0),
      isPlaying: true,
    ),
    LabTrack(
      title: 'Slow Static',
      releaseTitle: 'Harbour Lights',
      streams: 14,
      artworkPath: c(0),
    ),
    LabTrack(
      title: 'Velvet Signal',
      releaseTitle: 'Afterglow (Deluxe)',
      streams: 11,
      artworkPath: c(1),
    ),
    LabTrack(
      title: 'Northern Window',
      releaseTitle: 'Paper Moons',
      streams: 9,
      artworkPath: c(2),
    ),
    LabTrack(
      title: 'Little Earthquake Season',
      releaseTitle: 'Paper Moons',
      streams: 6,
      artworkPath: c(2),
    ),
  ];
  return LabArtistProfile(
    name: 'Ayo Nova',
    bannerPath: bannerPath ?? art.banner(variant),
    portraitPath: portraitPath ?? art.portrait(variant),
    standing: 'Your #1 artist',
    streams: 64,
    listened: const Duration(hours: 3, minutes: 20),
    topTracks: tracks,
    releases: [
      LabRelease(title: 'Harbour Lights', year: 2026, artworkPath: c(0)),
      LabRelease(
        title: 'Afterglow',
        year: 2025,
        edition: 'Deluxe',
        artworkPath: c(1),
      ),
      LabRelease(title: 'Paper Moons', year: 2024, artworkPath: c(2)),
      LabRelease(title: 'Quiet Engines', year: 2022, artworkPath: c(3)),
      LabRelease(title: 'First Light EP', year: 2021, artworkPath: c(4)),
      LabRelease(title: 'Demos', year: 2019, artworkPath: c(5)),
    ],
    collaborations: [
      LabCollaboration(
        partnerName: 'Kemi Ade',
        songCount: 4,
        partnerPortraitPath: art.partner(0),
      ),
      LabCollaboration(
        partnerName: 'The Harbour Choir',
        songCount: 2,
        partnerPortraitPath: art.partner(1),
      ),
      LabCollaboration(
        partnerName: 'Lio Marsh',
        songCount: 1,
        partnerPortraitPath: art.partner(2),
      ),
    ],
    nowPlaying: tracks.first,
  );
}

/// The Sonus theme with real Roboto (the test runner's own font is square).
ThemeData labTheme(SonusAppearanceSpec spec) {
  final base = SonusThemeFactory.build(spec);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: realRobotoFamily),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: realRobotoFamily,
      ),
    ),
  );
}

const ValueKey<String> labCaptureKey = ValueKey<String>('lab-capture');

/// A phone and text size to render at.
class LabDevice {
  const LabDevice(this.name, this.size, this.ratio, {this.textScale = 1});

  final String name;
  final Size size;
  final double ratio;
  final double textScale;

  LabDevice withText(double scale) =>
      LabDevice('${name}_text_$scale', size, ratio, textScale: scale);

  static const s26 = LabDevice('s26', s26UltraSize, s26UltraRatio);
  static const small = LabDevice('360x780', Size(360, 780), 3.0);
  static const large = LabDevice('412x915', Size(412, 915), 2.625);
  static const phones = [small, s26, large];
}

/// Where the page is scrolled to for a capture.
enum LabState {
  top('Top'),
  middle('Middle (Top Tracks)'),
  collapsed('Collapsed header');

  const LabState(this.label);
  final String label;
}

/// Pumps the lab page and lets artwork decode; returns its controller.
/// Call `setUpAll(loadBaselineFonts)` first: fonts cannot load inside a
/// widget test's fake async zone.
Future<ScrollController> pumpLab(
  WidgetTester tester, {
  required LabArtistProfile profile,
  LabDevice device = LabDevice.s26,
  SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  LabLayers layers = LabLayers.all,
  ScrollController? controller,
}) async {
  setDevice(tester, size: device.size, ratio: device.ratio);
  // Colours cannot be extracted in the fake async zone: warm the cache.
  await tester.runAsync(() async {
    for (final path in [profile.atmospherePath]) {
      await SonusArtworkPalette.shared.colorsFor(
        path,
        brightness: Brightness.dark,
      );
    }
  });
  final scroll = controller ?? ScrollController();
  if (controller == null) addTearDown(scroll.dispose);
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
      home: ProfileLabPage(
        profile: profile,
        layers: layers,
        scrollController: scroll,
      ),
    ),
  );
  await settleLab(tester);
  return scroll;
}

/// Lets real file reads and decoding finish (see the baselines' harness).
Future<void> settleLab(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (var round = 0; round < 6; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Scrolls to [state]: top, the Top Tracks header ~150dp below the top
/// (middle), or the Releases header ~200dp below it (collapsed header).
Future<void> scrollLab(
  WidgetTester tester,
  ScrollController scroll,
  LabState state,
) async {
  scroll.jumpTo(0);
  await tester.pump();
  if (state != LabState.top) {
    final (key, below) = state == LabState.middle
        ? ('lab-top-tracks-header', 150.0)
        : ('lab-releases-header', 200.0);
    final target = find.byKey(ValueKey<String>(key));
    // Slivers far below are not built yet: step down until it exists.
    while (target.evaluate().isEmpty &&
        scroll.offset < scroll.position.maxScrollExtent) {
      scroll.jumpTo(
        (scroll.offset + 300).clamp(0.0, scroll.position.maxScrollExtent),
      );
      await tester.pump();
    }
    final top = tester.getRect(target).top;
    scroll.jumpTo(
      (scroll.offset + top - below).clamp(0.0, scroll.position.maxScrollExtent),
    );
    await tester.pump();
  }
  await settleLab(tester);
}

/// RGBA pixels of a capture.
class LabPixels {
  LabPixels(this.width, this.height, this.rgba, this.scale);

  final int width;
  final int height;
  final Uint8List rgba;

  /// Pixels per logical pixel.
  final double scale;

  (int, int, int) at(int x, int y) {
    final i = (y * width + x) * 4;
    return (rgba[i], rgba[i + 1], rgba[i + 2]);
  }
}

/// Captures the whole app as pixels (and the image, for boards).
Future<(LabPixels, ui.Image)> captureLab(
  WidgetTester tester, {
  double pixelRatio = 1,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(labCaptureKey),
  );
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (
      LabPixels(
        image.width,
        image.height,
        data!.buffer.asUint8List(),
        pixelRatio,
      ),
      image,
    );
  });
  return result!;
}
