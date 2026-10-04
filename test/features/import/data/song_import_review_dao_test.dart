import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/data/daos/song_import_review_dao.dart';
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

  Future<void> createSong(
    Database db, {
    required String suffix,
    required DateTime now,
  }) async {
    final artist = Artist(
      id: 'artist_$suffix',
      name: 'Artist $suffix',
      canonicalName: 'artist $suffix',
      createdAt: now,
      updatedAt: now,
    );

    final album = Album(
      id: 'album_$suffix',
      artistId: artist.id,
      title: 'Album $suffix',
      canonicalTitle: 'album $suffix',
      createdAt: now,
      updatedAt: now,
    );

    final edition = AlbumEdition(
      id: 'edition_$suffix',
      albumId: album.id,
      title: 'Album $suffix',
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: now,
      updatedAt: now,
    );

    final song = Song(
      id: 'song_$suffix',
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Song $suffix',
      canonicalTitle: 'song $suffix',
      trackNumber: 1,
      durationSeconds: 180,
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

  test('dao persists ambiguous artist credit review payload', () async {
    final db = await appDatabase.database;
    final dao = SongImportReviewDao(db);
    final now = DateTime.utc(2026, 10, 1, 12);

    await createSong(db, suffix: 'ambiguous_credit', now: now);

    final review = SongImportReview(
      songId: 'song_ambiguous_credit',
      metadataSource: MetadataSource.embedded,
      reasons: const [ImportReviewReason.ambiguousArtistCredit],
      payload: const ImportReviewPayload(
        rawArtistCredit: 'Megan Thee Stallion & Cardi B',
      ),
      createdAt: now,
      updatedAt: now,
    );

    await dao.insert(review);

    final restored = await dao.findBySongId(review.songId);

    expect(restored, isNotNull);
    expect(restored!.reasons, const [ImportReviewReason.ambiguousArtistCredit]);
    expect(restored.payload?.rawArtistCredit, 'Megan Thee Stallion & Cardi B');
    expect(restored.needsReview, isTrue);
  });
  test('dao inserts and restores complete review state', () async {
    final db = await appDatabase.database;
    final dao = SongImportReviewDao(db);
    final now = DateTime.utc(2026, 9, 17, 12);

    await createSong(db, suffix: 'roundtrip', now: now);

    final review = SongImportReview(
      songId: 'song_roundtrip',
      metadataSource: MetadataSource.fallback,
      reasons: const [
        ImportReviewReason.fallbackMetadata,
        ImportReviewReason.unknownAlbum,
        ImportReviewReason.missingDuration,
      ],
      createdAt: now,
      updatedAt: now,
    );

    await dao.insert(review);

    final restored = await dao.findBySongId(review.songId);

    expect(restored, isNotNull);
    expect(restored!.songId, review.songId);
    expect(restored.metadataSource, MetadataSource.fallback);
    expect(restored.reasons, const [
      ImportReviewReason.fallbackMetadata,
      ImportReviewReason.unknownAlbum,
      ImportReviewReason.missingDuration,
    ]);
    expect(restored.resolvedAt, isNull);
    expect(restored.createdAt, now);
    expect(restored.updatedAt, now);
  });

  test(
    'dao returns unresolved reviews in created order and counts them',
    () async {
      final db = await appDatabase.database;
      final dao = SongImportReviewDao(db);

      final firstAt = DateTime.utc(2026, 9, 17, 12);
      final secondAt = DateTime.utc(2026, 9, 17, 13);
      final thirdAt = DateTime.utc(2026, 9, 17, 14);

      await createSong(db, suffix: 'first', now: firstAt);
      await createSong(db, suffix: 'second', now: secondAt);
      await createSong(db, suffix: 'resolved', now: thirdAt);

      await dao.insert(
        SongImportReview(
          songId: 'song_second',
          metadataSource: MetadataSource.embedded,
          reasons: const [ImportReviewReason.missingTrackNumber],
          createdAt: secondAt,
          updatedAt: secondAt,
        ),
      );

      await dao.insert(
        SongImportReview(
          songId: 'song_first',
          metadataSource: MetadataSource.fallback,
          reasons: const [ImportReviewReason.fallbackMetadata],
          createdAt: firstAt,
          updatedAt: firstAt,
        ),
      );

      await dao.insert(
        SongImportReview(
          songId: 'song_resolved',
          metadataSource: MetadataSource.fallback,
          reasons: const [ImportReviewReason.unknownArtist],
          resolvedAt: thirdAt,
          createdAt: thirdAt,
          updatedAt: thirdAt,
        ),
      );

      final unresolved = await dao.findUnresolved();

      expect(unresolved.map((review) => review.songId).toList(), [
        'song_first',
        'song_second',
      ]);
      expect(await dao.countUnresolved(), 2);
    },
  );

  test('dao update can mark review resolved', () async {
    final db = await appDatabase.database;
    final dao = SongImportReviewDao(db);

    final createdAt = DateTime.utc(2026, 9, 17, 12);
    final resolvedAt = DateTime.utc(2026, 9, 17, 13);

    await createSong(db, suffix: 'resolve', now: createdAt);

    final review = SongImportReview(
      songId: 'song_resolve',
      metadataSource: MetadataSource.fallback,
      reasons: const [ImportReviewReason.fallbackMetadata],
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await dao.insert(review);

    await dao.update(
      review.copyWith(resolvedAt: resolvedAt, updatedAt: resolvedAt),
    );

    final restored = await dao.findBySongId(review.songId);

    expect(restored, isNotNull);
    expect(restored!.resolvedAt, resolvedAt);
    expect(restored.updatedAt, resolvedAt);
    expect(restored.isResolved, isTrue);
    expect(restored.needsReview, isFalse);
    expect(await dao.countUnresolved(), 0);
    expect(await dao.findUnresolved(), isEmpty);
  });

  test('dao update fails when review does not exist', () async {
    final db = await appDatabase.database;
    final dao = SongImportReviewDao(db);
    final now = DateTime.utc(2026, 9, 17, 12);

    final review = SongImportReview(
      songId: 'missing_song_review',
      metadataSource: MetadataSource.embedded,
      reasons: const [ImportReviewReason.missingDuration],
      createdAt: now,
      updatedAt: now,
    );

    await expectLater(dao.update(review), throwsA(isA<StateError>()));
  });
}
