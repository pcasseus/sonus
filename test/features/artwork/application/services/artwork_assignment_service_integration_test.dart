import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_assignment_service.dart';
import 'package:sonus_next/features/artwork/data/daos/artwork_asset_dao.dart';
import 'package:sonus_next/features/artwork/data/repositories/sqlite_artwork_asset_repository.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset_factory.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_artist_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/library/domain/services/metadata_field_state_service.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner mutationRunner;
  late ArtworkAssignmentService service;

  final originalTime = DateTime.utc(2026, 10, 7, 12);
  final assignTime = DateTime.utc(2026, 10, 7, 13);
  final clearTime = DateTime.utc(2026, 10, 7, 14);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    mutationRunner = SyncMutationTransactionRunner(appDatabase: appDatabase);

    final db = await appDatabase.database;

    service = ArtworkAssignmentService(
      artworkAssetRepository: SqliteArtworkAssetRepository(ArtworkAssetDao(db)),
      artistRepository: SqliteArtistRepository(ArtistDao(db)),
      albumEditionRepository: SqliteAlbumEditionRepository(AlbumEditionDao(db)),
      songRepository: SqliteSongRepository(SongDao(db)),
      mutationRunner: mutationRunner,
    );

    await _createLibraryGraph(appDatabase: appDatabase, now: originalTime);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test(
    'song artwork assignment persists asset entity and manual provenance',
    () async {
      final artwork = await service.assignSong(
        songId: 'song_artwork',
        filePath: r'C:\Artwork\Song Cover.jpg',
        now: assignTime,
      );

      final db = await appDatabase.database;

      final storedArtwork = await ArtworkAssetDao(db).findById(artwork.id);
      final storedSong = await SongDao(db).findById('song_artwork');

      final state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: 'song_artwork',
        fieldName: MetadataFields.songArtwork,
      );

      expect(storedArtwork, isNotNull);
      expect(storedArtwork!.id, artwork.id);

      expect(storedSong, isNotNull);
      expect(storedSong!.artworkId, artwork.id);
      expect(storedSong.updatedAt, assignTime);

      expect(state, isNotNull);
      expect(state!.authority, MetadataAuthority.manual);
      expect(state.source, MetadataProvenanceSource.user);
      expect(state.updatedAt, assignTime);
    },
  );

  test(
    'clearing song artwork persists null and refreshes manual provenance',
    () async {
      await service.assignSong(
        songId: 'song_artwork',
        filePath: r'C:\Artwork\Song Cover.jpg',
        now: assignTime,
      );

      await service.clearSong('song_artwork', now: clearTime);

      final db = await appDatabase.database;

      final storedSong = await SongDao(db).findById('song_artwork');

      final state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: 'song_artwork',
        fieldName: MetadataFields.songArtwork,
      );

      expect(storedSong, isNotNull);
      expect(storedSong!.artworkId, isNull);
      expect(storedSong.updatedAt, clearTime);

      expect(state, isNotNull);
      expect(state!.authority, MetadataAuthority.manual);
      expect(state.source, MetadataProvenanceSource.user);
      expect(state.updatedAt, clearTime);
    },
  );

  test(
    'album edition artwork assignment and clear persist manual provenance',
    () async {
      final artwork = await service.assignAlbumEdition(
        albumEditionId: 'edition_artwork',
        filePath: r'C:\Artwork\Album Cover.jpg',
        now: assignTime,
      );

      final db = await appDatabase.database;

      var storedEdition = await AlbumEditionDao(db).findById('edition_artwork');

      var state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.albumEdition,
        entityId: 'edition_artwork',
        fieldName: MetadataFields.editionArtwork,
      );

      expect(storedEdition, isNotNull);
      expect(storedEdition!.artworkId, artwork.id);
      expect(storedEdition.updatedAt, assignTime);

      expect(state, isNotNull);
      expect(state!.authority, MetadataAuthority.manual);
      expect(state.source, MetadataProvenanceSource.user);
      expect(state.updatedAt, assignTime);

      await service.clearAlbumEdition('edition_artwork', now: clearTime);

      storedEdition = await AlbumEditionDao(db).findById('edition_artwork');

      state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.albumEdition,
        entityId: 'edition_artwork',
        fieldName: MetadataFields.editionArtwork,
      );

      expect(storedEdition, isNotNull);
      expect(storedEdition!.artworkId, isNull);
      expect(storedEdition.updatedAt, clearTime);

      expect(state, isNotNull);
      expect(state!.authority, MetadataAuthority.manual);
      expect(state.source, MetadataProvenanceSource.user);
      expect(state.updatedAt, clearTime);
    },
  );

  test(
    'transaction rollback removes artwork entity mutation and provenance',
    () async {
      final rollbackTime = DateTime.utc(2026, 10, 7, 15);

      await expectLater(
        mutationRunner.run((context) async {
          final song = await context.songRepository.getById('song_artwork');

          expect(song, isNotNull);

          final artwork = ArtworkAssetFactory.create(
            filePath: r'C:\Artwork\Rollback.jpg',
            now: rollbackTime,
          );

          await context.artworkAssetRepository.create(artwork);

          await context.songRepository.save(
            song!.copyWith(artworkId: artwork.id, updatedAt: rollbackTime),
          );

          final metadataRepository = context.metadataFieldStateRepository;

          expect(metadataRepository, isNotNull);

          await MetadataFieldStateService(
            repository: metadataRepository!,
          ).record(
            entityType: MetadataEntityType.song,
            entityId: song.id,
            fieldName: MetadataFields.songArtwork,
            authority: MetadataAuthority.manual,
            source: MetadataProvenanceSource.user,
            updatedAt: rollbackTime,
          );

          throw StateError('Force artwork transaction rollback');
        }),
        throwsA(isA<StateError>()),
      );

      final db = await appDatabase.database;

      final storedSong = await SongDao(db).findById('song_artwork');

      expect(storedSong, isNotNull);
      expect(storedSong!.artworkId, isNull);
      expect(storedSong.updatedAt, originalTime);

      expect(
        await ArtworkAssetDao(
          db,
        ).findByNormalizedPath('c:/artwork/rollback.jpg'),
        isNull,
      );

      expect(
        await MetadataFieldStateDao(db).find(
          entityType: MetadataEntityType.song,
          entityId: 'song_artwork',
          fieldName: MetadataFields.songArtwork,
        ),
        isNull,
      );
    },
  );
}

Future<void> _createLibraryGraph({
  required AppDatabase appDatabase,
  required DateTime now,
}) async {
  final db = await appDatabase.database;

  final artist = Artist(
    id: 'artist_artwork',
    name: 'Artwork Artist',
    canonicalName: 'artwork artist',
    createdAt: now,
    updatedAt: now,
  );

  final album = Album(
    id: 'album_artwork',
    artistId: artist.id,
    title: 'Artwork Album',
    canonicalTitle: 'artwork album',
    createdAt: now,
    updatedAt: now,
  );

  final edition = AlbumEdition(
    id: 'edition_artwork',
    albumId: album.id,
    title: 'Artwork Album',
    type: AlbumEditionType.standard,
    isPrimary: true,
    createdAt: now,
    updatedAt: now,
  );

  final song = Song(
    id: 'song_artwork',
    artistId: artist.id,
    albumId: album.id,
    albumEditionId: edition.id,
    title: 'Artwork Song',
    canonicalTitle: 'artwork song',
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
