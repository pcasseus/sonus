// SN-50 device feedback: Moments documents every recorded chart
// achievement from the device polish's start, without the three-a-day cap
// on smaller stories. Earlier days keep exactly what they published.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';

import 'moment_editorial_test.dart'
    show FakeLookups, event, items, release, song;

final _start = DateTime.utc(2026, 11, 2);
final _after = DateTime.utc(2026, 11, 3, 12);
final _before = DateTime.utc(2026, 10, 27, 12);
final _polished = ChartMomentRules(devicePolishFromUtc: _start);

MomentEditorialDesk _desk(ChartMomentRules rules) => MomentEditorialDesk(
  lookups: FakeLookups(artists: const {'artist-a': 'Name artist-a'}),
  rules: rules,
);

List<ChartMomentEvent> _debuts(
  int count, {
  required DateTime at,
  ChartMomentScope scope = ChartMomentScope.allTime,
  ChartType chartType = ChartType.songs,
  int firstRank = 60,
}) => [
  for (var i = 0; i < count; i++)
    event(
      ChartMomentEventType.debut,
      entity: chartType == ChartType.songs ? song('d$i') : release('d$i'),
      chartType: chartType,
      scope: scope,
      source: 'play-$i',
      at: at.add(Duration(minutes: i)),
      rank: firstRank + i,
    ),
];

void main() {
  group('complete coverage', () {
    test('more than three smaller debuts on one day are all told', () {
      final stories = _desk(_polished).compose(items(_debuts(12, at: _after)));
      expect(stories, hasLength(12));
      expect(stories.map((s) => s.item.entity.entityId).toSet(), hasLength(12));
    });

    test('days before the start keep the daily cap', () {
      final before = _desk(
        ChartMomentRules.legacy,
      ).compose(items(_debuts(12, at: _before)));
      final polishedRules = _desk(
        _polished,
      ).compose(items(_debuts(12, at: _before)));
      expect(before, hasLength(3));
      expect(
        polishedRules.map((s) => s.headline),
        before.map((s) => s.headline),
      );
    });

    test('lower Hot 100 and Bubbling Under debuts name their chart and '
        'position', () {
      final stories = _desk(_polished).compose(
        items([
          ..._debuts(1, at: _after, firstRank: 97),
          event(
            ChartMomentEventType.debut,
            entity: song('bu'),
            source: 'bu',
            at: _after.add(const Duration(hours: 1)),
            rank: 187,
          ),
        ]),
      );
      final hot = stories.firstWhere((s) => s.item.entity.entityId == 'd0');
      final bu = stories.firstWhere((s) => s.item.entity.entityId == 'bu');
      expect(hot.family, MomentFamily.songDebut);
      expect(hot.rank, 97);
      expect(bu.family, MomentFamily.songBubblingUnderDebut);
      expect(bu.rank, 187);
      expect(bu.kicker.toUpperCase(), contains('BUBBLING UNDER'));
    });

    test('weekly debuts below the Top 10 are told, on the weekly chart', () {
      final stories = _desk(_polished).compose(
        items([
          ..._debuts(5, at: _after, scope: ChartMomentScope.finalized),
          event(
            ChartMomentEventType.debut,
            entity: song('wbu'),
            scope: ChartMomentScope.finalized,
            source: 'week',
            at: _after,
            rank: 150,
          ),
        ]),
      );
      expect(stories, hasLength(6));
      final bu = stories.firstWhere((s) => s.item.entity.entityId == 'wbu');
      expect(bu.headline, isNot(contains('Hot 100')));
      expect(bu.headline, contains('#150'));
    });

    test('Albums & EPs debuts at any position', () {
      final stories = _desk(_polished).compose(
        items([
          ..._debuts(
            4,
            at: _after,
            chartType: ChartType.albums,
            firstRank: 120,
          ),
        ]),
      );
      expect(stories, hasLength(4));
      expect(
        stories.every((s) => s.family == MomentFamily.releaseDebut),
        isTrue,
      );
    });

    test('weekly new peaks and re-entries at any position', () {
      final stories = _desk(_polished).compose(
        items([
          event(
            ChartMomentEventType.newPeak,
            entity: song('peak'),
            scope: ChartMomentScope.finalized,
            source: 'week',
            at: _after,
            rank: 44,
            previousRank: 60,
            previousPeak: 52,
          ),
          event(
            ChartMomentEventType.reentry,
            entity: song('back'),
            scope: ChartMomentScope.finalized,
            source: 'week',
            at: _after,
            rank: 81,
          ),
        ]),
      );
      final families = {
        for (final s in stories) s.item.entity.entityId: s.family,
      };
      expect(families['peak'], MomentFamily.songNewPeak);
      expect(families['back'], MomentFamily.songReentry);
    });

    test('weekly climbs state the exact places; a move into the Hot 100 is '
        'not told as places', () {
      final stories = _desk(_polished).compose(
        items([
          event(
            ChartMomentEventType.rankRise,
            entity: song('up'),
            scope: ChartMomentScope.finalized,
            source: 'week',
            at: _after,
            rank: 31,
            previousRank: 38,
          ),
          event(
            ChartMomentEventType.rankRise,
            entity: song('cross'),
            scope: ChartMomentScope.finalized,
            source: 'week',
            at: _after,
            rank: 92,
            previousRank: 140,
          ),
        ]),
      );
      final up = stories.firstWhere((s) => s.item.entity.entityId == 'up');
      expect(up.headline, contains('7 places'));
      expect(up.climb, 7);
      final cross = stories.firstWhere(
        (s) => s.item.entity.entityId == 'cross',
      );
      expect(cross.family, MomentFamily.songHot100Breakthrough);
      expect(cross.climb, isNull);
      expect(cross.headline, isNot(contains('48 places')));
    });

    test('the same events composed again publish the same stories once', () {
      final events = _debuts(6, at: _after);
      final first = _desk(_polished).compose(items(events));
      final again = _desk(_polished).compose(items([...events, ...events]));
      expect(again.map((s) => s.id), first.map((s) => s.id));
      expect(again.map((s) => s.headline), first.map((s) => s.headline));
    });

    test('a large day composes quickly and completely', () {
      // Every position from #2 to #200 debuts on one day.
      final events = _debuts(199, at: _after, firstRank: 2);
      final watch = Stopwatch()..start();
      final stories = _desk(_polished).compose(items(events));
      watch.stop();
      expect(stories, hasLength(events.length));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
