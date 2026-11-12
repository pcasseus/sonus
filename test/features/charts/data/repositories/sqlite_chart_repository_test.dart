import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_repository.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_week_finalizer.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SqliteChartRepository repository;

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    await database.database;

    repository = SqliteChartRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  ChartEntry createEntry({
    required String entityId,
    required int rank,
    int streams = 10,
    int? previousFinalRank,
    int peakRank = 1,
    int weeksOnChart = 1,
    ChartMovement movement = ChartMovement.newEntry,
  }) {
    return ChartEntry(
      entity: ChartEntitySnapshot(
        entityId: entityId,
        title: 'Title $entityId',
        artistId: 'artist-$entityId',
        artistName: 'Artist $entityId',
        albumTitle: 'Album $entityId',
      ),
      rank: rank,
      qualifiedStreamCount: streams,
      lastQualifiedAt: DateTime.utc(2026, 10, 3, 20),
      previousFinalRank: previousFinalRank,
      peakRank: peakRank,
      peakAchievedAt: DateTime.utc(2026, 9, 28, 12),
      weeksOnChart: weeksOnChart,
      movement: movement,
    );
  }

  ChartSnapshot createSnapshot({
    String id = 'snapshot-week-1',
    int revision = 1,
    bool finalized = true,
    List<ChartEntry>? entries,
  }) {
    return ChartSnapshot(
      id: id,
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
      finalizedAt: finalized ? DateTime.utc(2026, 10, 4) : null,
      revision: revision,
      entries:
          entries ??
          [
            createEntry(entityId: 'song-a', rank: 1, streams: 20, peakRank: 1),
            createEntry(
              entityId: 'song-b',
              rank: 2,
              streams: 15,
              previousFinalRank: 5,
              peakRank: 2,
              weeksOnChart: 3,
              movement: ChartMovement.up,
            ),
          ],
    );
  }

  test('round-trips finalized chart snapshot with entries', () async {
    final snapshot = createSnapshot();

    await repository.replaceSnapshot(snapshot);

    final restored = await repository.getById(snapshot.id);

    expect(restored, isNotNull);
    expect(restored!.id, snapshot.id);
    expect(restored.chartType, ChartType.songs);
    expect(restored.weekStartUtc, snapshot.weekStartUtc);
    expect(restored.weekEndUtc, snapshot.weekEndUtc);
    expect(restored.finalizedAt, snapshot.finalizedAt);
    expect(restored.revision, 1);

    expect(restored.entries, hasLength(2));

    expect(restored.entries[0].entity.entityId, 'song-a');
    expect(restored.entries[0].entity.artistId, 'artist-song-a');
    expect(restored.entries[0].rank, 1);
    expect(restored.entries[0].qualifiedStreamCount, 20);

    expect(restored.entries[1].entity.entityId, 'song-b');
    expect(restored.entries[1].rank, 2);
    expect(restored.entries[1].previousFinalRank, 5);
    expect(restored.entries[1].movement, ChartMovement.up);
  });

  test('REF-19: a week keeps its provenance; unknown stays unknown', () async {
    for (final provenance in [...ChartSnapshotProvenance.values, null]) {
      final snapshot = createSnapshot(
        id: 'week-${provenance?.name ?? 'unknown'}',
      ).withProvenance(provenance);
      await database.transaction(
        (txn) => txn.delete(DatabaseTables.chartSnapshots),
      );
      await repository.replaceSnapshot(snapshot);

      expect((await repository.getById(snapshot.id))!.provenance, provenance);
      final history = await repository.getHistory(ChartType.songs);
      expect(history.single.provenance, provenance);
    }
  });

  test('REF-19: the chart history origin reads back, or null', () async {
    final origin = await repository.chartHistoryOriginUtc();
    expect(origin, isNotNull);
    expect(origin!.isUtc, isTrue);

    await database.transaction(
      (txn) => txn.delete(DatabaseTables.chartHistoryOrigin),
    );
    expect(await repository.chartHistoryOriginUtc(), isNull);
  });

  test('loads snapshot by chart type and week', () async {
    final snapshot = createSnapshot();

    await repository.replaceSnapshot(snapshot);

    final restored = await repository.getForWeek(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
    );

    expect(restored, isNotNull);
    expect(restored!.id, snapshot.id);
  });

  test('history returns finalized snapshots newest first', () async {
    final older = ChartSnapshot(
      id: 'snapshot-old',
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 20),
      weekEndUtc: DateTime.utc(2026, 9, 27),
      finalizedAt: DateTime.utc(2026, 9, 27),
      entries: [createEntry(entityId: 'song-old', rank: 1)],
    );

    final newer = createSnapshot(id: 'snapshot-new');

    await repository.replaceSnapshot(older);
    await repository.replaceSnapshot(newer);

    final history = await repository.getHistory(ChartType.songs);

    expect(history.map((snapshot) => snapshot.id).toList(), [
      'snapshot-new',
      'snapshot-old',
    ]);
  });

  test('history limit is respected', () async {
    final older = ChartSnapshot(
      id: 'snapshot-old',
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 20),
      weekEndUtc: DateTime.utc(2026, 9, 27),
      finalizedAt: DateTime.utc(2026, 9, 27),
      entries: [createEntry(entityId: 'song-old', rank: 1)],
    );

    final newer = createSnapshot(id: 'snapshot-new');

    await repository.replaceSnapshot(older);
    await repository.replaceSnapshot(newer);

    final history = await repository.getHistory(ChartType.songs, limit: 1);

    expect(history, hasLength(1));
    expect(history.single.id, 'snapshot-new');
  });

  test('higher revision replaces an unfinalized snapshot', () async {
    await repository.replaceSnapshot(
      createSnapshot(
        revision: 1,
        finalized: false,
        entries: [
          createEntry(entityId: 'song-a', rank: 1, streams: 10),
          createEntry(entityId: 'song-b', rank: 2, streams: 8),
        ],
      ),
    );

    await repository.replaceSnapshot(
      createSnapshot(
        revision: 2,
        entries: [createEntry(entityId: 'song-c', rank: 1, streams: 25)],
      ),
    );

    final restored = await repository.getForWeek(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
    );

    expect(restored, isNotNull);
    expect(restored!.revision, 2);
    expect(restored.entries, hasLength(1));
    expect(restored.entries.single.entity.entityId, 'song-c');
    expect(restored.entries.single.qualifiedStreamCount, 25);
  });

  test('older revision cannot overwrite newer snapshot', () async {
    await repository.replaceSnapshot(
      createSnapshot(
        revision: 3,
        finalized: false,
        entries: [createEntry(entityId: 'song-new', rank: 1, streams: 30)],
      ),
    );

    await expectLater(
      repository.replaceSnapshot(
        createSnapshot(
          revision: 2,
          finalized: false,
          entries: [createEntry(entityId: 'song-old', rank: 1, streams: 5)],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error,
          'not the freeze',
          isNot(isA<FinalizedChartWeekFrozen>()),
        ),
      ),
    );

    final restored = await repository.getForWeek(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
    );

    expect(restored, isNotNull);
    expect(restored!.revision, 3);
    expect(restored.entries.single.entity.entityId, 'song-new');
  });

  test(
    'same revision of an unfinalized week can be written idempotently',
    () async {
      final snapshot = createSnapshot(revision: 2, finalized: false);

      await repository.replaceSnapshot(snapshot);
      await repository.replaceSnapshot(snapshot);

      final restored = await repository.getById(snapshot.id);

      expect(restored, isNotNull);
      expect(restored!.revision, 2);
      expect(restored.entries, hasLength(2));
    },
  );

  test('historical text survives without live library entities', () async {
    final snapshot = createSnapshot(
      entries: [
        ChartEntry(
          entity: const ChartEntitySnapshot(
            entityId: 'deleted-song',
            title: 'Gone Song',
            artistName: 'Gone Artist',
            albumTitle: 'Gone Album',
          ),
          rank: 7,
          qualifiedStreamCount: 11,
          lastQualifiedAt: DateTime.utc(2026, 10, 3, 19),
          previousFinalRank: null,
          peakRank: 3,
          peakAchievedAt: DateTime.utc(2026, 9, 29),
          weeksOnChart: 1,
          movement: ChartMovement.newEntry,
        ),
      ],
    );

    await repository.replaceSnapshot(snapshot);

    final restored = await repository.getById(snapshot.id);

    expect(restored, isNotNull);
    expect(restored!.entries.single.entity.entityId, 'deleted-song');
    expect(restored.entries.single.entity.title, 'Gone Song');
    expect(restored.entries.single.entity.artistName, 'Gone Artist');
    expect(restored.entries.single.entity.albumTitle, 'Gone Album');
  });

  group('SN-50 F6: a finalized week and its Moments are written together', () {
    final weekStart = DateTime.utc(2026, 9, 27);

    ChartMomentEvent moment(String id, {String? key, DateTime? week}) {
      return ChartMomentEvent(
        id: id,
        deduplicationKey: key ?? 'key-$id',
        userId: 'user-1',
        sourceId: 'source-$id',
        chartType: ChartType.songs,
        scope: ChartMomentScope.finalized,
        eventType: ChartMomentEventType.rankRise,
        entity: const ChartEntitySnapshot(
          entityId: 'song-a',
          title: 'Title song-a',
          artistId: 'artist-song-a',
          artistName: 'Artist song-a',
          albumTitle: 'Album song-a',
        ),
        weekStartUtc: week ?? weekStart,
        weekEndUtc: DateTime.utc(2026, 10, 4),
        occurredAt: DateTime.utc(2026, 10, 4),
        createdAt: DateTime.utc(2026, 10, 4, 1),
        previousRank: 5,
        currentRank: 1,
      );
    }

    Future<Map<String, List<Map<String, Object?>>>> rows() async {
      final db = await database.database;
      return {
        for (final table in [
          DatabaseTables.chartSnapshots,
          DatabaseTables.chartEntries,
          DatabaseTables.chartMomentEvents,
        ])
          table: await db.query(table, orderBy: 'id'),
      };
    }

    test('both are stored by one call', () async {
      final result = await repository.finalizeWeek(
        snapshot: createSnapshot(),
        moments: [moment('m1'), moment('m2')],
      );

      expect(result.wasAlreadyFinalized, isFalse);
      expect(result.moments, ChartFinalizedMoments.published);
      final stored = await rows();
      expect(stored[DatabaseTables.chartSnapshots], hasLength(1));
      expect(stored[DatabaseTables.chartEntries], hasLength(2));
      expect(stored[DatabaseTables.chartMomentEvents], hasLength(2));
    });

    test('a failure while writing the entries rolls back everything', () async {
      final before = await rows();

      await expectLater(
        repository.finalizeWeek(
          snapshot: createSnapshot(
            entries: [
              createEntry(entityId: 'song-a', rank: 1),
              createEntry(entityId: 'song-b', rank: 1),
            ],
          ),
          moments: [moment('m1')],
        ),
        throwsA(anything),
      );

      expect(await rows(), before);
    });

    test(
      'a failure while publishing the Moments rolls back the snapshot',
      () async {
        final before = await rows();

        // The same id under another deduplication key: the second insert
        // fails after the snapshot and its entries were written.
        await expectLater(
          repository.finalizeWeek(
            snapshot: createSnapshot(),
            moments: [
              moment('m1'),
              moment('m1', key: 'another-key'),
            ],
          ),
          throwsA(anything),
        );

        expect(await rows(), before);
      },
    );

    test('a week already finalized is returned as stored; nothing is '
        'written, Moments included', () async {
      await repository.finalizeWeek(
        snapshot: createSnapshot(),
        moments: [moment('m1')],
      );
      final stored = await rows();

      final again = await repository.finalizeWeek(
        snapshot: createSnapshot(
          id: 'snapshot-other',
          revision: 2,
          entries: [createEntry(entityId: 'song-z', rank: 1)],
        ),
        moments: [moment('m9')],
      );

      expect(again.wasAlreadyFinalized, isTrue);
      expect(again.snapshot.id, 'snapshot-week-1');
      expect(again.snapshot.entries.first.entity.entityId, 'song-a');
      expect(await rows(), stored);
    });

    test('Moments published without a snapshot (the earlier write order) '
        'are kept exactly; only the snapshot is added', () async {
      final db = await database.database;
      await SqliteChartMomentRepository(database).publishFinalizedForWeek(
        chartType: ChartType.songs,
        weekStartUtc: weekStart,
        events: [moment('old-1')],
      );
      final earlier = await db.query(DatabaseTables.chartMomentEvents);

      final result = await repository.finalizeWeek(
        snapshot: createSnapshot(),
        moments: [moment('new-1'), moment('new-2')],
      );

      expect(result.moments, ChartFinalizedMoments.keptEarlier);
      expect(await db.query(DatabaseTables.chartMomentEvents), earlier);
      expect(await db.query(DatabaseTables.chartSnapshots), hasLength(1));
    });

    test(
      'Moments for another week are refused before anything is written',
      () async {
        final before = await rows();

        expect(
          () => repository.finalizeWeek(
            snapshot: createSnapshot(),
            moments: [moment('m1', week: DateTime.utc(2026, 9, 20))],
          ),
          throwsArgumentError,
        );

        expect(await rows(), before);
      },
    );

    test('an unfinalized snapshot is refused', () async {
      final before = await rows();

      expect(
        () =>
            repository.finalizeWeek(snapshot: createSnapshot(finalized: false)),
        throwsArgumentError,
      );

      expect(await rows(), before);
    });

    test('nothing is written while a restore holds the library', () async {
      final before = await rows();
      final release = Completer<void>();
      final restoring = database.mutationCoordinator.runExclusiveRestore(
        () => release.future,
      );

      await expectLater(
        repository.finalizeWeek(
          snapshot: createSnapshot(),
          moments: [moment('m1')],
        ),
        throwsA(isA<LibraryMutationUnavailable>()),
      );

      release.complete();
      await restoring;
      expect(await rows(), before);
    });

    test('replaceSnapshot never rewrites a finalized week', () async {
      await repository.finalizeWeek(snapshot: createSnapshot());
      final stored = await rows();

      await expectLater(
        repository.replaceSnapshot(
          createSnapshot(
            revision: 2,
            entries: [createEntry(entityId: 'song-z', rank: 1)],
          ),
        ),
        throwsA(isA<FinalizedChartWeekFrozen>()),
      );

      expect(await rows(), stored);
    });
  });
}
