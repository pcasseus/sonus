// Protected baseline: the Film Reel (approved, unchanged), the Library's
// alternative view, inside the real shell. Owned files and shared
// dependencies: see protected_manifest.json ("film_reel").
//
// Known behaviour, pinned as approved (not a defect to fix here): the reel
// has no mini-player allowance, so it is taller by the mini-player's height
// when nothing is queued. At 360 x 780 the extra height even changes the
// layout: the stacked layout (statistics below) with the mini-player, the
// three-panel reel without it. Both are pinned in goldens/film_reel/
// geometry.json.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/widgets/playback/sonus_mini_player.dart';
import 'package:sonus_next/features/shell/domain/models/app_destination.dart';

import 'support/baseline_app.dart';
import 'support/geometry_baseline.dart';

Future<void> openFilmReel(
  WidgetTester tester,
  BaselineScenario scenario,
) async {
  await pumpBaselineApp(tester, scenario, destination: AppDestination.library);
  await tester.tap(byKey('library-view-reel'));
  await settleArtwork(tester);
  expect(byKey('film-reel-pages'), findsOneWidget);
}

Map<String, Finder> reelParts() => {
  'pages': byKey('film-reel-pages'),
  'panelLeft': byKey('film-reel-panel-left'),
  'panelRight': byKey('film-reel-panel-right'),
  'statsBelow': byKey('film-reel-stats-below'),
  'rank': byKey('film-reel-rank'),
  'topTrack': byKey('film-reel-top-track'),
  'previous': byKey('film-reel-previous'),
  'next': byKey('film-reel-next'),
  'miniPlayer': byKey('playback-host-bar'),
};

void main() {
  final geometry = GeometryBaseline(
    'test/visual_baselines/goldens/film_reel/geometry.json',
  )..register();

  group('Film Reel golden baselines', () {
    for (final scenario in standardScenarios) {
      testWidgets(scenario.name, (tester) async {
        await openFilmReel(tester, scenario);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/film_reel/${scenario.name}.png'),
        );
      });
    }
  });

  group('Film Reel pinned geometry', () {
    for (final scenario in geometryScenarios()) {
      testWidgets(scenario.name, (tester) async {
        await openFilmReel(tester, scenario);
        expect(tester.takeException(), isNull);
        geometry.check(tester, scenario.name, reelParts());
      });
    }
  });

  testWidgets('approved behaviour: without the mini-player the reel is '
      'taller by exactly the mini-player\'s height (normal text; with '
      'enlarged text the stacked layout shares the height, pinned in the '
      'geometry above)', (tester) async {
    final normalText = geometryScenarios(
      withoutTrack: false,
    ).where((scenario) => scenario.textScale == 1 && scenario.size.width > 360);
    for (final scenario in normalText) {
      await openFilmReel(tester, scenario);
      final withBar = tester.getSize(byKey('film-reel-pages')).height;
      final context = tester.element(byKey('film-reel-pages'));
      final added = SonusMiniPlayer.addedHeight(context);

      await openFilmReel(
        tester,
        BaselineScenario(
          '${scenario.name}_no_track',
          size: scenario.size,
          ratio: scenario.ratio,
          textScale: scenario.textScale,
          withTrack: false,
        ),
      );
      final without = tester.getSize(byKey('film-reel-pages')).height;
      expect(
        without - withBar,
        closeTo(added, 1.5),
        reason: '${scenario.name}: the reel takes the freed height',
      );
    }
  });
}
