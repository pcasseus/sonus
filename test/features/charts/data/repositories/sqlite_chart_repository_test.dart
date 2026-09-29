import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_repository.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';

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
    List<ChartEntry>? entries,
  }) {
    return ChartSnapshot(
      id: id,
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
      finalizedAt: DateTime.utc(2026, 10, 4),
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

  test('higher revision replaces existing snapshot contents', () async {
    await repository.replaceSnapshot(
      createSnapshot(
        revision: 1,
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
        entries: [createEntry(entityId: 'song-new', rank: 1, streams: 30)],
      ),
    );

    await expectLater(
      repository.replaceSnapshot(
        createSnapshot(
          revision: 2,
          entries: [createEntry(entityId: 'song-old', rank: 1, streams: 5)],
        ),
      ),
      throwsA(isA<StateError>()),
    );

    final restored = await repository.getForWeek(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
    );

    expect(restored, isNotNull);
    expect(restored!.revision, 3);
    expect(restored.entries.single.entity.entityId, 'song-new');
  });

  test('same revision can be written idempotently', () async {
    final snapshot = createSnapshot(revision: 2);

    await repository.replaceSnapshot(snapshot);
    await repository.replaceSnapshot(snapshot);

    final restored = await repository.getById(snapshot.id);

    expect(restored, isNotNull);
    expect(restored!.revision, 2);
    expect(restored.entries, hasLength(2));
  });

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
}
