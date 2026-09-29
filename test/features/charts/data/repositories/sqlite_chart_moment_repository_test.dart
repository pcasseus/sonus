import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SqliteChartMomentRepository repository;

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    await database.database;

    repository = SqliteChartMomentRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  ChartMomentEvent createEvent({
    required String id,
    required String deduplicationKey,
    required String sourceId,
    required DateTime occurredAt,
    int previousRank = 10,
    int currentRank = 9,
    ChartMomentEventType eventType = ChartMomentEventType.rankRise,
    ChartMomentScope scope = ChartMomentScope.live,
    ChartType chartType = ChartType.songs,
    DateTime? weekStartUtc,
    DateTime? weekEndUtc,
    ChartEntitySnapshot? relatedEntity,
  }) {
    return ChartMomentEvent(
      id: id,
      deduplicationKey: deduplicationKey,
      userId: 'user-1',
      sourceId: sourceId,
      chartType: chartType,
      scope: scope,
      eventType: eventType,
      entity: const ChartEntitySnapshot(
        entityId: 'song-a',
        title: 'Song A',
        artistId: 'artist-a',
        artistName: 'Artist A',
        albumTitle: 'Album A',
      ),
      relatedEntity: relatedEntity,
      weekStartUtc: weekStartUtc ?? DateTime.utc(2026, 9, 27),
      weekEndUtc: weekEndUtc ?? DateTime.utc(2026, 10, 4),
      occurredAt: occurredAt,
      createdAt: DateTime.utc(2026, 9, 28, 18),
      previousRank: previousRank,
      currentRank: currentRank,
      threshold: 10,
      previousPeakRank: 12,
      currentPeakRank: 9,
      qualifiedStreamCount: 7,
      milestoneValue: 100,
    );
  }

  test('round-trips every persisted Moment field', () async {
    final event = createEvent(
      id: 'moment-1',
      deduplicationKey: 'dedupe-1',
      sourceId: 'play-1',
      occurredAt: DateTime.utc(2026, 9, 28, 17),
      relatedEntity: const ChartEntitySnapshot(
        entityId: 'song-b',
        title: 'Song B',
        artistId: 'artist-b',
        artistName: 'Artist B',
        albumTitle: 'Album B',
      ),
    );

    await repository.saveAll([event]);

    final restored = await repository.getById(event.id);

    expect(restored, isNotNull);

    expect(restored!.id, event.id);
    expect(restored.deduplicationKey, event.deduplicationKey);
    expect(restored.userId, event.userId);
    expect(restored.sourceId, event.sourceId);
    expect(restored.chartType, event.chartType);
    expect(restored.scope, event.scope);
    expect(restored.eventType, event.eventType);

    expect(restored.entity.entityId, 'song-a');
    expect(restored.entity.title, 'Song A');
    expect(restored.entity.artistId, 'artist-a');
    expect(restored.entity.artistName, 'Artist A');
    expect(restored.entity.albumTitle, 'Album A');

    expect(restored.relatedEntity, isNotNull);
    expect(restored.relatedEntity!.entityId, 'song-b');
    expect(restored.relatedEntity!.title, 'Song B');
    expect(restored.relatedEntity!.artistId, 'artist-b');
    expect(restored.relatedEntity!.artistName, 'Artist B');
    expect(restored.relatedEntity!.albumTitle, 'Album B');

    expect(restored.weekStartUtc, event.weekStartUtc);
    expect(restored.weekEndUtc, event.weekEndUtc);
    expect(restored.occurredAt, event.occurredAt);
    expect(restored.createdAt, event.createdAt);

    expect(restored.previousRank, 10);
    expect(restored.currentRank, 9);
    expect(restored.threshold, 10);
    expect(restored.previousPeakRank, 12);
    expect(restored.currentPeakRank, 9);
    expect(restored.qualifiedStreamCount, 7);
    expect(restored.milestoneValue, 100);
  });

  test('replaying same dedupe key persists only one event', () async {
    final first = createEvent(
      id: 'moment-1',
      deduplicationKey: 'same-transition',
      sourceId: 'play-1',
      occurredAt: DateTime.utc(2026, 9, 28, 17),
    );

    final replay = createEvent(
      id: 'moment-2',
      deduplicationKey: 'same-transition',
      sourceId: 'play-1',
      occurredAt: DateTime.utc(2026, 9, 28, 17),
    );

    await repository.saveAll([first]);
    await repository.saveAll([replay]);

    final events = await repository.getRecent();

    expect(events, hasLength(1));
    expect(events.single.id, 'moment-1');
    expect(events.single.deduplicationKey, 'same-transition');
  });

  test('duplicate id with different dedupe key still throws', () async {
    final first = createEvent(
      id: 'shared-id',
      deduplicationKey: 'dedupe-a',
      sourceId: 'play-a',
      occurredAt: DateTime.utc(2026, 9, 28, 17),
    );

    final conflicting = createEvent(
      id: 'shared-id',
      deduplicationKey: 'dedupe-b',
      sourceId: 'play-b',
      occurredAt: DateTime.utc(2026, 9, 28, 17, 1),
    );

    await repository.saveAll([first]);

    await expectLater(
      repository.saveAll([conflicting]),
      throwsA(isA<DatabaseException>()),
    );

    final events = await repository.getRecent();

    expect(events, hasLength(1));
    expect(events.single.id, 'shared-id');
    expect(events.single.deduplicationKey, 'dedupe-a');
  });
  test('legitimate reversal persists as a separate event', () async {
    final rise = createEvent(
      id: 'moment-rise',
      deduplicationKey: 'rise-transition',
      sourceId: 'play-rise',
      occurredAt: DateTime.utc(2026, 9, 28, 17),
      previousRank: 2,
      currentRank: 1,
      eventType: ChartMomentEventType.rankRise,
    );

    final fall = createEvent(
      id: 'moment-fall',
      deduplicationKey: 'fall-transition',
      sourceId: 'play-fall',
      occurredAt: DateTime.utc(2026, 9, 28, 17, 1),
      previousRank: 1,
      currentRank: 2,
      eventType: ChartMomentEventType.rankFall,
    );

    await repository.saveAll([rise, fall]);

    final events = await repository.getRecent();

    expect(events, hasLength(2));

    expect(events[0].id, 'moment-fall');
    expect(events[0].eventType, ChartMomentEventType.rankFall);
    expect(events[0].sourceId, 'play-fall');

    expect(events[1].id, 'moment-rise');
    expect(events[1].eventType, ChartMomentEventType.rankRise);
    expect(events[1].sourceId, 'play-rise');
  });

  test('returns events newest first', () async {
    final older = createEvent(
      id: 'older',
      deduplicationKey: 'older-dedupe',
      sourceId: 'older-source',
      occurredAt: DateTime.utc(2026, 9, 28, 15),
    );

    final newer = createEvent(
      id: 'newer',
      deduplicationKey: 'newer-dedupe',
      sourceId: 'newer-source',
      occurredAt: DateTime.utc(2026, 9, 28, 18),
    );

    await repository.saveAll([older, newer]);

    final events = await repository.getRecent();

    expect(events.map((event) => event.id).toList(), ['newer', 'older']);
  });

  test('recent limit is respected', () async {
    final first = createEvent(
      id: 'first',
      deduplicationKey: 'first-dedupe',
      sourceId: 'source-1',
      occurredAt: DateTime.utc(2026, 9, 28, 15),
    );

    final second = createEvent(
      id: 'second',
      deduplicationKey: 'second-dedupe',
      sourceId: 'source-2',
      occurredAt: DateTime.utc(2026, 9, 28, 16),
    );

    final third = createEvent(
      id: 'third',
      deduplicationKey: 'third-dedupe',
      sourceId: 'source-3',
      occurredAt: DateTime.utc(2026, 9, 28, 17),
    );

    await repository.saveAll([first, second, third]);

    final events = await repository.getRecent(limit: 2);

    expect(events, hasLength(2));
    expect(events.map((event) => event.id).toList(), ['third', 'second']);
  });

  test(
    'replaces only finalized Moments for matching chart type and week',
    () async {
      final weekStart = DateTime.utc(2026, 9, 27);
      final weekEnd = DateTime.utc(2026, 10, 4);

      final obsoleteFinal = createEvent(
        id: 'obsolete-final',
        deduplicationKey: 'obsolete-final-dedupe',
        sourceId: 'chart-songs-week',
        occurredAt: weekEnd,
        scope: ChartMomentScope.finalized,
        chartType: ChartType.songs,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
      );

      final liveSameWeek = createEvent(
        id: 'live-same-week',
        deduplicationKey: 'live-same-week-dedupe',
        sourceId: 'play-live',
        occurredAt: DateTime.utc(2026, 9, 30),
        scope: ChartMomentScope.live,
        chartType: ChartType.songs,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
      );

      final otherTypeFinal = createEvent(
        id: 'album-final',
        deduplicationKey: 'album-final-dedupe',
        sourceId: 'chart-albums-week',
        occurredAt: weekEnd,
        scope: ChartMomentScope.finalized,
        chartType: ChartType.albums,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
      );

      final otherWeekFinal = createEvent(
        id: 'other-week-final',
        deduplicationKey: 'other-week-final-dedupe',
        sourceId: 'chart-songs-other-week',
        occurredAt: DateTime.utc(2026, 10, 11),
        scope: ChartMomentScope.finalized,
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 10, 4),
        weekEndUtc: DateTime.utc(2026, 10, 11),
      );

      await repository.saveAll([
        obsoleteFinal,
        liveSameWeek,
        otherTypeFinal,
        otherWeekFinal,
      ]);

      final replacement = createEvent(
        id: 'replacement-final',
        deduplicationKey: 'replacement-final-dedupe',
        sourceId: 'chart-songs-week',
        occurredAt: weekEnd,
        scope: ChartMomentScope.finalized,
        chartType: ChartType.songs,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
        previousRank: 14,
        currentRank: 3,
        eventType: ChartMomentEventType.newPeak,
      );

      await repository.replaceFinalizedForWeek(
        chartType: ChartType.songs,
        weekStartUtc: weekStart,
        events: [replacement],
      );

      final events = await repository.getRecent();
      final ids = events.map((event) => event.id).toSet();

      expect(ids, contains('replacement-final'));

      expect(ids, isNot(contains('obsolete-final')));

      expect(ids, contains('live-same-week'));
      expect(ids, contains('album-final'));
      expect(ids, contains('other-week-final'));
    },
  );

  test('empty finalized replacement clears only the canonical slice', () async {
    final weekStart = DateTime.utc(2026, 9, 27);
    final weekEnd = DateTime.utc(2026, 10, 4);

    final finalized = createEvent(
      id: 'final-to-clear',
      deduplicationKey: 'final-to-clear-dedupe',
      sourceId: 'chart-songs-week',
      occurredAt: weekEnd,
      scope: ChartMomentScope.finalized,
      weekStartUtc: weekStart,
      weekEndUtc: weekEnd,
    );

    final live = createEvent(
      id: 'live-to-preserve',
      deduplicationKey: 'live-to-preserve-dedupe',
      sourceId: 'play-live',
      occurredAt: DateTime.utc(2026, 9, 30),
      scope: ChartMomentScope.live,
      weekStartUtc: weekStart,
      weekEndUtc: weekEnd,
    );

    await repository.saveAll([finalized, live]);

    await repository.replaceFinalizedForWeek(
      chartType: ChartType.songs,
      weekStartUtc: weekStart,
      events: const [],
    );

    final events = await repository.getRecent();

    expect(events.map((event) => event.id).toList(), ['live-to-preserve']);
  });

  test('repeating identical finalized replacement is idempotent', () async {
    final weekStart = DateTime.utc(2026, 9, 27);
    final weekEnd = DateTime.utc(2026, 10, 4);

    final event = createEvent(
      id: 'canonical-final',
      deduplicationKey: 'canonical-final-dedupe',
      sourceId: 'chart-songs-week',
      occurredAt: weekEnd,
      scope: ChartMomentScope.finalized,
      weekStartUtc: weekStart,
      weekEndUtc: weekEnd,
      eventType: ChartMomentEventType.newPeak,
    );

    await repository.replaceFinalizedForWeek(
      chartType: ChartType.songs,
      weekStartUtc: weekStart,
      events: [event],
    );

    await repository.replaceFinalizedForWeek(
      chartType: ChartType.songs,
      weekStartUtc: weekStart,
      events: [event],
    );

    final events = await repository.getRecent();

    expect(events, hasLength(1));
    expect(events.single.id, 'canonical-final');
    expect(events.single.scope, ChartMomentScope.finalized);
  });

  test(
    'invalid finalized replacement does not delete existing facts',
    () async {
      final weekStart = DateTime.utc(2026, 9, 27);
      final weekEnd = DateTime.utc(2026, 10, 4);

      final existing = createEvent(
        id: 'existing-final',
        deduplicationKey: 'existing-final-dedupe',
        sourceId: 'chart-songs-week',
        occurredAt: weekEnd,
        scope: ChartMomentScope.finalized,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
      );

      final invalidLive = createEvent(
        id: 'invalid-live',
        deduplicationKey: 'invalid-live-dedupe',
        sourceId: 'play-live',
        occurredAt: weekEnd,
        scope: ChartMomentScope.live,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
      );

      await repository.saveAll([existing]);

      await expectLater(
        repository.replaceFinalizedForWeek(
          chartType: ChartType.songs,
          weekStartUtc: weekStart,
          events: [invalidLive],
        ),
        throwsArgumentError,
      );

      final events = await repository.getRecent();

      expect(events, hasLength(1));
      expect(events.single.id, 'existing-final');
    },
  );
  test('missing id returns null', () async {
    final restored = await repository.getById('missing');

    expect(restored, isNull);
  });
}
