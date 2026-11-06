// Protected baseline: the full-screen player (Now Playing), opened from the
// mini-player as on the phone. Owned files and shared dependencies: see
// protected_manifest.json ("now_playing").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/shell/domain/models/app_destination.dart';

import 'support/baseline_app.dart';
import 'support/geometry_baseline.dart';

Future<void> openNowPlaying(
  WidgetTester tester,
  BaselineScenario scenario,
) async {
  await pumpBaselineApp(tester, scenario, destination: AppDestination.tracks);
  await tester.tap(byKey('mini-player-open'));
  await settleArtwork(tester);
  expect(byKey('now-playing-artwork'), findsOneWidget);
}

Map<String, Finder> nowPlayingParts() => {
  'artwork': byKey('now-playing-artwork'),
  'title': byKey('now-playing-title'),
  'artist': byKey('now-playing-artist'),
  'album': byKey('now-playing-album'),
  'seek': byKey('now-playing-seek'),
  'elapsed': byKey('now-playing-elapsed'),
  'previous': byKey('now-playing-previous'),
  'playPause': byKey('now-playing-play-pause'),
  'next': byKey('now-playing-next'),
  'shuffle': byKey('now-playing-shuffle'),
  'repeat': byKey('now-playing-repeat'),
  'queue': byKey('now-playing-queue'),
  'lyrics': byKey('now-playing-lyrics'),
  'miniPlayer': byKey('playback-host-bar'),
};

/// Now Playing needs a song, so its matrix has no "no track" state; the
/// remaining standard scenarios plus the 2x text extreme.
final List<BaselineScenario> nowPlayingScenarios = [
  for (final scenario in standardScenarios)
    if (scenario.withTrack) scenario,
  const BaselineScenario('s26_text_2_0', textScale: 2),
  const BaselineScenario(
    's26_monochrome_high_contrast',
    spec: SonusAppearanceSpec(
      themeId: SonusThemeId.monochrome,
      highContrast: true,
    ),
  ),
];

void main() {
  final geometry = GeometryBaseline(
    'test/visual_baselines/goldens/now_playing/geometry.json',
  )..register();

  group('Now Playing golden baselines', () {
    for (final scenario in nowPlayingScenarios) {
      testWidgets(scenario.name, (tester) async {
        await openNowPlaying(tester, scenario);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/now_playing/${scenario.name}.png'),
        );
      });
    }
  });

  group('Now Playing pinned geometry', () {
    for (final scenario in geometryScenarios(withoutTrack: false)) {
      testWidgets(scenario.name, (tester) async {
        await openNowPlaying(tester, scenario);
        expect(tester.takeException(), isNull);
        expect(
          byKey('playback-host-bar'),
          findsNothing,
          reason: 'the mini-player hides on Now Playing',
        );
        geometry.check(tester, scenario.name, nowPlayingParts());
      });
    }
  });
}
