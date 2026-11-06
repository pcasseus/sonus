// Protected baseline: Home, inside the real shell. Owned files and shared
// dependencies: see protected_manifest.json ("home").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/baseline_app.dart';
import 'support/geometry_baseline.dart';

Map<String, Finder> homeParts() => {
  'popularHeading': byKey('home-popular-heading'),
  'firstPopularTrack': byKey('home-popular-track-song-0'),
  'secondPopularTrack': byKey('home-popular-track-song-1'),
  'topArtistsHeading': byKey('home-top-artists-heading'),
  'firstTopArtist': byKey('home-top-artist-artist-0'),
  'secondTopArtist': byKey('home-top-artist-artist-1'),
  'miniPlayer': byKey('playback-host-bar'),
};

void main() {
  final geometry = GeometryBaseline(
    'test/visual_baselines/goldens/home/geometry.json',
  )..register();

  group('Home golden baselines', () {
    for (final scenario in standardScenarios) {
      testWidgets(scenario.name, (tester) async {
        await pumpBaselineApp(tester, scenario);
        expect(byKey('home-popular-heading'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/home/${scenario.name}.png'),
        );
      });
    }

    // The lower part of Home (New Releases), scrolled into view.
    for (final scenario in const [
      BaselineScenario('s26_scrolled_track'),
      BaselineScenario('s26_scrolled_no_track', withTrack: false),
    ]) {
      testWidgets(scenario.name, (tester) async {
        await pumpBaselineApp(tester, scenario);
        await tester.drag(
          byKey('home-top-artists-heading'),
          const Offset(0, -700),
        );
        await settleArtwork(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/home/${scenario.name}.png'),
        );
      });
    }
  });

  group('Home pinned geometry', () {
    for (final scenario in geometryScenarios()) {
      testWidgets(scenario.name, (tester) async {
        await pumpBaselineApp(tester, scenario);
        expect(tester.takeException(), isNull);
        geometry.check(tester, scenario.name, homeParts());
      });
    }
  });
}
