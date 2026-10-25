import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/import/application/models/import_review_queue_item.dart';
import 'package:sonus_next/features/import/application/services/import_review_cleanup_service.dart';
import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/data/daos/song_import_review_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_song_import_review_repository.dart';
import 'package:sonus_next/features/import/presentation/scopes/import_scope.dart';
import 'package:sonus_next/features/library/application/services/artist_creation_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

import '../../../../support/library_seed.dart';

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late AppDatabase appDatabase;
  late Database db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sonus_review_');
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}review.db',
    );
    db = await appDatabase.database;

    await seedConnectedLibrary(db, key: 'a');
    await seedImportReview(db, key: 'a');
  });

  tearDown(() async {
    await appDatabase.close();
    await directory.delete(recursive: true);
  });

  Future<T> whileRestoring<T>(Future<T> Function() body) async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final restore = appDatabase.mutationCoordinator.runExclusiveRestore(
      () async {
        entered.complete();
        await release.future;
      },
    );
    await entered.future;

    try {
      return await body();
    } finally {
      release.complete();
      await restore;
    }
  }

  group('review resolution', () {
    late _CommitHookRunner runner;
    late ImportReviewService service;

    // Mirrors ImportScope: the review repository is coordinated and the
    // track edit runs through its own admitted SyncMutationTransactionRunner.
    setUp(() {
      runner = _CommitHookRunner(
        SyncMutationTransactionRunner(appDatabase: appDatabase),
      );
      service = ImportReviewService(
        reviewRepository: SqliteSongImportReviewRepository(
          SongImportReviewDao(db),
          appDatabase: appDatabase,
        ),
        libraryQueryRepository: SqliteLibraryQueryRepository(
          LibraryQueryDao(db),
        ),
        trackProfileEditingService: TrackProfileEditingService(
          mutationRunner: runner,
        ),
        artistCreationService: ArtistCreationService(mutationRunner: runner),
      );
    });

    Future<void> resolve(ImportReviewQueueItem item) {
      return service.updateTrackAndResolve(
        userId: null,
        item: item,
        title: 'Edited title',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
        artistId: 'artist-a',
        albumId: 'album-a',
        placementEditionId: 'edition-a',
      );
    }

    Future<Map<String, Object?>> songRow() async {
      final rows = await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: ['song-a'],
      );
      return rows.single;
    }

    Future<Map<String, Object?>> reviewRow() async {
      final rows = await db.query(
        DatabaseTables.songImportReviews,
        where: 'song_id = ?',
        whereArgs: ['song-a'],
      );
      return rows.single;
    }

    test('resolves normally when no restore is active', () async {
      await resolve((await service.getUnresolved()).single);

      expect((await songRow())['title'], 'Edited title');
      expect((await reviewRow())['resolved_at'], isNotNull);
      expect(await service.getUnresolved(), isEmpty);
      expect(appDatabase.mutationCoordinator.activeMutations, 0);
    });

    test(
      'a restore already in progress rejects the edit; nothing is written',
      () async {
        final item = (await service.getUnresolved()).single;
        final before = await snapshotDatabase(db);

        await whileRestoring(() async {
          await expectLater(
            resolve(item),
            throwsA(isA<LibraryMutationUnavailable>()),
          );
        });

        expect(await snapshotDatabase(db), before);
      },
    );

    test('a restore requested after the edit commits rejects the resolution, '
        'keeps the edit, and a retry after the restore resolves', () async {
      final item = (await service.getUnresolved()).single;
      final reviewBefore = await reviewRow();

      final release = Completer<void>();
      Future<void>? restore;
      runner.afterCommit = () {
        restore = appDatabase.mutationCoordinator.runExclusiveRestore(
          () => release.future,
        );
      };

      try {
        await expectLater(
          resolve(item),
          throwsA(isA<LibraryMutationUnavailable>()),
        );

        // The separate track-edit transaction committed before admission
        // closed; the review resolution was refused.
        expect((await songRow())['title'], 'Edited title');
        expect(await reviewRow(), reviewBefore);
      } finally {
        release.complete();
        await restore;
      }

      final retried = (await service.getUnresolved()).single;
      await resolve(retried);

      expect((await reviewRow())['resolved_at'], isNotNull);
      expect(await service.getUnresolved(), isEmpty);
      expect(appDatabase.mutationCoordinator.activeMutations, 0);
    });
  });

  group('startup duration maintenance', () {
    late List<String> messages;
    late List<int> levels;
    late List<StackTrace?> stackTraces;

    setUp(() {
      messages = [];
      levels = [];
      stackTraces = [];
    });

    void log(String message, {required int level, StackTrace? stackTrace}) {
      messages.add(message);
      levels.add(level);
      stackTraces.add(stackTrace);
    }

    test('runs repair then cleanup and logs nothing on success', () async {
      final calls = <String>[];

      await runStartupDurationMaintenance(
        repairDurations: () async => calls.add('repair'),
        cleanupReviews: () async => calls.add('cleanup'),
        log: log,
      );

      expect(calls, ['repair', 'cleanup']);
      expect(messages, isEmpty);
    });

    test('a repair failure is reported as repair, skips cleanup, and omits '
        'error details', () async {
      var cleanupCalls = 0;

      await runStartupDurationMaintenance(
        repairDurations: () async =>
            throw StateError('/private/Music/Secret Song.mp3'),
        cleanupReviews: () async => cleanupCalls++,
        log: log,
      );

      expect(cleanupCalls, 0);
      expect(messages, ['Startup duration repair failed: StateError.']);
      expect(levels, [1000]);
      expect(stackTraces.single, isNotNull);
    });

    test(
      'a cleanup failure after a successful repair is reported as cleanup',
      () async {
        await runStartupDurationMaintenance(
          repairDurations: () async {},
          cleanupReviews: () async =>
              throw StateError('Song import review not found: song-a'),
          log: log,
        );

        expect(messages, ['Startup review cleanup failed: StateError.']);
        expect(levels, [1000]);
      },
    );

    test('restore rejection stops each stage without retrying', () async {
      var repairCalls = 0;
      var cleanupCalls = 0;

      await runStartupDurationMaintenance(
        repairDurations: () async {
          repairCalls++;
          throw const LibraryMutationUnavailable('restoring');
        },
        cleanupReviews: () async => cleanupCalls++,
        log: log,
      );
      await runStartupDurationMaintenance(
        repairDurations: () async => repairCalls++,
        cleanupReviews: () async {
          cleanupCalls++;
          throw const LibraryMutationUnavailable('restoring');
        },
        log: log,
      );

      expect(repairCalls, 2);
      expect(cleanupCalls, 1);
      expect(messages, [
        'Startup duration repair stopped: library restoration is active.',
        'Startup review cleanup stopped: library restoration is active.',
      ]);
      expect(levels, [800, 800]);
    });

    test('coordinated cleanup during a restore is stopped and logged, '
        'leaving reviews unchanged', () async {
      await db.update(
        DatabaseTables.songImportReviews,
        {'review_reasons': '["missingDuration"]'},
        where: 'song_id = ?',
        whereArgs: ['song-a'],
      );
      final before = await snapshotDatabase(db);
      final cleanup = ImportReviewCleanupService(
        reviewRepository: SqliteSongImportReviewRepository(
          SongImportReviewDao(db),
          appDatabase: appDatabase,
        ),
        songRepository: SqliteSongRepository(SongDao(db)),
        appDatabase: appDatabase,
      );

      await whileRestoring(
        () => runStartupDurationMaintenance(
          repairDurations: () async {},
          cleanupReviews: cleanup.cleanupStaleDurationReasons,
          log: log,
        ),
      );

      expect(messages, [
        'Startup review cleanup stopped: library restoration is active.',
      ]);
      expect(await snapshotDatabase(db), before);
      expect(appDatabase.mutationCoordinator.activeMutations, 0);
    });
  });
}

/// Delegates to a real runner and fires a one-shot hook right after the
/// first mutation commits.
class _CommitHookRunner implements SyncMutationRunner {
  _CommitHookRunner(this._inner);

  final SyncMutationRunner _inner;
  void Function()? afterCommit;

  @override
  Future<T> run<T>(SyncMutationAction<T> action) async {
    final result = await _inner.run(action);
    final hook = afterCommit;
    afterCommit = null;
    hook?.call();
    return result;
  }
}
