import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_application_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late ExternalMetadataApplicationService service;

  final originalTime = DateTime.utc(2026, 10, 7, 12);
  final mutationTime = DateTime.utc(2026, 10, 7, 15);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutboxId = 0;

    service = ExternalMetadataApplicationService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'external_outbox_${++nextOutboxId}',
        now: () => mutationTime,
      ),
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<({Artist artist, Album album, AlbumEdition edition, Song song})>
  createGraph() async {
    final artist = Artist(
      id: 'artist_1',
      name: 'Beyonce',
      canonicalName: 'beyonce',
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final album = Album(
      id: 'album_1',
      artistId: 'artist_1',
      title: 'Old Album',
      canonicalTitle: 'old album',
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final edition = AlbumEdition(
      id: 'edition_1',
      albumId: album.id,
      title: 'Standard',
      type: AlbumEditionType.standard,
      isPrimary: true,
      releaseDate: DateTime.utc(2020, 1, 1),
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final song = Song(
      id: 'song_1',
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Old Track',
      canonicalTitle: 'old track',
      trackNumber: 1,
      durationSeconds: 200,
      isSingle: false,
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final db = await appDatabase.database;

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(album);
    await AlbumEditionDao(db).insert(edition);
    await SongDao(db).insert(song);

    return (artist: artist, album: album, edition: edition, song: song);
  }

  Future<void> seedState({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
    required MetadataAuthority authority,
  }) async {
    final db = await appDatabase.database;

    await MetadataFieldStateDao(db).upsert(
      MetadataFieldState(
        entityType: entityType,
        entityId: entityId,
        fieldName: fieldName,
        authority: authority,
        source: MetadataProvenanceSource.embeddedTag,
        updatedAt: originalTime,
      ),
    );
  }

  test('MusicBrainz artist replaces imported name and records MBID', () async {
    final graph = await createGraph();

    await seedState(
      entityType: MetadataEntityType.artist,
      entityId: graph.artist.id,
      fieldName: MetadataFields.artistName,
      authority: MetadataAuthority.imported,
    );

    final result = await service.applyArtistCandidate(
      userId: 'user_1',
      artistId: graph.artist.id,
      candidate: const ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.artist,
        providerEntityId: '859d0860-d480-4efd-970c-c05d5f1776b8',
        displayName: 'Beyoncé',
      ),
      now: mutationTime,
    );

    expect(result.changedFields, {MetadataFields.artistName});

    final db = await appDatabase.database;
    final stored = await ArtistDao(db).findById(graph.artist.id);

    expect(stored!.name, 'Beyoncé');

    final state = await MetadataFieldStateDao(db).find(
      entityType: MetadataEntityType.artist,
      entityId: graph.artist.id,
      fieldName: MetadataFields.artistName,
    );

    expect(state!.authority, MetadataAuthority.external);
    expect(state.source, MetadataProvenanceSource.musicBrainz);
    expect(
      state.sourceReference,
      'musicbrainz:artist:859d0860-d480-4efd-970c-c05d5f1776b8',
    );

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.artist);
  });

  test(
    'manual track title is protected while imported duration updates',
    () async {
      final graph = await createGraph();

      await seedState(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songTitle,
        authority: MetadataAuthority.manual,
      );

      await seedState(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songDuration,
        authority: MetadataAuthority.imported,
      );

      final result = await service.applyTrackCandidate(
        userId: 'user_1',
        songId: graph.song.id,
        candidate: const ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.track,
          providerEntityId: 'recording-mbid',
          displayName: 'MusicBrainz Track',
          durationSeconds: 224,
        ),
        now: mutationTime,
      );

      expect(result.protectedFields, {MetadataFields.songTitle});
      expect(result.changedFields, {MetadataFields.songDuration});

      final db = await appDatabase.database;
      final stored = await SongDao(db).findById(graph.song.id);

      expect(stored!.title, 'Old Track');
      expect(stored.durationSeconds, 224);

      final titleState = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songTitle,
      );

      final durationState = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songDuration,
      );

      expect(titleState!.authority, MetadataAuthority.manual);
      expect(durationState!.authority, MetadataAuthority.external);
      expect(durationState.source, MetadataProvenanceSource.musicBrainz);
      expect(
        durationState.sourceReference,
        'musicbrainz:recording:recording-mbid',
      );

      final pending = await LocalSyncDao(db).findPending('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.entityType, CloudDataEntity.song);
    },
  );

  test(
    'legacy field without provenance requires review and is not changed',
    () async {
      final graph = await createGraph();

      final result = await service.applyTrackCandidate(
        userId: 'user_1',
        songId: graph.song.id,
        candidate: const ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.track,
          providerEntityId: 'recording-mbid',
          displayName: 'Different Track',
        ),
        now: mutationTime,
      );

      expect(result.reviewRequiredFields, contains(MetadataFields.songTitle));

      final db = await appDatabase.database;
      final stored = await SongDao(db).findById(graph.song.id);

      expect(stored!.title, 'Old Track');
      expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
    },
  );

  test(
    'album applies release-group title without mutating edition date',
    () async {
      final graph = await createGraph();

      await seedState(
        entityType: MetadataEntityType.album,
        entityId: graph.album.id,
        fieldName: MetadataFields.albumTitle,
        authority: MetadataAuthority.imported,
      );

      final result = await service.applyAlbumCandidate(
        userId: 'user_1',
        albumId: graph.album.id,
        candidate: ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.album,
          providerEntityId: 'release-group-mbid',
          displayName: 'Renaissance',
          releaseDate: DateTime.utc(2022, 7, 29),
        ),
        now: mutationTime,
      );

      expect(result.changedFields, {MetadataFields.albumTitle});

      final db = await appDatabase.database;

      final album = await AlbumDao(db).findById(graph.album.id);
      final edition = await AlbumEditionDao(db).findById(graph.edition.id);

      expect(album!.title, 'Renaissance');
      expect(edition!.releaseDate, DateTime.utc(2020, 1, 1));

      final albumState = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.album,
        entityId: graph.album.id,
        fieldName: MetadataFields.albumTitle,
      );

      final editionState = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.albumEdition,
        entityId: graph.edition.id,
        fieldName: MetadataFields.editionReleaseDate,
      );
      expect(albumState!.authority, MetadataAuthority.external);
      expect(albumState.source, MetadataProvenanceSource.musicBrainz);
      expect(
        albumState.sourceReference,
        'musicbrainz:release-group:release-group-mbid',
      );

      expect(editionState, isNull);

      final pending = await LocalSyncDao(db).findPending('user_1');

      expect(pending.map((entry) => entry.entityType).toSet(), {
        CloudDataEntity.album,
      });
    },
  );

  test(
    'same accepted value upgrades provenance and queues parent sync',
    () async {
      final graph = await createGraph();

      await seedState(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songTitle,
        authority: MetadataAuthority.imported,
      );

      final result = await service.applyTrackCandidate(
        userId: 'user_1',
        songId: graph.song.id,
        candidate: const ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.track,
          providerEntityId: 'recording-mbid',
          displayName: 'Old Track',
        ),
        now: mutationTime,
      );

      expect(result.changedFields, isEmpty);
      expect(result.provenanceUpdatedFields, {MetadataFields.songTitle});

      final db = await appDatabase.database;

      final state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songTitle,
      );

      expect(state!.authority, MetadataAuthority.external);
      expect(state.source, MetadataProvenanceSource.musicBrainz);
      expect(state.sourceReference, 'musicbrainz:recording:recording-mbid');

      final pending = await LocalSyncDao(db).findPending('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.entityType, CloudDataEntity.song);
      expect(pending.single.entityId, graph.song.id);
    },
  );

  test('artist candidate rejects canonical identity collision', () async {
    final graph = await createGraph();

    await seedState(
      entityType: MetadataEntityType.artist,
      entityId: graph.artist.id,
      fieldName: MetadataFields.artistName,
      authority: MetadataAuthority.imported,
    );

    final db = await appDatabase.database;

    await ArtistDao(db).insert(
      Artist(
        id: 'artist_collision',
        name: 'Beyoncé',
        canonicalName: 'beyoncé',
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    await expectLater(
      service.applyArtistCandidate(
        userId: 'user_1',
        artistId: graph.artist.id,
        candidate: const ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.artist,
          providerEntityId: 'artist-mbid',
          displayName: 'Beyoncé',
        ),
        now: mutationTime,
      ),
      throwsA(
        isA<ExternalMetadataIdentityCollisionException>()
            .having((error) => error.entityId, 'entityId', graph.artist.id)
            .having(
              (error) => error.conflictingEntityId,
              'conflictingEntityId',
              'artist_collision',
            ),
      ),
    );

    final stored = await ArtistDao(db).findById(graph.artist.id);

    expect(stored, isNotNull);
    expect(stored!.name, 'Beyonce');
    expect(stored.canonicalName, 'beyonce');

    final state = await MetadataFieldStateDao(db).find(
      entityType: MetadataEntityType.artist,
      entityId: graph.artist.id,
      fieldName: MetadataFields.artistName,
    );

    expect(state, isNotNull);
    expect(state!.authority, MetadataAuthority.imported);
    expect(state.source, MetadataProvenanceSource.embeddedTag);
    expect(state.sourceReference, isNull);

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test(
    'outbox failure rolls back external entity and provenance mutation',
    () async {
      final graph = await createGraph();

      await seedState(
        entityType: MetadataEntityType.artist,
        entityId: graph.artist.id,
        fieldName: MetadataFields.artistName,
        authority: MetadataAuthority.imported,
      );

      await seedState(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songTitle,
        authority: MetadataAuthority.imported,
      );

      final collisionService = ExternalMetadataApplicationService(
        mutationRunner: SyncMutationTransactionRunner(
          appDatabase: appDatabase,
          generateId: () => 'fixed_external_outbox',
          now: () => mutationTime,
        ),
      );

      await collisionService.applyArtistCandidate(
        userId: 'user_1',
        artistId: graph.artist.id,
        candidate: const ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.artist,
          providerEntityId: 'artist-mbid',
          displayName: 'Beyoncé',
        ),
        now: mutationTime,
      );

      await expectLater(
        collisionService.applyTrackCandidate(
          userId: 'user_1',
          songId: graph.song.id,
          candidate: const ExternalMetadataCandidate(
            provider: ExternalMetadataProviderKind.musicBrainz,
            entityKind: ExternalMetadataEntityKind.track,
            providerEntityId: 'recording-mbid',
            displayName: 'Changed Track',
          ),
          now: mutationTime,
        ),
        throwsA(isA<DatabaseException>()),
      );

      final db = await appDatabase.database;

      final storedSong = await SongDao(db).findById(graph.song.id);

      expect(storedSong, isNotNull);
      expect(storedSong!.title, 'Old Track');
      expect(storedSong.canonicalTitle, 'old track');
      expect(storedSong.updatedAt, originalTime);

      final titleState = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songTitle,
      );

      expect(titleState, isNotNull);
      expect(titleState!.authority, MetadataAuthority.imported);
      expect(titleState.source, MetadataProvenanceSource.embeddedTag);
      expect(titleState.sourceReference, isNull);
      expect(titleState.updatedAt, originalTime);

      final pending = await LocalSyncDao(db).findPending('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.entityType, CloudDataEntity.artist);
      expect(pending.single.entityId, graph.artist.id);
    },
  );
}
