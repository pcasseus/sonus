// Protected baseline: navigation (the Sonus bar and tabs) and the
// mini-player, shown over a plain placeholder page so nothing else is in
// the picture. Owned files and shared dependencies: see
// protected_manifest.json ("navigation").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/widgets/playback/sonus_mini_player.dart';
import 'package:sonus_next/features/shell/domain/models/app_destination.dart';

import 'support/baseline_app.dart';
import 'support/geometry_baseline.dart';

Map<String, Finder> navigationParts() => {
  'appMark': byKey('sonus-app-mark'),
  'appTitle': byKey('sonus-app-title'),
  'searchButton': byKey('shell-search-button'),
  'importButton': byKey('shell-import-button'),
  'settingsButton': byKey('shell-settings-button'),
  'homeTab': byKey('app-tab-home'),
  'tracksTab': byKey('app-tab-tracks'),
  'pages': find.byType(PageView),
  'miniPlayer': byKey('playback-host-bar'),
  'miniPlayerArtwork': byKey('mini-player-artwork'),
  'miniPlayerTitle': byKey('mini-player-title'),
  'miniPlayerPlayPause': byKey('mini-player-play-pause'),
  'miniPlayerNext': byKey('mini-player-next'),
  'miniPlayerPrevious': byKey('mini-player-previous'),
  'miniPlayerQueue': byKey('mini-player-queue'),
  'miniPlayerProgress': byKey('mini-player-progress'),
};

const List<BaselineScenario> navigationScenarios = [
  ...standardScenarios,
  BaselineScenario('s26_text_2_0', textScale: 2),
  BaselineScenario(
    's26_monochrome_no_track',
    withTrack: false,
    spec: SonusAppearanceSpec(themeId: SonusThemeId.monochrome),
  ),
];

void main() {
  final geometry = GeometryBaseline(
    'test/visual_baselines/goldens/navigation/geometry.json',
  )..register();

  group('Navigation and mini-player golden baselines', () {
    for (final scenario in navigationScenarios) {
      testWidgets(scenario.name, (tester) async {
        await pumpBaselineApp(
          tester,
          scenario,
          destination: AppDestination.tracks,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/navigation/${scenario.name}.png'),
        );
      });
    }
  });

  group('Navigation and mini-player pinned geometry', () {
    for (final scenario in [
      ...geometryScenarios(),
      const BaselineScenario(
        '384x832_track_text_2.0',
        ratio: 2.8125,
        textScale: 2,
      ),
    ]) {
      testWidgets(scenario.name, (tester) async {
        await pumpBaselineApp(
          tester,
          scenario,
          destination: AppDestination.tracks,
        );
        expect(tester.takeException(), isNull);
        geometry.check(tester, scenario.name, navigationParts());
      });
    }
  });

  group('Mini-player placement rules', () {
    for (final scenario in geometryScenarios()) {
      testWidgets(scenario.name, (tester) async {
        await pumpBaselineApp(
          tester,
          scenario,
          destination: AppDestination.tracks,
        );
        final bar = byKey('playback-host-bar');
        if (!scenario.withTrack) {
          expect(bar, findsNothing, reason: 'no bar while nothing is queued');
          return;
        }
        expect(bar, findsOneWidget);
        final barRect = tester.getRect(bar);
        // The page ends where the bar begins: nothing is covered.
        expect(
          tester.getRect(find.byType(PageView)).bottom,
          lessThanOrEqualTo(barRect.top + 0.5),
        );
        // The bar sits on the bottom of the screen and is as tall as the
        // mini-player says it adds.
        expect(barRect.bottom, closeTo(scenario.size.height, 0.5));
        final added = SonusMiniPlayer.addedHeight(tester.element(bar));
        final systemBottom = 48.0; // the S26 Ultra's three-button bar
        expect(barRect.height, closeTo(added + systemBottom, 1.5));
      });
    }
  });
}
