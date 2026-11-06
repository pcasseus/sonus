// Protected baseline: the Artist Roster (accepted at a678b95), the Library's
// default view, inside the real shell. Owned files and shared dependencies:
// see protected_manifest.json ("roster").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/shell/domain/models/app_destination.dart';

import '../support/device_layout.dart';
import 'support/baseline_app.dart';
import 'support/geometry_baseline.dart';

Map<String, Finder> rosterParts() => {
  'roster': byKey('artist-roster'),
  'compact': byKey('roster-compact'),
  'featuredFrame': byKey('roster-featured-frame'),
  'featuredPortrait': byKey('roster-featured-portrait'),
  'featuredName': byKey('roster-featured-name'),
  'firstTile': byKey('roster-tile-artist-0'),
  'fifthTile': byKey('roster-tile-artist-4'),
  'sixthTile': byKey('roster-tile-artist-5'),
  'tenthTile': byKey('roster-tile-artist-9'),
  'select': byKey('roster-select'),
  'miniPlayer': byKey('playback-host-bar'),
};

void main() {
  final geometry = GeometryBaseline(
    'test/visual_baselines/goldens/roster/geometry.json',
  )..register();

  group('Artist Roster golden baselines', () {
    for (final scenario in standardScenarios) {
      testWidgets(scenario.name, (tester) async {
        await pumpBaselineApp(
          tester,
          scenario,
          destination: AppDestination.library,
        );
        expect(byKey('artist-roster'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/roster/${scenario.name}.png'),
        );
      });
    }
  });

  group('Artist Roster pinned geometry', () {
    for (final scenario in geometryScenarios()) {
      testWidgets(scenario.name, (tester) async {
        await pumpBaselineApp(
          tester,
          scenario,
          destination: AppDestination.library,
        );
        expect(tester.takeException(), isNull);
        geometry.check(tester, scenario.name, rosterParts());
      });
    }
  });

  // The a678b95 device regression: after a launch that restored no queue
  // there was no mini-player, the Library was 70dp taller, and the featured
  // picture stretched (182 x 186.8 -> 182 x 256.8dp on the S26 Ultra). The
  // picture, the portraits and the two-row grid must not depend on whether
  // the mini-player is shown.
  group('Artist Roster does not depend on the mini-player', () {
    for (final (size, ratio) in const [
      (s26UltraSize, s26UltraRatio),
      (Size(412, 915), 2.625),
      (Size(360, 780), 3.0),
    ]) {
      for (final text in const [1.0, 1.3]) {
        testWidgets('${size.width.toInt()}x${size.height.toInt()} '
            'text $text', (tester) async {
          Future<Map<String, Size?>> measure(bool withTrack) async {
            await pumpBaselineApp(
              tester,
              BaselineScenario(
                'invariant',
                size: size,
                ratio: ratio,
                textScale: text,
                withTrack: withTrack,
              ),
              destination: AppDestination.library,
            );
            expect(
              byKey('playback-host-bar'),
              withTrack ? findsOneWidget : findsNothing,
            );
            return {
              for (final MapEntry(:key, :value) in rosterParts().entries)
                // The containers take the height that is left; only what
                // is drawn in them must keep its size.
                if (!const {
                  'roster',
                  'compact',
                  'select',
                  'miniPlayer',
                }.contains(key))
                  key: value.evaluate().isEmpty ? null : tester.getSize(value),
            };
          }

          final withMiniPlayer = await measure(true);
          final without = await measure(false);
          for (final key in withMiniPlayer.keys) {
            final a = withMiniPlayer[key], b = without[key];
            expect(b == null, a == null, reason: '$key shown in one state');
            if (a == null || b == null) continue;
            expect(b.width, closeTo(a.width, 0.01), reason: '$key width');
            expect(b.height, closeTo(a.height, 0.01), reason: '$key height');
          }
          // Two rows of five portraits (tiles are staggered vertically):
          // the first five run left to right, the sixth starts row two
          // under the first, and all ten are shown.
          final tiles = [
            for (var i = 0; i < 10; i++)
              tester.getRect(byKey('roster-tile-artist-$i')),
          ];
          for (var i = 1; i < 5; i++) {
            expect(tiles[i].left, greaterThan(tiles[i - 1].right - 0.5));
          }
          expect(tiles[5].left, closeTo(tiles[0].left, 0.5), reason: 'row 2');
          expect(
            tiles[5].top,
            greaterThan(tiles[0].center.dy),
            reason: 'row 2',
          );
          expect(
            byKey('roster-tile-artist-10').hitTestable(),
            findsNothing,
            reason: 'page 1 shows ten portraits',
          );
        });
      }
    }

    testWidgets('the approved S26 Ultra picture: 182 x 186.8dp', (
      tester,
    ) async {
      for (final withTrack in [true, false]) {
        await pumpBaselineApp(
          tester,
          BaselineScenario(
            'approved',
            ratio: s26UltraRatio,
            withTrack: withTrack,
          ),
          destination: AppDestination.library,
        );
        final frame = tester.getSize(byKey('roster-featured-frame'));
        expect(frame.width, closeTo(182, 0.5), reason: 'track: $withTrack');
        expect(frame.height, closeTo(186.8, 0.5), reason: 'track: $withTrack');
      }
    });
  });
}
