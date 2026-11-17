// App Update 1.3 (REF-1.3-06): rank and chart-zone labelling of Moments.
//
// The report: a song described as #14 on the weekly Hot 100 also appears
// at #114, in Bubbling Under, elsewhere. Stored data shows these are two
// different charts (the weekly chart ranks one week's plays; the all-time
// chart ranks lifetime plays), so both numbers can be right. These tests
// pin that every story quotes the overall position (1-200) of its own
// chart, names the zone that position is in, and never shows a
// zone-relative number such as "#14" for #114.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/models/chart_moment_feed_item.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';

import 'moment_editorial_test.dart' show FakeLookups;

const _song = ChartEntitySnapshot(
  entityId: 'song-u',
  title: 'Where Are U Now',
  artistId: 'artist-a',
  artistName: 'Name artist-a',
  albumTitle: 'Album U',
);

final _week = DateTime.utc(2026, 11, 8, 5);

ChartMomentEvent _debut({required ChartMomentScope scope, required int rank}) {
  final key = '${scope.name}|debut|${_song.entityId}|$rank';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: scope == ChartMomentScope.allTime
        ? 'play-1'
        : 'chart_songs_${_week.millisecondsSinceEpoch}',
    chartType: ChartType.songs,
    scope: scope,
    eventType: ChartMomentEventType.debut,
    entity: _song,
    weekStartUtc: _week,
    weekEndUtc: _week.add(const Duration(days: 7)),
    occurredAt: scope == ChartMomentScope.allTime
        ? DateTime.utc(2026, 11, 11, 1, 55)
        : _week.add(const Duration(days: 7)),
    createdAt: DateTime.utc(2026, 11, 15),
    currentRank: rank,
    currentPeakRank: rank,
    qualifiedStreamCount: 2,
  );
}

ChartMomentFeedItem _item(ChartMomentEvent event) =>
    const ChartMomentFeedAggregator().aggregate([event]).single;

final _lookups = FakeLookups(artists: {'artist-a': 'Name artist-a'});

MomentFacts _facts(ChartMomentScope scope, int rank, {bool refined = true}) =>
    MomentFacts.of(
      _item(_debut(scope: scope, rank: rank)),
      _lookups,
      refined: refined,
    );

/// "#14" but not "#114" or "#140".
Matcher _quotes(int rank) => matches(RegExp('(^|[^0-9])#$rank(?![0-9])'));

void main() {
  group('the stored position is quoted, never a zone-relative one', () {
    test('weekly #14 is the weekly Hot 100, #14', () {
      final facts = _facts(ChartMomentScope.finalized, 14);
      expect(facts.rank, 14);
      expect(facts.bubblingUnder, isFalse);
      expect(facts.chart, 'the weekly Sonus Hot 100');
      expect(facts.chartName, 'Sonus Hot 100');
    });

    test('all-time #114 is Bubbling Under, #114', () {
      final facts = _facts(ChartMomentScope.allTime, 114);
      expect(facts.rank, 114);
      expect(facts.bubblingUnder, isTrue);
      expect(facts.chart, 'Sonus Bubbling Under');
      expect(facts.chartName, 'Sonus Bubbling Under');
    });

    test('weekly #114 is the weekly Bubbling Under, never the Hot 100', () {
      final facts = _facts(ChartMomentScope.finalized, 114);
      expect(facts.rank, 114);
      expect(facts.chart, 'the weekly Sonus Bubbling Under');
      expect(facts.scopedChart, 'the weekly Sonus Bubbling Under');
    });

    test('the zone boundary: #100 is the Hot 100, #101 Bubbling Under', () {
      for (final scope in [
        ChartMomentScope.allTime,
        ChartMomentScope.finalized,
      ]) {
        expect(_facts(scope, 100).bubblingUnder, isFalse, reason: '$scope');
        expect(_facts(scope, 101).bubblingUnder, isTrue, reason: '$scope');
        expect(_facts(scope, 101).rank, 101, reason: '$scope');
        expect(_facts(scope, 200).rank, 200, reason: '$scope');
      }
    });
  });

  group('headlines', () {
    final desk = MomentEditorialDesk(
      lookups: _lookups,
      rules: ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 1, 1)),
    );
    String headline(ChartMomentScope scope, int rank) =>
        desk.compose([_item(_debut(scope: scope, rank: rank))]).single.headline;

    test('an all-time Bubbling Under debut quotes #114 and its zone', () {
      final text = headline(ChartMomentScope.allTime, 114);
      expect(text, _quotes(114));
      expect(text, isNot(_quotes(14)));
      expect(text, isNot(contains('Hot 100')));
    });

    test('a weekly Hot 100 debut quotes #14', () {
      final text = headline(ChartMomentScope.finalized, 14);
      expect(text, _quotes(14));
      expect(text, isNot(_quotes(114)));
      expect(text, isNot(contains('Bubbling Under')));
    });

    test('a weekly Bubbling Under debut never reads as the Hot 100', () {
      final text = headline(ChartMomentScope.finalized, 114);
      expect(text, isNot(_quotes(14)));
      expect(text, isNot(contains('Hot 100')));
    });
  });
}
