import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_moment_feed_copy.dart';
import 'package:sonus_next/features/charts/presentation/news/sonus_news_story.dart';

import 'package:sonus_next/features/charts/application/models/chart_moment_feed_item.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/formatters/chart_moment_feed_copy_formatter.dart';

void main() {
  const formatter = ChartMomentFeedCopyFormatter();

  final weekStart = DateTime.utc(2026, 9, 27);
  final weekEnd = DateTime.utc(2026, 10, 4);

  ChartEntitySnapshot song({
    String id = 'song-a',
    String title = 'Song A',
    String artistId = 'artist-a',
    String artistName = 'Artist A',
  }) {
    return ChartEntitySnapshot(
      entityId: id,
      title: title,
      artistId: artistId,
      artistName: artistName,
      albumTitle: 'Album A',
    );
  }

  ChartMomentEvent event({
    required String id,
    required ChartMomentEventType type,
    required ChartEntitySnapshot entity,
    ChartMomentScope scope = ChartMomentScope.finalized,
    ChartType chartType = ChartType.songs,
    int? previousRank,
    int? currentRank,
    int? previousPeakRank,
    int? currentPeakRank,
    int? threshold,
    int? milestoneValue,
    ChartEntitySnapshot? relatedEntity,
  }) {
    final at = DateTime.utc(2026, 10, 4, 1);

    return ChartMomentEvent(
      id: id,
      deduplicationKey: id,
      sourceId: 'source-$id',
      chartType: chartType,
      scope: scope,
      eventType: type,
      entity: entity,
      relatedEntity: relatedEntity,
      weekStartUtc: weekStart,
      weekEndUtc: weekEnd,
      occurredAt: at,
      createdAt: at,
      previousRank: previousRank,
      currentRank: currentRank,
      previousPeakRank: previousPeakRank,
      currentPeakRank: currentPeakRank,
      threshold: threshold,
      milestoneValue: milestoneValue,
    );
  }

  ChartMomentFeedItem item({
    required ChartMomentEvent dominant,
    List<ChartMomentEvent>? events,
  }) {
    final allEvents = events ?? [dominant];

    return ChartMomentFeedItem(
      id: 'feed-${dominant.id}',
      subjectType: ChartMomentFeedSubjectType.entity,
      chartType: dominant.chartType,
      scope: dominant.scope,
      weekStartUtc: dominant.weekStartUtc,
      weekEndUtc: dominant.weekEndUtc,
      occurredAt: dominant.occurredAt,
      entity: dominant.entity,
      relatedEntity: dominant.relatedEntity,
      artistId: dominant.entity.artistId,
      events: allEvents,
      dominantEventType: dominant.eventType,
    );
  }

  test('LIVE #1 wording stays provisional', () {
    final dominant = event(
      id: 'live-number-one',
      type: ChartMomentEventType.firstNumberOne,
      entity: song(),
      scope: ChartMomentScope.live,
      currentRank: 1,
    );

    final copy = formatter.format(item(dominant: dominant));

    expect(copy.headline, 'Song A rises to #1');
    expect(copy.body, 'Song A reaches #1 on this week’s Sonus Hot 100.');
  });

  test('FINAL #1 wording is official', () {
    final dominant = event(
      id: 'final-number-one',
      type: ChartMomentEventType.firstNumberOne,
      entity: song(),
      currentRank: 1,
    );

    final copy = formatter.format(item(dominant: dominant));

    expect(copy.headline, 'Song A earns its first #1');
    expect(copy.body, 'Song A is officially #1 on the weekly Sonus Hot 100.');
  });

  test('LIVE new peak wording stays provisional', () {
    final dominant = event(
      id: 'live-peak',
      type: ChartMomentEventType.newPeak,
      entity: song(),
      scope: ChartMomentScope.live,
      currentRank: 3,
      currentPeakRank: 3,
    );

    final copy = formatter.format(item(dominant: dominant));

    expect(copy.headline, 'Song A reaches a new peak of #3');
    expect(copy.body, 'Song A rises to #3 on this week’s Sonus Hot 100.');
  });

  test('FINAL new peak wording is official', () {
    final dominant = event(
      id: 'final-peak',
      type: ChartMomentEventType.newPeak,
      entity: song(),
      currentRank: 3,
      currentPeakRank: 3,
    );

    final copy = formatter.format(item(dominant: dominant));

    expect(copy.headline, 'Song A reaches a new peak of #3');
    expect(copy.body, 'Song A earns a new weekly peak of #3.');
  });

  test('new peak includes related artist career-best fact', () {
    final entity = song();

    final dominant = event(
      id: 'peak',
      type: ChartMomentEventType.newPeak,
      entity: entity,
      currentRank: 3,
      currentPeakRank: 3,
    );

    final careerBest = event(
      id: 'career-best',
      type: ChartMomentEventType.artistHighestChartingSong,
      entity: entity,
      currentRank: 3,
      currentPeakRank: 3,
    );

    final copy = formatter.format(
      item(dominant: dominant, events: [dominant, careerBest]),
    );

    expect(copy.headline, 'Song A reaches a new peak of #3');
    expect(
      copy.body,
      'Song A also becomes Artist A’s highest-charting song at #3.',
    );
  });

  test('artist return to number one includes gap weeks', () {
    final dominant = event(
      id: 'artist-return',
      type: ChartMomentEventType.artistReturnsToNumberOneSong,
      entity: song(),
      currentRank: 1,
      threshold: 1,
      milestoneValue: 6,
    );

    final copy = formatter.format(item(dominant: dominant));

    expect(copy.headline, 'Artist A returns to #1');
    expect(
      copy.body,
      'Artist A returns to the top of the weekly chart after 6 weeks.',
    );
  });

  test('simultaneous threshold wording uses occupancy count', () {
    final dominant = event(
      id: 'simultaneous',
      type: ChartMomentEventType.artistSimultaneousThresholdSongs,
      entity: song(),
      threshold: 10,
      milestoneValue: 2,
    );

    final copy = formatter.format(item(dominant: dominant));

    expect(copy.headline, 'Artist A lands 2 songs in the Top 10');
    expect(
      copy.body,
      'Artist A has 2 songs inside the Top 10 at the same time.',
    );
  });

  test('nth artist threshold wording uses ordinals', () {
    final dominant = event(
      id: 'nth-threshold',
      type: ChartMomentEventType.artistNthThresholdSong,
      entity: song(),
      threshold: 10,
      milestoneValue: 3,
    );

    final copy = formatter.format(item(dominant: dominant));

    expect(copy.headline, 'Artist A earns a 3rd Top 10 song');
    expect(
      copy.body,
      'Song A becomes Artist A’s 3rd song to reach the Top 10.',
    );
  });

  test('ordinal helper handles teen suffixes through generated copy', () {
    final dominant = event(
      id: 'eleventh-threshold',
      type: ChartMomentEventType.artistNthThresholdSong,
      entity: song(),
      threshold: 100,
      milestoneValue: 11,
    );

    final copy = formatter.format(item(dominant: dominant));

    expect(copy.headline, 'Artist A earns a 11th Top 100 song');
  });

  test('rank rise wording includes exact movement distance', () {
    final dominant = event(
      id: 'rise',
      type: ChartMomentEventType.rankRise,
      entity: song(),
      previousRank: 15,
      currentRank: 3,
    );

    final copy = formatter.format(item(dominant: dominant));

    expect(copy.headline, 'Song A rises to #3');
    expect(copy.body, 'Song A climbs 12 spots.');
  });

  // Moments come from weekly charts. Since the main Hot 100 became an
  // all-time leaderboard, no Moment may read as an all-time achievement.
  test('an all-time peak at #2 is not called the Top 2', () {
    final copy = formatter.format(
      item(
        dominant: event(
          id: 'peak-2',
          type: ChartMomentEventType.newPeak,
          entity: song(),
          scope: ChartMomentScope.allTime,
          previousRank: 4,
          currentRank: 2,
          currentPeakRank: 2,
          threshold: 2,
        ),
      ),
    );

    expect(copy.headline, endsWith('rises to #2 all-time'));
    expect(copy.headline, isNot(contains('Top 2')));
  });

  test('every Moment names the chart it came from: weekly or all-time', () {
    for (final scope in ChartMomentScope.values) {
      for (final type in ChartMomentEventType.values) {
        for (final values in [(null, null), (3, 2)]) {
          final dominant = event(
            id: '${scope.name}-${type.name}-${values.$1}',
            type: type,
            entity: song(),
            scope: scope,
            previousRank: values.$1,
            currentRank: values.$2,
            currentPeakRank: values.$2,
            threshold: values.$1 == null ? null : 10,
            milestoneValue: values.$1 == null ? null : 2,
          );
          final copy = formatter.format(item(dominant: dominant));
          final text = '${copy.headline} ${copy.body}';

          for (final mention in RegExp(
            r'(\S+ )?Sonus Hot 100',
          ).allMatches(text)) {
            expect(
              mention.group(1),
              scope == ChartMomentScope.allTime
                  ? 'all-time '
                  : anyOf('weekly ', 'week’s '),
              reason: '${scope.name} ${type.name}: $text',
            );
          }
        }
      }
    }
  });

  group('all-time copy adopted from the legacy editorial desk', () {
    ChartMomentFeedCopy allTime(
      ChartMomentEventType type, {
      int? previousRank,
      int? currentRank,
      int? threshold,
    }) => formatter.format(
      item(
        dominant: event(
          id: 'all-time-${type.name}-$threshold-$previousRank',
          type: type,
          entity: song(),
          scope: ChartMomentScope.allTime,
          previousRank: previousRank,
          currentRank: currentRank,
          threshold: threshold,
        ),
      ),
    );

    test('headlines carry the "Title by Artist" byline', () {
      expect(
        allTime(ChartMomentEventType.firstNumberOne, currentRank: 1).headline,
        'Song A by Artist A takes #1 all-time',
      );
      expect(
        allTime(ChartMomentEventType.debut, currentRank: 7).headline,
        'Song A by Artist A debuts at #7 all-time',
      );
    });

    test('breakthrough verbs scale with the zone', () {
      String zone(int threshold) => allTime(
        ChartMomentEventType.newPeak,
        currentRank: threshold,
        threshold: threshold,
      ).headline;

      expect(zone(10), 'Song A by Artist A breaks into the all-time Top 10');
      expect(zone(25), 'Song A by Artist A enters the all-time Top 25');
      expect(zone(50), 'Song A by Artist A reaches the all-time Top 50');
      expect(zone(5), 'Song A by Artist A climbs into the all-time Top 5');
      expect(zone(2), 'Song A by Artist A rises to #2 all-time');
    });

    test('climb verbs scale with the move', () {
      expect(
        allTime(
          ChartMomentEventType.rankRise,
          previousRank: 60,
          currentRank: 20,
        ).headline,
        'Song A by Artist A surges 40 places all-time',
      );
      expect(
        allTime(
          ChartMomentEventType.rankRise,
          previousRank: 40,
          currentRank: 20,
        ).headline,
        'Song A by Artist A jumps 20 places all-time',
      );
    });

    test('decks: a new leader, a fresh entry, the highest position so far', () {
      expect(
        allTime(ChartMomentEventType.firstNumberOne, currentRank: 1).body,
        startsWith('A new leader takes over the all-time Sonus Hot 100'),
      );
      expect(
        allTime(ChartMomentEventType.debut, currentRank: 7).body,
        startsWith('A fresh entry'),
      );
      expect(
        allTime(
          ChartMomentEventType.newPeak,
          currentRank: 9,
          threshold: 10,
        ).body,
        endsWith('its highest position so far.'),
      );
    });

    test('no chart-cycle or weekly-reset wording reaches all-time stories', () {
      for (final type in ChartMomentEventType.values) {
        final copy = allTime(
          type,
          previousRank: 40,
          currentRank: 3,
          threshold: 3,
        );
        final text = '${copy.headline} ${copy.body}'.toLowerCase();
        for (final banned in [
          'weekly',
          'this week',
          'chart cycle',
          'another day',
          'last charting',
        ]) {
          expect(text, isNot(contains(banned)), reason: '${type.name}: $text');
        }
      }
    });

    test('only Sonus Daily and PulsePop publish; retired desks never do', () {
      expect(SonusNewsEdition.values.map((e) => e.label), [
        'Sonus Daily',
        'PulsePop',
      ]);
    });
  });
}
