import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_application_service.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
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
    'explicit review confirmation applies legacy track title as confirmed review',
    () async {
      final graph = await createGraph();

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.track,
        providerEntityId: 'reviewed-recording-mbid',
        displayName: 'Reviewed Track',
      );

      final result = await service.confirmReviewedTrackCandidate(
        userId: 'user_1',
        songId: graph.song.id,
        candidate: candidate,
        confirmedFields: const {MetadataFields.songTitle},
        now: mutationTime,
      );

      expect(result.changedFields, {MetadataFields.songTitle});
      expect(result.reviewRequiredFields, isEmpty);

      final db = await appDatabase.database;

      final stored = await SongDao(db).findById(graph.song.id);

      expect(stored, isNotNull);
      expect(stored!.title, 'Reviewed Track');

      final state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songTitle,
      );

      expect(state, isNotNull);
      expect(state!.authority, MetadataAuthority.confirmed);
      expect(state.source, MetadataProvenanceSource.review);
      expect(state.sourceReference, candidate.sourceReference);
      expect(state.updatedAt, mutationTime);

      final pending = await LocalSyncDao(db).findPending('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.entityType, CloudDataEntity.song);
      expect(pending.single.entityId, graph.song.id);
    },
  );

  test(
    'review confirmation refuses field whose authority changed after preview',
    () async {
      final graph = await createGraph();

      await seedState(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songTitle,
        authority: MetadataAuthority.manual,
      );

      await expectLater(
        service.confirmReviewedTrackCandidate(
          userId: 'user_1',
          songId: graph.song.id,
          candidate: const ExternalMetadataCandidate(
            provider: ExternalMetadataProviderKind.musicBrainz,
            entityKind: ExternalMetadataEntityKind.track,
            providerEntityId: 'stale-review-recording',
            displayName: 'Should Not Apply',
          ),
          confirmedFields: const {MetadataFields.songTitle},
          now: mutationTime,
        ),
        throwsA(isA<StateError>()),
      );

      final db = await appDatabase.database;
      final stored = await SongDao(db).findById(graph.song.id);

      expect(stored!.title, 'Old Track');

      final state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songTitle,
      );

      expect(state!.authority, MetadataAuthority.manual);
      expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
    },
  );

  test(
    'explicit review confirmation can confirm legacy track duration',
    () async {
      final graph = await createGraph();

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.track,
        providerEntityId: 'reviewed-duration-recording',
        displayName: 'Old Track',
        durationSeconds: 224,
      );

      final result = await service.confirmReviewedTrackCandidate(
        userId: 'user_1',
        songId: graph.song.id,
        candidate: candidate,
        confirmedFields: const {MetadataFields.songDuration},
        now: mutationTime,
      );

      expect(result.changedFields, {MetadataFields.songDuration});

      final db = await appDatabase.database;
      final stored = await SongDao(db).findById(graph.song.id);

      expect(stored!.durationSeconds, 224);

      final state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: MetadataFields.songDuration,
      );

      expect(state!.authority, MetadataAuthority.confirmed);
      expect(state.source, MetadataProvenanceSource.review);
      expect(state.sourceReference, candidate.sourceReference);
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
          releaseDate: ReleaseDate.of(2022, 7, 29),
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

  test('reapplying identical MusicBrainz artist is a no-op', () async {
    final graph = await createGraph();

    await seedState(
      entityType: MetadataEntityType.artist,
      entityId: graph.artist.id,
      fieldName: MetadataFields.artistName,
      authority: MetadataAuthority.imported,
    );

    const candidate = ExternalMetadataCandidate(
      provider: ExternalMetadataProviderKind.musicBrainz,
      entityKind: ExternalMetadataEntityKind.artist,
      providerEntityId: 'artist-idempotency-mbid',
      displayName: 'Beyonce',
    );

    final first = await service.applyArtistCandidate(
      userId: 'user_1',
      artistId: graph.artist.id,
      candidate: candidate,
      now: mutationTime,
    );

    expect(first.changedFields, isEmpty);
    expect(first.provenanceUpdatedFields, {MetadataFields.artistName});

    final second = await service.applyArtistCandidate(
      userId: 'user_1',
      artistId: graph.artist.id,
      candidate: candidate,
      now: mutationTime.add(const Duration(hours: 1)),
    );

    expect(second.changedFields, isEmpty);
    expect(second.provenanceUpdatedFields, isEmpty);

    final db = await appDatabase.database;
    final state = await MetadataFieldStateDao(db).find(
      entityType: MetadataEntityType.artist,
      entityId: graph.artist.id,
      fieldName: MetadataFields.artistName,
    );

    expect(state!.authority, MetadataAuthority.external);
    expect(state.source, MetadataProvenanceSource.musicBrainz);
    expect(state.sourceReference, candidate.sourceReference);
    expect(state.updatedAt, mutationTime);
    expect(
      (await ArtistDao(db).findById(graph.artist.id))!.updatedAt,
      originalTime,
    );
    expect(await LocalSyncDao(db).findPending('user_1'), hasLength(1));
  });

  test('reapplying identical MusicBrainz album is a no-op', () async {
    final graph = await createGraph();

    await seedState(
      entityType: MetadataEntityType.album,
      entityId: graph.album.id,
      fieldName: MetadataFields.albumTitle,
      authority: MetadataAuthority.imported,
    );

    const candidate = ExternalMetadataCandidate(
      provider: ExternalMetadataProviderKind.musicBrainz,
      entityKind: ExternalMetadataEntityKind.album,
      providerEntityId: 'album-idempotency-mbid',
      displayName: 'Old Album',
    );

    final first = await service.applyAlbumCandidate(
      userId: 'user_1',
      albumId: graph.album.id,
      candidate: candidate,
      now: mutationTime,
    );

    expect(first.changedFields, isEmpty);
    expect(first.provenanceUpdatedFields, {MetadataFields.albumTitle});

    final second = await service.applyAlbumCandidate(
      userId: 'user_1',
      albumId: graph.album.id,
      candidate: candidate,
      now: mutationTime.add(const Duration(hours: 1)),
    );

    expect(second.changedFields, isEmpty);
    expect(second.provenanceUpdatedFields, isEmpty);

    final db = await appDatabase.database;
    final state = await MetadataFieldStateDao(db).find(
      entityType: MetadataEntityType.album,
      entityId: graph.album.id,
      fieldName: MetadataFields.albumTitle,
    );

    expect(state!.authority, MetadataAuthority.external);
    expect(state.source, MetadataProvenanceSource.musicBrainz);
    expect(state.sourceReference, candidate.sourceReference);
    expect(state.updatedAt, mutationTime);
    expect(
      (await AlbumDao(db).findById(graph.album.id))!.updatedAt,
      originalTime,
    );
    expect(await LocalSyncDao(db).findPending('user_1'), hasLength(1));
  });

  test('reapplying identical MusicBrainz track is a no-op', () async {
    final graph = await createGraph();

    await seedState(
      entityType: MetadataEntityType.song,
      entityId: graph.song.id,
      fieldName: MetadataFields.songTitle,
      authority: MetadataAuthority.imported,
    );

    await seedState(
      entityType: MetadataEntityType.song,
      entityId: graph.song.id,
      fieldName: MetadataFields.songDuration,
      authority: MetadataAuthority.imported,
    );

    const candidate = ExternalMetadataCandidate(
      provider: ExternalMetadataProviderKind.musicBrainz,
      entityKind: ExternalMetadataEntityKind.track,
      providerEntityId: 'track-idempotency-mbid',
      displayName: 'Old Track',
      durationSeconds: 200,
    );

    final first = await service.applyTrackCandidate(
      userId: 'user_1',
      songId: graph.song.id,
      candidate: candidate,
      now: mutationTime,
    );

    expect(first.changedFields, isEmpty);
    expect(first.provenanceUpdatedFields, {
      MetadataFields.songTitle,
      MetadataFields.songDuration,
    });

    final second = await service.applyTrackCandidate(
      userId: 'user_1',
      songId: graph.song.id,
      candidate: candidate,
      now: mutationTime.add(const Duration(hours: 1)),
    );

    expect(second.changedFields, isEmpty);
    expect(second.provenanceUpdatedFields, isEmpty);

    final db = await appDatabase.database;

    for (final field in [
      MetadataFields.songTitle,
      MetadataFields.songDuration,
    ]) {
      final state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: field,
      );

      expect(state!.authority, MetadataAuthority.external);
      expect(state.source, MetadataProvenanceSource.musicBrainz);
      expect(state.sourceReference, candidate.sourceReference);
      expect(state.updatedAt, mutationTime);
    }

    expect(
      (await SongDao(db).findById(graph.song.id))!.updatedAt,
      originalTime,
    );
    expect(await LocalSyncDao(db).findPending('user_1'), hasLength(1));
  });
  test('changing MusicBrainz recording ID updates provenance', () async {
    final graph = await createGraph();

    await seedState(
      entityType: MetadataEntityType.song,
      entityId: graph.song.id,
      fieldName: MetadataFields.songTitle,
      authority: MetadataAuthority.imported,
    );

    await seedState(
      entityType: MetadataEntityType.song,
      entityId: graph.song.id,
      fieldName: MetadataFields.songDuration,
      authority: MetadataAuthority.imported,
    );

    const originalCandidate = ExternalMetadataCandidate(
      provider: ExternalMetadataProviderKind.musicBrainz,
      entityKind: ExternalMetadataEntityKind.track,
      providerEntityId: 'recording-old',
      displayName: 'Old Track',
      durationSeconds: 200,
    );

    const correctedCandidate = ExternalMetadataCandidate(
      provider: ExternalMetadataProviderKind.musicBrainz,
      entityKind: ExternalMetadataEntityKind.track,
      providerEntityId: 'recording-corrected',
      displayName: 'Old Track',
      durationSeconds: 200,
    );

    await service.applyTrackCandidate(
      userId: 'user_1',
      songId: graph.song.id,
      candidate: originalCandidate,
      now: mutationTime,
    );

    final correctionTime = mutationTime.add(const Duration(hours: 1));

    final corrected = await service.applyTrackCandidate(
      userId: 'user_1',
      songId: graph.song.id,
      candidate: correctedCandidate,
      now: correctionTime,
    );

    expect(corrected.changedFields, isEmpty);
    expect(corrected.provenanceUpdatedFields, {
      MetadataFields.songTitle,
      MetadataFields.songDuration,
    });

    final db = await appDatabase.database;

    final storedSong = await SongDao(db).findById(graph.song.id);
    expect(storedSong!.title, 'Old Track');
    expect(storedSong.durationSeconds, 200);
    expect(storedSong.updatedAt, originalTime);

    for (final field in [
      MetadataFields.songTitle,
      MetadataFields.songDuration,
    ]) {
      final state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.song,
        entityId: graph.song.id,
        fieldName: field,
      );

      expect(state!.authority, MetadataAuthority.external);
      expect(state.source, MetadataProvenanceSource.musicBrainz);
      expect(state.sourceReference, correctedCandidate.sourceReference);
      expect(state.updatedAt, correctionTime);
    }

    final repeated = await service.applyTrackCandidate(
      userId: 'user_1',
      songId: graph.song.id,
      candidate: correctedCandidate,
      now: correctionTime.add(const Duration(hours: 1)),
    );

    expect(repeated.changedFields, isEmpty);
    expect(repeated.provenanceUpdatedFields, isEmpty);

    expect(await LocalSyncDao(db).findPending('user_1'), hasLength(1));
  });
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

  group('release classification from MusicBrainz', () {
    late SqliteLibraryOrganizationRepository organization;
    late ExternalMetadataApplicationService classifying;

    setUp(() {
      organization = SqliteLibraryOrganizationRepository(appDatabase);
      var nextOutboxId = 0;
      classifying = ExternalMetadataApplicationService(
        mutationRunner: SyncMutationTransactionRunner(
          appDatabase: appDatabase,
          generateId: () => 'classify_outbox_${++nextOutboxId}',
          now: () => mutationTime,
        ),
        organization: organization,
      );
    });

    ExternalMetadataCandidate releaseGroup(List<String> secondaryTypes) =>
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.album,
          providerEntityId: 'rg-1',
          displayName: 'Old Album',
          primaryType: 'Album',
          secondaryTypes: secondaryTypes,
        );

    test('a Soundtrack release group classifies the album', () async {
      final graph = await createGraph();

      await classifying.applyAlbumCandidate(
        userId: null,
        albumId: graph.album.id,
        candidate: releaseGroup(const ['Soundtrack']),
        now: mutationTime,
      );

      final classification = (await organization.getClassifications()).single;
      expect(classification.albumId, graph.album.id);
      expect(classification.kind, ReleaseKind.soundtrack);
      expect(classification.authority, ReleaseClassificationAuthority.external);
      expect(classification.sourceReference, contains('rg-1'));
    });

    test('SN-49: a Live soundtrack EP keeps all three facts', () async {
      final graph = await createGraph();

      await classifying.applyAlbumCandidate(
        userId: null,
        albumId: graph.album.id,
        candidate: ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.album,
          providerEntityId: 'rg-1',
          displayName: 'Old Album',
          primaryType: 'EP',
          secondaryTypes: const ['Soundtrack', 'Live'],
        ),
        now: mutationTime,
      );

      final live = (await organization.getLiveClassifications()).single;
      expect(live.isLive, isTrue);
      expect(live.authority, ReleaseClassificationAuthority.external);
      expect(live.sourceReference, contains('rg-1'));
      expect(
        (await organization.getClassifications()).single.kind,
        ReleaseKind.soundtrack,
      );
      expect((await organization.getFormats()).single.format, ReleaseFormat.ep);
    });

    test(
      "SN-49: the user's \"not live\" is kept; no type is no guess",
      () async {
        final graph = await createGraph();

        await classifying.applyAlbumCandidate(
          userId: null,
          albumId: graph.album.id,
          candidate: releaseGroup(const []),
          now: mutationTime,
        );
        expect(
          await organization.getLiveClassifications(),
          isEmpty,
          reason: 'only a Live type suggests Live; nothing is inferred',
        );

        await organization.saveLiveClassification(
          AlbumLiveClassification(
            albumId: graph.album.id,
            isLive: false,
            authority: ReleaseClassificationAuthority.manual,
            createdAt: originalTime,
            updatedAt: originalTime,
          ),
        );
        await classifying.applyAlbumCandidate(
          userId: null,
          albumId: graph.album.id,
          candidate: releaseGroup(const ['Live']),
          now: mutationTime,
        );

        final live = (await organization.getLiveClassifications()).single;
        expect(live.isLive, isFalse);
        expect(live.authority, ReleaseClassificationAuthority.manual);
      },
    );

    test('a plain album release group classifies nothing', () async {
      final graph = await createGraph();

      await classifying.applyAlbumCandidate(
        userId: null,
        albumId: graph.album.id,
        candidate: releaseGroup(const []),
        now: mutationTime,
      );

      expect(await organization.getClassifications(), isEmpty);
    });

    test("the user's own classification is never replaced", () async {
      final graph = await createGraph();
      await organization.saveClassification(
        AlbumReleaseClassification(
          albumId: graph.album.id,
          kind: ReleaseKind.castRecording,
          authority: ReleaseClassificationAuthority.manual,
          createdAt: originalTime,
          updatedAt: originalTime,
        ),
      );

      await classifying.applyAlbumCandidate(
        userId: null,
        albumId: graph.album.id,
        candidate: releaseGroup(const ['Compilation']),
        now: mutationTime,
      );

      final classification = (await organization.getClassifications()).single;
      expect(classification.kind, ReleaseKind.castRecording);
      expect(classification.authority, ReleaseClassificationAuthority.manual);
    });

    ExternalMetadataCandidate typed(String primaryType) =>
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.album,
          providerEntityId: 'rg-2',
          displayName: 'Old Album',
          primaryType: primaryType,
        );

    test('SN-45: a Single release group suggests the Single format', () async {
      final graph = await createGraph();

      await classifying.applyAlbumCandidate(
        userId: null,
        albumId: graph.album.id,
        candidate: typed('Single'),
        now: mutationTime,
      );

      final format = (await organization.getFormats()).single;
      expect(format.format, ReleaseFormat.single);
      expect(format.authority, ReleaseClassificationAuthority.external);
      expect(format.sourceReference, contains('rg-2'));
      expect(
        await organization.getClassifications(),
        isEmpty,
        reason: 'a format is not a classification',
      );
    });

    test('SN-45: a manual format is never replaced by a refresh', () async {
      final graph = await createGraph();
      await organization.saveFormat(
        AlbumReleaseFormat(
          albumId: graph.album.id,
          format: ReleaseFormat.single,
          authority: ReleaseClassificationAuthority.manual,
          createdAt: originalTime,
          updatedAt: originalTime,
        ),
      );

      for (final type in ['Album', 'EP']) {
        await classifying.applyAlbumCandidate(
          userId: null,
          albumId: graph.album.id,
          candidate: typed(type),
          now: mutationTime,
        );
      }

      final format = (await organization.getFormats()).single;
      expect(format.format, ReleaseFormat.single);
      expect(format.authority, ReleaseClassificationAuthority.manual);
    });

    test('SN-45: an unknown primary type states no format', () async {
      final graph = await createGraph();

      await classifying.applyAlbumCandidate(
        userId: null,
        albumId: graph.album.id,
        candidate: typed('Broadcast'),
        now: mutationTime,
      );

      expect(await organization.getFormats(), isEmpty);
    });
  });

  group('SN-49 release date from MusicBrainz', () {
    ExternalMetadataCandidate dated(ReleaseDate? date) =>
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.album,
          providerEntityId: 'release-group-mbid',
          displayName: 'Old Album',
          releaseDate: date,
        );

    Future<AlbumEdition> taggedYear(ReleaseDate date) async {
      final graph = await createGraph();
      final db = await appDatabase.database;
      await AlbumEditionDao(db).update(graph.edition.withReleaseDate(date));
      await seedState(
        entityType: MetadataEntityType.albumEdition,
        entityId: graph.edition.id,
        fieldName: MetadataFields.editionReleaseDate,
        authority: MetadataAuthority.imported,
      );
      return graph.edition;
    }

    test('a tagged year becomes MusicBrainz\'s exact day', () async {
      final edition = await taggedYear(ReleaseDate.of(2020)!);

      final result = await service.applyAlbumCandidate(
        userId: 'user_1',
        albumId: edition.albumId,
        candidate: dated(ReleaseDate.of(2020, 2, 14)),
        now: mutationTime,
      );

      expect(result.changedFields, contains(MetadataFields.editionReleaseDate));

      final db = await appDatabase.database;
      final saved = await AlbumEditionDao(db).findById(edition.id);
      expect(saved!.releaseDateValue, ReleaseDate.of(2020, 2, 14));
      expect(saved.releaseDatePrecision, ReleaseDatePrecision.day);

      final state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.albumEdition,
        entityId: edition.id,
        fieldName: MetadataFields.editionReleaseDate,
      );
      expect(state!.authority, MetadataAuthority.external);
      expect(state.source, MetadataProvenanceSource.musicBrainz);

      final pending = await LocalSyncDao(db).findPending('user_1');
      expect(
        pending
            .where((entry) => entry.entityType == CloudDataEntity.albumEdition)
            .map((entry) => entry.entityId),
        [edition.id],
      );
    });

    test('a month stays a month; no day is invented', () async {
      final edition = await taggedYear(ReleaseDate.of(2020)!);

      await service.applyAlbumCandidate(
        userId: 'user_1',
        albumId: edition.albumId,
        candidate: dated(ReleaseDate.of(2020, 2)),
        now: mutationTime,
      );

      final db = await appDatabase.database;
      final saved = await AlbumEditionDao(db).findById(edition.id);
      expect(saved!.releaseDateValue, ReleaseDate.of(2020, 2));
      expect(saved.releaseDateValue!.label, 'February 2020');
    });

    test('a less exact form of the saved date changes nothing', () async {
      final edition = await taggedYear(ReleaseDate.of(2020, 2, 14)!);

      final result = await service.applyAlbumCandidate(
        userId: 'user_1',
        albumId: edition.albumId,
        candidate: dated(ReleaseDate.of(2020)),
        now: mutationTime,
      );

      expect(
        result.changedFields,
        isNot(contains(MetadataFields.editionReleaseDate)),
      );
      expect(
        result.provenanceUpdatedFields,
        isNot(contains(MetadataFields.editionReleaseDate)),
      );

      final db = await appDatabase.database;
      final saved = await AlbumEditionDao(db).findById(edition.id);
      expect(saved!.releaseDateValue, ReleaseDate.of(2020, 2, 14));
      final state = await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.albumEdition,
        entityId: edition.id,
        fieldName: MetadataFields.editionReleaseDate,
      );
      expect(state!.authority, MetadataAuthority.imported);
    });

    test(
      'a date of unknown source waits for review, then is confirmed',
      () async {
        final graph = await createGraph();
        final candidate = dated(ReleaseDate.of(2021, 9));

        final applied = await service.applyAlbumCandidate(
          userId: 'user_1',
          albumId: graph.album.id,
          candidate: candidate,
          now: mutationTime,
        );
        expect(
          applied.reviewRequiredFields,
          contains(MetadataFields.editionReleaseDate),
        );

        final db = await appDatabase.database;
        expect(
          (await AlbumEditionDao(db).findById(graph.edition.id))!.releaseDate,
          DateTime.utc(2020, 1, 1),
        );

        final confirmed = await service.confirmReviewedAlbumCandidate(
          userId: 'user_1',
          albumId: graph.album.id,
          candidate: candidate,
          confirmedFields: {MetadataFields.editionReleaseDate},
          now: mutationTime,
        );

        expect(confirmed.changedFields, {MetadataFields.editionReleaseDate});
        final saved = await AlbumEditionDao(db).findById(graph.edition.id);
        expect(saved!.releaseDateValue, ReleaseDate.of(2021, 9));
        expect(saved.title, 'Standard');
        final album = await AlbumDao(db).findById(graph.album.id);
        expect(album!.title, 'Old Album');
        final state = await MetadataFieldStateDao(db).find(
          entityType: MetadataEntityType.albumEdition,
          entityId: graph.edition.id,
          fieldName: MetadataFields.editionReleaseDate,
        );
        expect(state!.authority, MetadataAuthority.confirmed);
      },
    );
  });
}
