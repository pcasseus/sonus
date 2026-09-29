import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/application/models/chart_moment_feed_item.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';

void main() {
  const aggregator = ChartMomentFeedAggregator();

  final weekStart = DateTime.utc(2026, 9, 27);
  final weekEnd = DateTime.utc(2026, 10, 4);

  ChartEntitySnapshot song(
    String id, {
    String artistId = 'artist-a',
    String artistName = 'Artist A',
  }) {
    return ChartEntitySnapshot(
      entityId: id,
      title: 'Song $id',
      artistId: artistId,
      artistName: artistName,
      albumTitle: 'Album A',
    );
  }

  ChartEntitySnapshot album(
    String id, {
    String artistId = 'artist-a',
    String artistName = 'Artist A',
  }) {
    return ChartEntitySnapshot(
      entityId: id,
      title: 'Album $id',
      artistId: artistId,
      artistName: artistName,
    );
  }

  ChartMomentEvent event({
    required String id,
    required ChartMomentEventType type,
    required ChartEntitySnapshot entity,
    ChartMomentScope scope = ChartMomentScope.finalized,
    ChartType chartType = ChartType.songs,
    String? sourceId = 'snapshot-1',
    DateTime? occurredAt,
    int? previousRank,
    int? currentRank,
    int? threshold,
    int? milestoneValue,
    ChartEntitySnapshot? relatedEntity,
  }) {
    final at = occurredAt ?? DateTime.utc(2026, 10, 4, 1);

    return ChartMomentEvent(
      id: id,
      deduplicationKey: id,
      sourceId: sourceId,
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
      threshold: threshold,
      milestoneValue: milestoneValue,
    );
  }

  test('FINAL facts for one entity and week collapse into one story', () {
    final entity = song('song-a');

    final items = aggregator.aggregate([
      event(
        id: 'rise',
        type: ChartMomentEventType.rankRise,
        entity: entity,
        previousRank: 15,
        currentRank: 3,
      ),
      event(
        id: 'peak',
        type: ChartMomentEventType.newPeak,
        entity: entity,
        previousRank: 15,
        currentRank: 3,
      ),
      event(
        id: 'top-10',
        type: ChartMomentEventType.firstThresholdEntry,
        entity: entity,
        currentRank: 3,
        threshold: 10,
      ),
    ]);

    expect(items, hasLength(1));

    final item = items.single;

    expect(item.subjectType, ChartMomentFeedSubjectType.entity);
    expect(item.events, hasLength(3));
    expect(item.dominantEventType, ChartMomentEventType.newPeak);
    expect(item.isFinalized, isTrue);
  });

  test('LIVE facts from one source collapse into one transition story', () {
    final entity = song('song-a');

    final items = aggregator.aggregate([
      event(
        id: 'rise',
        type: ChartMomentEventType.rankRise,
        entity: entity,
        scope: ChartMomentScope.live,
        sourceId: 'play-1',
        previousRank: 15,
        currentRank: 3,
      ),
      event(
        id: 'peak',
        type: ChartMomentEventType.newPeak,
        entity: entity,
        scope: ChartMomentScope.live,
        sourceId: 'play-1',
        currentRank: 3,
      ),
      event(
        id: 'threshold',
        type: ChartMomentEventType.firstThresholdEntry,
        entity: entity,
        scope: ChartMomentScope.live,
        sourceId: 'play-1',
        currentRank: 3,
        threshold: 10,
      ),
    ]);

    expect(items, hasLength(1));
    expect(items.single.events, hasLength(3));
    expect(items.single.isLive, isTrue);
  });

  test('separate LIVE sources remain separate stories for reversals', () {
    final entity = song('song-a');

    final items = aggregator.aggregate([
      event(
        id: 'rise',
        type: ChartMomentEventType.rankRise,
        entity: entity,
        scope: ChartMomentScope.live,
        sourceId: 'play-1',
        occurredAt: DateTime.utc(2026, 9, 28, 10),
        previousRank: 15,
        currentRank: 3,
      ),
      event(
        id: 'fall',
        type: ChartMomentEventType.rankFall,
        entity: entity,
        scope: ChartMomentScope.live,
        sourceId: 'play-2',
        occurredAt: DateTime.utc(2026, 9, 28, 11),
        previousRank: 3,
        currentRank: 7,
      ),
    ]);

    expect(items, hasLength(2));
    expect(items.first.dominantEventType, ChartMomentEventType.rankFall);
    expect(items.last.dominantEventType, ChartMomentEventType.rankRise);
  });

  test('LIVE and FINAL facts never merge', () {
    final entity = song('song-a');

    final items = aggregator.aggregate([
      event(
        id: 'live',
        type: ChartMomentEventType.newPeak,
        entity: entity,
        scope: ChartMomentScope.live,
        sourceId: 'play-1',
      ),
      event(
        id: 'final',
        type: ChartMomentEventType.newPeak,
        entity: entity,
        scope: ChartMomentScope.finalized,
      ),
    ]);

    expect(items, hasLength(2));
    expect(items.map((item) => item.scope).toSet(), {
      ChartMomentScope.live,
      ChartMomentScope.finalized,
    });
  });

  test('simultaneous threshold facts aggregate at artist level', () {
    final first = song('song-a');
    final second = song('song-b');

    final items = aggregator.aggregate([
      event(
        id: 'top-100',
        type: ChartMomentEventType.artistSimultaneousThresholdSongs,
        entity: first,
        relatedEntity: second,
        threshold: 100,
        milestoneValue: 2,
      ),
      event(
        id: 'top-50',
        type: ChartMomentEventType.artistSimultaneousThresholdSongs,
        entity: first,
        relatedEntity: second,
        threshold: 50,
        milestoneValue: 2,
      ),
    ]);

    expect(items, hasLength(1));

    final item = items.single;

    expect(item.subjectType, ChartMomentFeedSubjectType.artist);
    expect(item.artistId, 'artist-a');
    expect(item.events, hasLength(2));
  });

  test('ordinary artist accomplishment facts stay with entity story', () {
    final entity = song('song-a');

    final items = aggregator.aggregate([
      event(
        id: 'number-one',
        type: ChartMomentEventType.firstNumberOne,
        entity: entity,
        threshold: 1,
        currentRank: 1,
      ),
      event(
        id: 'artist-number-one',
        type: ChartMomentEventType.artistNthNumberOneSong,
        entity: entity,
        threshold: 1,
        milestoneValue: 3,
      ),
    ]);

    expect(items, hasLength(1));
    expect(items.single.subjectType, ChartMomentFeedSubjectType.entity);
    expect(items.single.dominantEventType, ChartMomentEventType.firstNumberOne);
  });

  test('songs and albums never merge', () {
    final items = aggregator.aggregate([
      event(
        id: 'song',
        type: ChartMomentEventType.newPeak,
        entity: song('shared'),
      ),
      event(
        id: 'album',
        type: ChartMomentEventType.newPeak,
        entity: album('shared'),
        chartType: ChartType.albums,
      ),
    ]);

    expect(items, hasLength(2));
  });

  test('different FINAL entities remain separate stories', () {
    final items = aggregator.aggregate([
      event(
        id: 'a',
        type: ChartMomentEventType.newPeak,
        entity: song('song-a'),
      ),
      event(
        id: 'b',
        type: ChartMomentEventType.newPeak,
        entity: song('song-b'),
      ),
    ]);

    expect(items, hasLength(2));
  });

  test('aggregation identity and ordering are deterministic', () {
    final entity = song('song-a');

    final older = event(
      id: 'older',
      type: ChartMomentEventType.rankRise,
      entity: entity,
      scope: ChartMomentScope.live,
      sourceId: 'play-old',
      occurredAt: DateTime.utc(2026, 9, 28, 10),
    );

    final newer = event(
      id: 'newer',
      type: ChartMomentEventType.rankRise,
      entity: entity,
      scope: ChartMomentScope.live,
      sourceId: 'play-new',
      occurredAt: DateTime.utc(2026, 9, 28, 11),
    );

    final first = aggregator.aggregate([older, newer]);
    final second = aggregator.aggregate([newer, older]);

    expect(
      first.map((item) => item.id).toList(),
      second.map((item) => item.id).toList(),
    );

    expect(first.first.occurredAt, newer.occurredAt);
  });
}
