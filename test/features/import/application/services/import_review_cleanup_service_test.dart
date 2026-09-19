import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/application/services/import_review_cleanup_service.dart';
import 'package:sonus_next/features/import/data/daos/song_import_review_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_song_import_review_repository.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SqliteSongImportReviewRepository reviewRepository;
  late SqliteSongRepository songRepository;

  final originalTime = DateTime.utc(2026, 9, 19, 12);
  final cleanupTime = DateTime.utc(2026, 9, 19, 14);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

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
  }) async {
    await reviewRepository.create(
      SongImportReview(
        songId: song.id,
        metadataSource: MetadataSource.fallback,
        reasons: List.unmodifiable(reasons),
        resolvedAt: resolvedAt,
        createdAt: originalTime,
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
}
