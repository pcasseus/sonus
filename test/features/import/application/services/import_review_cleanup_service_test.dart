import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/import/application/services/import_review_cleanup_service.dart';
import 'package:sonus_next/features/import/data/daos/song_import_review_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_song_import_review_repository.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/import/domain/repositories/song_import_review_repository.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  sqfliteFfiInit();

  late _ObservedAppDatabase appDatabase;
  late SqliteSongImportReviewRepository reviewRepository;
  late SqliteSongRepository songRepository;

  final originalTime = DateTime.utc(2026, 9, 19, 12);
  final cleanupTime = DateTime.utc(2026, 9, 19, 14);

  setUp(() async {
    appDatabase = _ObservedAppDatabase();

    final db = await appDatabase.database;

    reviewRepository = SqliteSongImportReviewRepository(
      SongImportReviewDao(db),
    );
    songRepository = SqliteSongRepository(SongDao(db));
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<Song> createSong({
    required String suffix,
    required int durationSeconds,
  }) async {
    final artist = EntityFactory.createArtist(
      name: 'Artist $suffix',
      now: originalTime,
    );

    final album = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'Album $suffix',
      now: originalTime,
    );

    final edition = EntityFactory.createAlbumEdition(
      albumId: album.id,
      title: 'Edition $suffix',
      isPrimary: true,
      now: originalTime,
    );

    final song = EntityFactory.createSong(
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Song $suffix',
      trackNumber: 1,
      durationSeconds: durationSeconds,
      isSingle: false,
      featuredArtists: const [],
      now: originalTime,
    );

    final db = await appDatabase.database;

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(album);
    await AlbumEditionDao(db).insert(edition);
    await SongDao(db).insert(song);

    return song;
  }

  Future<void> createReview({
    required Song song,
    required List<ImportReviewReason> reasons,
    DateTime? resolvedAt,
    DateTime? createdAt,
  }) async {
    await reviewRepository.create(
      SongImportReview(
        songId: song.id,
        metadataSource: MetadataSource.fallback,
        reasons: List.unmodifiable(reasons),
        resolvedAt: resolvedAt,
        createdAt: createdAt ?? originalTime,
        updatedAt: originalTime,
      ),
    );
  }

  ImportReviewCleanupService buildService() {
    return ImportReviewCleanupService(
      reviewRepository: reviewRepository,
      songRepository: songRepository,
      now: () => cleanupTime,
    );
  }

  test(
    'removes missing duration while preserving other unresolved reasons',
    () async {
      final song = await createSong(
        suffix: 'mixed_reasons',
        durationSeconds: 214,
      );

      await createReview(
        song: song,
        reasons: const [
          ImportReviewReason.fallbackMetadata,
          ImportReviewReason.missingDuration,
          ImportReviewReason.missingTrackNumber,
        ],
      );

      final summary = await buildService().cleanupStaleDurationReasons();

      expect(summary.examined, 1);
      expect(summary.updated, 1);
      expect(summary.resolved, 0);
      expect(summary.skipped, 0);

      final stored = await reviewRepository.getBySongId(song.id);

      expect(stored, isNotNull);
      expect(stored!.reasons, const [
        ImportReviewReason.fallbackMetadata,
        ImportReviewReason.missingTrackNumber,
      ]);
      expect(stored.resolvedAt, isNull);
      expect(stored.updatedAt, cleanupTime);
      expect(stored.needsReview, isTrue);
    },
  );

  test('resolves review when missing duration was its only reason', () async {
    final song = await createSong(
      suffix: 'duration_only',
      durationSeconds: 180,
    );

    await createReview(
      song: song,
      reasons: const [ImportReviewReason.missingDuration],
    );

    final summary = await buildService().cleanupStaleDurationReasons();

    expect(summary.examined, 1);
    expect(summary.updated, 0);
    expect(summary.resolved, 1);
    expect(summary.skipped, 0);

    final stored = await reviewRepository.getBySongId(song.id);

    expect(stored, isNotNull);
    expect(stored!.reasons, isEmpty);
    expect(stored.resolvedAt, cleanupTime);
    expect(stored.updatedAt, cleanupTime);
    expect(stored.needsReview, isFalse);
  });

  test('review without missing duration remains unchanged', () async {
    final song = await createSong(suffix: 'unrelated', durationSeconds: 200);

    await createReview(
      song: song,
      reasons: const [ImportReviewReason.fallbackMetadata],
    );

    final summary = await buildService().cleanupStaleDurationReasons();

    expect(summary.examined, 1);
    expect(summary.updated, 0);
    expect(summary.resolved, 0);
    expect(summary.skipped, 1);

    final stored = await reviewRepository.getBySongId(song.id);

    expect(stored, isNotNull);
    expect(stored!.reasons, const [ImportReviewReason.fallbackMetadata]);
    expect(stored.resolvedAt, isNull);
    expect(stored.updatedAt, originalTime);
  });

  test('missing duration remains when song duration is still zero', () async {
    final song = await createSong(suffix: 'still_missing', durationSeconds: 0);

    await createReview(
      song: song,
      reasons: const [ImportReviewReason.missingDuration],
    );

    final summary = await buildService().cleanupStaleDurationReasons();

    expect(summary.examined, 1);
    expect(summary.updated, 0);
    expect(summary.resolved, 0);
    expect(summary.skipped, 1);

    final stored = await reviewRepository.getBySongId(song.id);

    expect(stored, isNotNull);
    expect(stored!.reasons, const [ImportReviewReason.missingDuration]);
    expect(stored.resolvedAt, isNull);
    expect(stored.updatedAt, originalTime);
  });

  test('already resolved review remains unchanged', () async {
    final resolvedTime = originalTime.add(const Duration(minutes: 30));

    final song = await createSong(suffix: 'resolved', durationSeconds: 200);

    await createReview(
      song: song,
      reasons: const [ImportReviewReason.missingDuration],
      resolvedAt: resolvedTime,
    );

    final summary = await buildService().cleanupStaleDurationReasons();

    expect(summary.examined, 0);
    expect(summary.updated, 0);
    expect(summary.resolved, 0);
    expect(summary.skipped, 0);

    final stored = await reviewRepository.getBySongId(song.id);

    expect(stored, isNotNull);
    expect(stored!.reasons, const [ImportReviewReason.missingDuration]);
    expect(stored.resolvedAt, resolvedTime);
    expect(stored.updatedAt, originalTime);
  });

  group('coordinated per-candidate transactions', () {
    ImportReviewCleanupService buildCoordinated({
      Future<void> Function()? afterListing,
    }) {
      // The injected repositories are deliberately uncoordinated, so restore
      // admission can only come from the service's own transactions.
      return ImportReviewCleanupService(
        reviewRepository: _ListingHook(
          reviewRepository,
          afterListing ?? () async {},
        ),
        songRepository: songRepository,
        appDatabase: appDatabase,
        now: () => cleanupTime,
      );
    }

    Future<Map<String, Object?>> reviewRow(Song song) async {
      final rows = await (await appDatabase.database).query(
        DatabaseTables.songImportReviews,
        where: 'song_id = ?',
        whereArgs: [song.id],
      );
      return rows.single;
    }

    DateTime order(int minutes) => originalTime.add(Duration(minutes: minutes));

    test(
      'uses one short, non-nested transaction per duration candidate',
      () async {
        final mixed = await createSong(suffix: 'mixed', durationSeconds: 210);
        final only = await createSong(suffix: 'only', durationSeconds: 190);
        final other = await createSong(suffix: 'other', durationSeconds: 200);

        await createReview(
          song: mixed,
          reasons: const [
            ImportReviewReason.missingDuration,
            ImportReviewReason.unknownAlbum,
          ],
          createdAt: order(1),
        );
        await createReview(
          song: only,
          reasons: const [ImportReviewReason.missingDuration],
          createdAt: order(2),
        );
        await createReview(
          song: other,
          reasons: const [ImportReviewReason.fallbackMetadata],
          createdAt: order(3),
        );
        appDatabase.transactions = 0;

        // A nested admitted transaction would deadlock on the SQLite lock.
        final summary = await buildCoordinated()
            .cleanupStaleDurationReasons()
            .timeout(const Duration(seconds: 10));

        expect(summary.examined, 3);
        expect(summary.updated, 1);
        expect(summary.resolved, 1);
        expect(summary.skipped, 1);
        expect(appDatabase.transactions, 2);
        expect(appDatabase.maxDepth, 1);
        expect(appDatabase.mutationCoordinator.activeMutations, 0);

        final mixedStored = await reviewRepository.getBySongId(mixed.id);
        expect(mixedStored!.reasons, const [ImportReviewReason.unknownAlbum]);
        expect(mixedStored.resolvedAt, isNull);
        expect(
          (await reviewRepository.getBySongId(only.id))!.resolvedAt,
          cleanupTime,
        );
        expect(
          (await reviewRepository.getBySongId(other.id))!.updatedAt,
          originalTime,
        );
      },
    );

    test('does not un-resolve a review resolved after the listing', () async {
      final song = await createSong(suffix: 'resolved', durationSeconds: 200);
      await createReview(
        song: song,
        reasons: const [
          ImportReviewReason.missingDuration,
          ImportReviewReason.unknownArtist,
        ],
      );
      final userResolvedAt = originalTime.add(const Duration(hours: 1));
      late Map<String, Object?> afterUser;

      final summary = await buildCoordinated(
        afterListing: () async {
          final current = await reviewRepository.getBySongId(song.id);
          await reviewRepository.save(
            current!.copyWith(
              resolvedAt: userResolvedAt,
              updatedAt: userResolvedAt,
            ),
          );
          afterUser = await reviewRow(song);
        },
      ).cleanupStaleDurationReasons();

      expect(summary.skipped, 1);
      expect(summary.updated + summary.resolved, 0);
      expect(await reviewRow(song), afterUser);

      final stored = await reviewRepository.getBySongId(song.id);
      expect(stored!.resolvedAt, userResolvedAt);
      expect(stored.updatedAt, userResolvedAt);
      expect(stored.reasons, const [
        ImportReviewReason.missingDuration,
        ImportReviewReason.unknownArtist,
      ]);
    });

    test(
      'does not rewrite a review that lost missing duration after listing',
      () async {
        final song = await createSong(suffix: 'lost', durationSeconds: 200);
        await createReview(
          song: song,
          reasons: const [
            ImportReviewReason.missingDuration,
            ImportReviewReason.fallbackMetadata,
          ],
        );
        final editedAt = originalTime.add(const Duration(minutes: 45));
        late Map<String, Object?> afterEdit;

        final summary = await buildCoordinated(
          afterListing: () async {
            final current = await reviewRepository.getBySongId(song.id);
            await reviewRepository.save(
              current!.copyWith(
                reasons: const [ImportReviewReason.fallbackMetadata],
                updatedAt: editedAt,
              ),
            );
            afterEdit = await reviewRow(song);
          },
        ).cleanupStaleDurationReasons();

        expect(summary.skipped, 1);
        expect(summary.updated + summary.resolved, 0);
        expect(await reviewRow(song), afterEdit);

        final stored = await reviewRepository.getBySongId(song.id);
        expect(stored!.reasons, const [ImportReviewReason.fallbackMetadata]);
        expect(stored.resolvedAt, isNull);
        expect(stored.updatedAt, editedAt);
      },
    );

    test('skips a review removed after the listing and continues', () async {
      final removed = await createSong(suffix: 'gone', durationSeconds: 200);
      final kept = await createSong(suffix: 'kept', durationSeconds: 200);
      await createReview(
        song: removed,
        reasons: const [ImportReviewReason.missingDuration],
        createdAt: order(1),
      );
      await createReview(
        song: kept,
        reasons: const [ImportReviewReason.missingDuration],
        createdAt: order(2),
      );

      final summary = await buildCoordinated(
        afterListing: () async {
          await (await appDatabase.database).delete(
            DatabaseTables.songImportReviews,
            where: 'song_id = ?',
            whereArgs: [removed.id],
          );
        },
      ).cleanupStaleDurationReasons();

      expect(summary.examined, 2);
      expect(summary.skipped, 1);
      expect(summary.resolved, 1);
      expect(await reviewRepository.getBySongId(removed.id), isNull);
      expect(
        (await reviewRepository.getBySongId(kept.id))!.resolvedAt,
        cleanupTime,
      );
    });

    test('rolls back a candidate whose write fails', () async {
      final first = await createSong(suffix: 'first', durationSeconds: 200);
      final failing = await createSong(suffix: 'fail', durationSeconds: 200);
      final last = await createSong(suffix: 'last', durationSeconds: 200);
      for (final (index, song) in [first, failing, last].indexed) {
        await createReview(
          song: song,
          reasons: const [ImportReviewReason.missingDuration],
          createdAt: order(index + 1),
        );
      }
      final failingBefore = await reviewRow(failing);
      final lastBefore = await reviewRow(last);

      // The update itself runs, then the trigger aborts it.
      final db = await appDatabase.database;
      await db.execute(
        'CREATE TABLE review_write_failures (song_id TEXT PRIMARY KEY)',
      );
      await db.insert('review_write_failures', {'song_id': failing.id});
      await db.execute('''
        CREATE TRIGGER fail_review_cleanup
        AFTER UPDATE ON ${DatabaseTables.songImportReviews}
        WHEN NEW.song_id IN (SELECT song_id FROM review_write_failures)
        BEGIN
          SELECT RAISE(ABORT, 'review write failed');
        END
      ''');

      await expectLater(
        buildCoordinated().cleanupStaleDurationReasons(),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        (await reviewRepository.getBySongId(first.id))!.resolvedAt,
        cleanupTime,
      );
      expect(await reviewRow(failing), failingBefore);
      expect(await reviewRow(last), lastBefore);
      expect(appDatabase.mutationCoordinator.activeMutations, 0);
    });

    test('stops mid-pass when a restore begins and does not retry', () async {
      final first = await createSong(suffix: 'before', durationSeconds: 200);
      final second = await createSong(suffix: 'after', durationSeconds: 200);
      await createReview(
        song: first,
        reasons: const [ImportReviewReason.missingDuration],
        createdAt: order(1),
      );
      await createReview(
        song: second,
        reasons: const [ImportReviewReason.missingDuration],
        createdAt: order(2),
      );
      final secondBefore = await reviewRow(second);
      appDatabase.transactions = 0;

      final release = Completer<void>();
      Future<void>? restore;
      appDatabase.afterCommit = () {
        restore = appDatabase.mutationCoordinator.runExclusiveRestore(
          () => release.future,
        );
      };

      try {
        await expectLater(
          buildCoordinated().cleanupStaleDurationReasons(),
          throwsA(isA<LibraryMutationUnavailable>()),
        );
      } finally {
        release.complete();
        await restore;
      }
      await pumpEventQueue();

      expect(
        (await reviewRepository.getBySongId(first.id))!.resolvedAt,
        cleanupTime,
      );
      expect(await reviewRow(second), secondBefore);
      expect(appDatabase.transactions, 2);
      expect(appDatabase.mutationCoordinator.activeMutations, 0);
    });
  });
}

/// Counts admitted transactions, their nesting depth, and runs a one-shot
/// hook after the first commit.
class _ObservedAppDatabase extends AppDatabase {
  _ObservedAppDatabase()
    : super(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );

  int transactions = 0;
  int maxDepth = 0;
  int _depth = 0;
  void Function()? afterCommit;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction transaction) action,
  ) async {
    transactions++;
    maxDepth = max(maxDepth, ++_depth);

    try {
      final result = await super.transaction(action);
      final hook = afterCommit;
      afterCommit = null;
      hook?.call();
      return result;
    } finally {
      _depth--;
    }
  }
}

/// Runs [afterListing] once the candidate listing has been read, so tests can
/// change rows between the listing and each candidate's transaction.
class _ListingHook implements SongImportReviewRepository {
  _ListingHook(this._inner, this._afterListing);

  final SongImportReviewRepository _inner;
  final Future<void> Function() _afterListing;

  @override
  Future<List<SongImportReview>> getUnresolved() async {
    final reviews = await _inner.getUnresolved();
    await _afterListing();
    return reviews;
  }

  @override
  Future<void> create(SongImportReview review) => _inner.create(review);

  @override
  Future<void> save(SongImportReview review) => _inner.save(review);

  @override
  Future<SongImportReview?> getBySongId(String songId) {
    return _inner.getBySongId(songId);
  }

  @override
  Future<int> countUnresolved() => _inner.countUnresolved();
}
