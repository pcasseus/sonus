import 'package:flutter_test/flutter_test.dart';

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
    expect(copy.body, 'Song A reaches #1 on the live Sonus Hot 100.');
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
    expect(copy.body, 'Song A is officially #1 on the Sonus Hot 100.');
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
    expect(copy.body, 'Song A rises to #3 on the live Sonus Hot 100.');
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
    expect(copy.body, 'Song A earns a new official peak of #3.');
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
    expect(copy.body, 'Artist A returns to the top after 6 weeks.');
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
}
