import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/import/data/daos/song_import_review_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_song_import_review_repository.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<void> createSong(Database db, DateTime now) async {
    final artist = Artist(
      id: 'artist_review_repo',
      name: 'Artist',
      canonicalName: 'artist',
      createdAt: now,
      updatedAt: now,
    );

    final album = Album(
      id: 'album_review_repo',
      artistId: artist.id,
      title: 'Album',
      canonicalTitle: 'album',
      createdAt: now,
      updatedAt: now,
    );

    final edition = AlbumEdition(
      id: 'edition_review_repo',
      albumId: album.id,
      title: 'Album',
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: now,
      updatedAt: now,
    );

    final song = Song(
      id: 'song_review_repo',
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Song',
      canonicalTitle: 'song',
      trackNumber: 0,
      durationSeconds: 0,
      isSingle: false,
      featuredArtists: const [],
      createdAt: now,
      updatedAt: now,
    );

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(album);
    await AlbumEditionDao(db).insert(edition);
    await SongDao(db).insert(song);
  }

  test(
    'repository creates reads lists counts and resolves review state',
    () async {
      final db = await appDatabase.database;
      final now = DateTime.utc(2026, 9, 17, 12);

      await createSong(db, now);

      final repository = SqliteSongImportReviewRepository(
        SongImportReviewDao(db),
      );

      final review = SongImportReview(
        songId: 'song_review_repo',
        metadataSource: MetadataSource.fallback,
        reasons: const [
          ImportReviewReason.fallbackMetadata,
          ImportReviewReason.missingTrackNumber,
          ImportReviewReason.missingDuration,
        ],
        createdAt: now,
        updatedAt: now,
      );

      await repository.create(review);

      final stored = await repository.getBySongId(review.songId);

      expect(stored, isNotNull);
      expect(stored!.songId, review.songId);
      expect(stored.metadataSource, MetadataSource.fallback);
      expect(stored.reasons, const [
        ImportReviewReason.fallbackMetadata,
        ImportReviewReason.missingTrackNumber,
        ImportReviewReason.missingDuration,
      ]);

      expect(await repository.countUnresolved(), 1);

      final unresolved = await repository.getUnresolved();

      expect(unresolved, hasLength(1));
      expect(unresolved.single.songId, review.songId);

      final resolvedAt = now.add(const Duration(hours: 1));

      await repository.save(
        stored.copyWith(resolvedAt: resolvedAt, updatedAt: resolvedAt),
      );

      final resolved = await repository.getBySongId(review.songId);

      expect(resolved, isNotNull);
      expect(resolved!.resolvedAt, resolvedAt);
      expect(resolved.isResolved, isTrue);
      expect(resolved.needsReview, isFalse);
      expect(await repository.countUnresolved(), 0);
      expect(await repository.getUnresolved(), isEmpty);
    },
  );

  group('coordinated with restore admission', () {
    final now = DateTime.utc(2026, 9, 17, 12);

    SongImportReview review() {
      return SongImportReview(
        songId: 'song_review_repo',
        metadataSource: MetadataSource.fallback,
        reasons: const [ImportReviewReason.missingDuration],
        createdAt: now,
        updatedAt: now,
      );
    }

    Future<List<Map<String, Object?>>> reviewRows() async {
      return (await appDatabase.database).query(
        DatabaseTables.songImportReviews,
      );
    }

    Future<SqliteSongImportReviewRepository> coordinated() async {
      final db = await appDatabase.database;
      await createSong(db, now);

      return SqliteSongImportReviewRepository(
        SongImportReviewDao(db),
        appDatabase: appDatabase,
      );
    }

    Future<void> duringRestore(Future<void> Function() body) async {
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
        await body();
      } finally {
        release.complete();
        await restore;
      }
    }

    test('create is rejected during an exclusive restore', () async {
      final repository = await coordinated();

      await duringRestore(() async {
        await expectLater(
          repository.create(review()),
          throwsA(isA<LibraryMutationUnavailable>()),
        );
      });

      expect(await reviewRows(), isEmpty);
    });

    test('save is rejected during an exclusive restore', () async {
      final repository = await coordinated();
      await repository.create(review());
      final before = await reviewRows();
      final resolvedAt = now.add(const Duration(hours: 1));

      await duringRestore(() async {
        await expectLater(
          repository.save(
            review().copyWith(resolvedAt: resolvedAt, updatedAt: resolvedAt),
          ),
          throwsA(isA<LibraryMutationUnavailable>()),
        );
      });

      expect(await reviewRows(), before);
      final stored = await repository.getBySongId('song_review_repo');
      expect(stored!.isResolved, isFalse);
    });

    test('create and save work when no restore is active', () async {
      final repository = await coordinated();
      final resolvedAt = now.add(const Duration(hours: 1));

      await repository.create(review());
      await repository.save(
        review().copyWith(resolvedAt: resolvedAt, updatedAt: resolvedAt),
      );

      final stored = await repository.getBySongId('song_review_repo');
      expect(stored!.resolvedAt, resolvedAt);
      expect(stored.reasons, const [ImportReviewReason.missingDuration]);
      expect(appDatabase.mutationCoordinator.activeMutations, 0);
    });
  });
}
