import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_session_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/qualified_play_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_session_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_qualified_play_repository.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_repository.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/domain/services/chart_week_resolver.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';

import '../../../../support/library_seed.dart';

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late AppDatabase appDatabase;
  late Database db;
  late _GatedPlays plays;
  late _ObservedCharts charts;

  const resolver = ChartWeekResolver();
  final referenceLocal = DateTime(2026, 10, 23, 12);

  // Two weeks before Moments activation and one after it.
  final w1 = DateTime.utc(2026, 8, 5, 12);
  final w2 = DateTime.utc(2026, 8, 12, 12);
  final w3 = DateTime.utc(2026, 10, 7, 12);

  DateTime weekStart(DateTime at) => resolver.resolve(at.toLocal()).startUtc;
  DateTime weekEnd(DateTime at) => resolver.resolve(at.toLocal()).endUtc;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sonus_charts_');
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}charts.db',
    );
    db = await appDatabase.database;
    plays = _GatedPlays(SqliteQualifiedPlayRepository(QualifiedPlayDao(db)));
    charts = _ObservedCharts(SqliteChartRepository(appDatabase));
  });

  tearDown(() async {
    await appDatabase.close();
    await directory.delete(recursive: true);
  });

  /// Composed as ChartsScope composes it.
  ChartFinalizationService service({bool guarded = true}) {
    return ChartFinalizationService(
      builder: ChartSnapshotBuilderService(
        qualifiedPlays: plays,
        library: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
        charts: charts.inner,
        playbackSessions: SqlitePlaybackSessionRepository(
          PlaybackSessionDao(db),
        ),
      ),
      charts: charts,
      qualifiedPlays: plays,
      moments: SqliteChartMomentRepository(appDatabase),
      momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 20),
      now: () => DateTime.utc(2026, 10, 23),
      restoreGeneration: guarded
          ? () => appDatabase.mutationCoordinator.restoreGeneration
          : null,
    );
  }

  Future<void> listen(String id, String song, DateTime at) async {
    final iso = at.toIso8601String();
    await db.insert(DatabaseTables.playbackSessions, {
      'id': 'session-$id',
      'song_id': song,
      'artist_id': 'artist-$song',
      'album_id': 'album-$song',
      'album_edition_id': 'edition-$song',
      'song_title': 'Title $song',
      'artist_name': 'Artist $song',
      'album_title': 'Album $song',
      'album_edition_title': 'Album $song',
      'started_at': iso,
      'ended_at': iso,
      'listened_duration_ms': 180000,
      'track_duration_ms': 180000,
      'final_position_ms': 180000,
      'end_reason': 'completed',
      'created_at': iso,
      'updated_at': iso,
    });
    await db.insert(DatabaseTables.qualifiedPlays, {
      'id': 'play-$id',
      'playback_session_id': 'session-$id',
      'song_id': song,
      'artist_id': 'artist-$song',
      'album_id': 'album-$song',
      'album_edition_id': 'edition-$song',
      'qualified_at': iso,
      'listened_duration_ms': 180000,
      'track_duration_ms': 180000,
      'created_at': iso,
    });
  }

  /// What a restore from a backup without [week]'s listening leaves behind:
  /// without any charts, or, with [onlyThatWeek], without that week's charts
  /// only.
  Future<void> restoreWithout(
    DatabaseExecutor tx,
    DateTime week, {
    bool onlyThatWeek = false,
  }) async {
    final start = weekStart(week).toIso8601String();
    final end = weekEnd(week).toIso8601String();

    if (onlyThatWeek) {
      await tx.delete(
        DatabaseTables.chartMomentEvents,
        where: 'week_start_utc = ?',
        whereArgs: [start],
      );
      await tx.rawDelete(
        'DELETE FROM ${DatabaseTables.chartEntries} WHERE chart_snapshot_id IN '
        '(SELECT id FROM ${DatabaseTables.chartSnapshots} '
        'WHERE week_start_utc = ?)',
        [start],
      );
      await tx.delete(
        DatabaseTables.chartSnapshots,
        where: 'week_start_utc = ?',
        whereArgs: [start],
      );
    } else {
      await tx.delete(DatabaseTables.chartMomentEvents);
      await tx.delete(DatabaseTables.chartEntries);
      await tx.delete(DatabaseTables.chartSnapshots);
    }

    await tx.delete(
      DatabaseTables.qualifiedPlays,
      where: 'qualified_at >= ? AND qualified_at < ?',
      whereArgs: [start, end],
    );
    await tx.delete(
      DatabaseTables.playbackSessions,
      where: 'started_at >= ? AND started_at < ?',
      whereArgs: [start, end],
    );
  }

  Future<void> restore(Future<void> Function(Transaction tx) change) {
    return appDatabase.mutationCoordinator.runExclusiveRestore(
      () => db.transaction(change),
    );
  }

  Future<List<Map<String, Object?>>> snapshotsFor(DateTime week) {
    return db.query(
      DatabaseTables.chartSnapshots,
      where: 'week_start_utc = ?',
      whereArgs: [weekStart(week).toIso8601String()],
    );
  }

  group('a pass that spans a restore writes nothing', () {
    test('1a: no empty chart for a week the restore removed', () async {
      await listen('1', 'song-a', w1);
      await listen('2', 'song-b', w2);

      final gate = plays.holdBuildOf(weekStart(w1));
      final pass = service().finalizeCompletedWeeks(
        referenceLocal: referenceLocal,
      );
      await gate.arrived;

      await restore((tx) => restoreWithout(tx, w1));
      final restored = await snapshotDatabase(db);

      gate.release();

      await expectLater(pass, throwsA(isA<LibraryMutationUnavailable>()));
      expect(await snapshotsFor(w1), isEmpty);
      expect(await snapshotDatabase(db), restored);
    });

    test('1b: the stale list of weeks is never used after a restore', () async {
      await listen('1', 'song-a', w1);
      await listen('2', 'song-b', w2);
      await service().finalizeCompletedWeeks(referenceLocal: referenceLocal);
      final finalized = await db.query(DatabaseTables.chartSnapshots);
      expect(finalized, hasLength(4));

      // Hold the second pass inside W1, which is unchanged and so writes
      // nothing, while a restore removes W2.
      final gate = plays.holdBuildOf(weekStart(w1));
      final pass = service().finalizeCompletedWeeks(
        referenceLocal: referenceLocal,
      );
      await gate.arrived;

      // W1 stays as it was, so the held pass has nothing to write there.
      await restore((tx) => restoreWithout(tx, w2, onlyThatWeek: true));
      expect(await snapshotsFor(w2), isEmpty);
      expect(await snapshotsFor(w1), hasLength(2));
      final restored = await snapshotDatabase(db);

      gate.release();

      await expectLater(pass, throwsA(isA<LibraryMutationUnavailable>()));
      expect(await snapshotsFor(w2), isEmpty);
      expect(await snapshotDatabase(db), restored);
    });

    test('2: the Moments write is refused on its own', () async {
      await listen('3', 'song-c', w3);

      // The snapshot write completes; the restore lands before Moments.
      final gate = plays.holdNextReadAfter(charts.replaced(weekStart(w3)));
      final pass = service().finalizeCompletedWeeks(
        referenceLocal: referenceLocal,
      );
      await gate.arrived;
      expect(await snapshotsFor(w3), isNotEmpty);

      await restore((tx) => restoreWithout(tx, w3));
      final restored = await snapshotDatabase(db);

      gate.release();

      await expectLater(pass, throwsA(isA<LibraryMutationUnavailable>()));
      expect(await db.query(DatabaseTables.chartMomentEvents), isEmpty);
      expect(await snapshotDatabase(db), restored);
    });

    test('3: a read that crosses the restore commit is not written', () async {
      await listen('1', 'song-a', w1);
      await listen('2', 'song-b', w2);

      final gate = plays.holdBuildOf(weekStart(w1), holdResult: true);
      final pass = service().finalizeCompletedWeeks(
        referenceLocal: referenceLocal,
      );
      await gate.arrived;

      final inTransaction = Completer<void>();
      final commit = Completer<void>();
      final restoring = appDatabase.mutationCoordinator.runExclusiveRestore(
        () => db.transaction((tx) async {
          await restoreWithout(tx, w2);
          inTransaction.complete();
          await commit.future;
        }),
      );
      await inTransaction.future;

      // The held read now reaches SQLite and waits behind the open restore
      // transaction, so it returns restored data.
      gate.release();
      await pumpEventQueue();
      commit.complete();
      await restoring;
      await gate.resultRead;
      final restored = await snapshotDatabase(db);

      gate.releaseResult();

      await expectLater(pass, throwsA(isA<LibraryMutationUnavailable>()));
      expect(await snapshotDatabase(db), restored);
    });
  });

  test('5: an undisturbed pass finalizes as before', () async {
    await listen('1', 'song-a', w1);
    await listen('2', 'song-b', w2);
    await listen('3', 'song-c', w3);

    final first = await service().finalizeCompletedWeeks(
      referenceLocal: referenceLocal,
    );

    expect(first, hasLength(6));
    expect(await snapshotsFor(w1), hasLength(2));
    expect(await snapshotsFor(w3), hasLength(2));
    expect(await db.query(DatabaseTables.chartMomentEvents), isNotEmpty);
    expect(appDatabase.mutationCoordinator.activeMutations, 0);

    final snapshots = await db.query(DatabaseTables.chartSnapshots);
    final entries = await db.query(DatabaseTables.chartEntries);

    final second = await service().finalizeCompletedWeeks(
      referenceLocal: referenceLocal,
    );

    expect(second.map((snapshot) => snapshot.revision), everyElement(1));
    expect(await db.query(DatabaseTables.chartSnapshots), snapshots);
    expect(await db.query(DatabaseTables.chartEntries), entries);
  });

  test(
    '6: a write during an active restore is still refused by admission',
    () async {
      await listen('1', 'song-a', w1);

      final gate = plays.holdBuildOf(weekStart(w1));
      final pass = service(
        guarded: false,
      ).finalizeCompletedWeeks(referenceLocal: referenceLocal);
      await gate.arrived;

      final before = await snapshotDatabase(db);
      final release = Completer<void>();
      final restoring = appDatabase.mutationCoordinator.runExclusiveRestore(
        () => release.future,
      );

      gate.release();

      try {
        await expectLater(pass, throwsA(isA<LibraryMutationUnavailable>()));
      } finally {
        release.complete();
        await restoring;
      }

      expect(await snapshotDatabase(db), before);
    },
  );
}

/// A pause point inside a finalization pass.
class _Gate {
  final _arrived = Completer<void>();
  final _release = Completer<void>();
  final _resultRead = Completer<void>();
  final _releaseResult = Completer<void>();

  Future<void> get arrived => _arrived.future;
  Future<void> get resultRead => _resultRead.future;

  void release() => _release.complete();
  void releaseResult() => _releaseResult.complete();
}

/// Lets a test hold a chosen listening-history read of the pass.
class _GatedPlays implements QualifiedPlayRepository {
  _GatedPlays(this._inner);

  final QualifiedPlayRepository _inner;
  bool Function(DateTime? from, DateTime? before)? _matches;
  _Gate? _gate;
  bool _holdResult = false;

  /// Holds the week's chart-build read, before it reaches the database and
  /// optionally again after its result is read.
  _Gate holdBuildOf(DateTime weekStartUtc, {bool holdResult = false}) {
    _holdResult = holdResult;
    _matches = (from, _) => from == weekStartUtc;
    return _gate = _Gate();
  }

  /// Holds the first read made after [armed] completes.
  _Gate holdNextReadAfter(Future<void> armed) {
    final gate = _gate = _Gate();
    var isArmed = false;
    unawaited(armed.then((_) => isArmed = true));
    _matches = (_, _) => isArmed;
    return gate;
  }

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    final gate = _gate;
    final matches = _matches;

    if (gate == null ||
        matches == null ||
        !matches(qualifiedAtOrAfter, qualifiedBefore)) {
      return _inner.getAll(
        qualifiedAtOrAfter: qualifiedAtOrAfter,
        qualifiedBefore: qualifiedBefore,
      );
    }

    _gate = null;
    gate._arrived.complete();
    await gate._release.future;

    final result = await _inner.getAll(
      qualifiedAtOrAfter: qualifiedAtOrAfter,
      qualifiedBefore: qualifiedBefore,
    );

    if (_holdResult) {
      gate._resultRead.complete();
      await gate._releaseResult.future;
    }

    return result;
  }

  @override
  Future<void> create(QualifiedPlay play) => _inner.create(play);

  @override
  Future<void> save(QualifiedPlay play) => _inner.save(play);

  @override
  Future<QualifiedPlay?> getById(String id) => _inner.getById(id);

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(String playbackSessionId) {
    return _inner.getByPlaybackSessionId(playbackSessionId);
  }

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) {
    return _inner.getByPlaybackSessionIds(playbackSessionIds);
  }
}

/// Reports completed snapshot writes.
class _ObservedCharts implements ChartRepository {
  _ObservedCharts(this.inner);

  final ChartRepository inner;
  final Map<DateTime, Completer<void>> _replaced = {};

  /// Completes once the first snapshot of [weekStartUtc] has been written.
  Future<void> replaced(DateTime weekStartUtc) {
    return (_replaced[weekStartUtc] ??= Completer<void>()).future;
  }

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) async {
    await inner.replaceSnapshot(snapshot);

    final done = _replaced[snapshot.weekStartUtc.toUtc()];
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }

  @override
  Future<ChartSnapshot?> getById(String id) => inner.getById(id);

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) {
    return inner.getForWeek(chartType: chartType, weekStartUtc: weekStartUtc);
  }

  @override
  Future<List<ChartSnapshot>> getHistory(ChartType chartType, {int? limit}) {
    return inner.getHistory(chartType, limit: limit);
  }
}
