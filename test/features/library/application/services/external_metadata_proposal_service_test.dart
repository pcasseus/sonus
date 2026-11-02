import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_proposal.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_proposal_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_repository.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_artist_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_metadata_field_state_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late ExternalMetadataProposalService service;

  final timestamp = DateTime.utc(2026, 10, 7);

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    final db = await database.database;

    service = ExternalMetadataProposalService(
      artistRepository: SqliteArtistRepository(ArtistDao(db)),
      albumRepository: SqliteAlbumRepository(AlbumDao(db)),
      albumEditionRepository: SqliteAlbumEditionRepository(AlbumEditionDao(db)),
      songRepository: SqliteSongRepository(SongDao(db)),
      metadataFieldStateRepository: SqliteMetadataFieldStateRepository(
        MetadataFieldStateDao(db),
      ),
    );

    await ArtistDao(db).insert(
      Artist(
        id: 'artist_1',
        name: 'Beyonce',
        canonicalName: 'beyonce',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );

    await AlbumDao(db).insert(
      Album(
        id: 'album_1',
        artistId: 'artist_1',
        title: 'Old Album',
        canonicalTitle: 'old album',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );

    await AlbumEditionDao(db).insert(
      AlbumEdition(
        id: 'edition_1',
        albumId: 'album_1',
        title: 'Standard',
        type: AlbumEditionType.standard,
        isPrimary: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );

    await SongDao(db).insert(
      Song(
        id: 'song_1',
        artistId: 'artist_1',
        albumId: 'album_1',
        albumEditionId: 'edition_1',
        title: 'Old Track',
        canonicalTitle: 'old track',
        trackNumber: 1,
        durationSeconds: 200,
        isSingle: false,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedState({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
    required MetadataAuthority authority,
    MetadataProvenanceSource source = MetadataProvenanceSource.embeddedTag,
    String? sourceReference,
  }) async {
    final db = await database.database;

    await MetadataFieldStateDao(db).upsert(
      MetadataFieldState(
        entityType: entityType,
        entityId: entityId,
        fieldName: fieldName,
        authority: authority,
        source: source,
        sourceReference: sourceReference,
        updatedAt: timestamp,
      ),
    );
  }

  ExternalMetadataCandidate artistCandidate(String name) =>
      ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.artist,
        providerEntityId: 'mb-artist-1',
        displayName: name,
      );

  ExternalMetadataCandidate albumCandidate(String title) =>
      ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: 'mb-album-1',
        displayName: title,
      );

  ExternalMetadataCandidate datedAlbumCandidate(ReleaseDate? date) =>
      ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: 'mb-album-1',
        displayName: 'Old Album',
        releaseDate: date,
      );

  Future<void> dateEdition(ReleaseDate date) async {
    final db = await database.database;
    final edition = await AlbumEditionDao(db).findById('edition_1');
    await AlbumEditionDao(db).update(edition!.withReleaseDate(date));
  }

  Future<ExternalMetadataProposalField> releaseDateField(
    ExternalMetadataCandidate candidate,
  ) async =>
      (await service.previewAlbum(
        albumId: 'album_1',
        candidate: candidate,
      )).fields.singleWhere(
        (field) => field.fieldName == MetadataFields.editionReleaseDate,
      );

  ExternalMetadataCandidate trackCandidate({
    String title = 'New Track',
    int? duration = 220,
  }) => ExternalMetadataCandidate(
    provider: ExternalMetadataProviderKind.musicBrainz,
    entityKind: ExternalMetadataEntityKind.track,
    providerEntityId: 'mb-track-1',
    displayName: title,
    durationSeconds: duration,
  );

  test('imported artist name proposes value change', () async {
    await seedState(
      entityType: MetadataEntityType.artist,
      entityId: 'artist_1',
      fieldName: MetadataFields.artistName,
      authority: MetadataAuthority.imported,
    );

    final proposal = await service.previewArtist(
      artistId: 'artist_1',
      candidate: artistCandidate('Beyoncé'),
    );

    expect(
      proposal.fields.single.status,
      ExternalMetadataProposalFieldStatus.valueChange,
    );
    expect(proposal.hasValueChanges, isTrue);
    expect(proposal.fields.single.currentValue, 'Beyonce');
    expect(proposal.fields.single.proposedValue, 'Beyoncé');
  });

  test('manual artist name remains protected', () async {
    await seedState(
      entityType: MetadataEntityType.artist,
      entityId: 'artist_1',
      fieldName: MetadataFields.artistName,
      authority: MetadataAuthority.manual,
    );

    final proposal = await service.previewArtist(
      artistId: 'artist_1',
      candidate: artistCandidate('Beyoncé'),
    );

    expect(
      proposal.fields.single.status,
      ExternalMetadataProposalFieldStatus.protected,
    );
    expect(proposal.hasProtectedFields, isTrue);
    expect(proposal.hasApplicableChanges, isFalse);
  });

  test('existing album title with unknown authority requires review', () async {
    final proposal = await service.previewAlbum(
      albumId: 'album_1',
      candidate: albumCandidate('New Album'),
    );

    expect(
      proposal.fields.first.status,
      ExternalMetadataProposalFieldStatus.reviewRequired,
    );
    expect(proposal.requiresReview, isTrue);
    expect(proposal.hasApplicableChanges, isFalse);
  });

  test(
    'identical album title with imported provenance upgrades source',
    () async {
      await seedState(
        entityType: MetadataEntityType.album,
        entityId: 'album_1',
        fieldName: MetadataFields.albumTitle,
        authority: MetadataAuthority.imported,
      );

      final proposal = await service.previewAlbum(
        albumId: 'album_1',
        candidate: albumCandidate('Old Album'),
      );

      expect(
        proposal.fields.first.status,
        ExternalMetadataProposalFieldStatus.provenanceOnly,
      );
      expect(proposal.hasValueChanges, isFalse);
      expect(proposal.hasProvenanceUpdates, isTrue);
    },
  );

  test('matching MusicBrainz provenance remains unchanged', () async {
    final candidate = albumCandidate('Old Album');

    await seedState(
      entityType: MetadataEntityType.album,
      entityId: 'album_1',
      fieldName: MetadataFields.albumTitle,
      authority: MetadataAuthority.external,
      source: MetadataProvenanceSource.musicBrainz,
      sourceReference: candidate.sourceReference,
    );

    final proposal = await service.previewAlbum(
      albumId: 'album_1',
      candidate: candidate,
    );

    expect(
      proposal.fields.first.status,
      ExternalMetadataProposalFieldStatus.unchanged,
    );
    expect(proposal.hasApplicableChanges, isFalse);
  });

  test('missing duration is not proposed', () async {
    await seedState(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: MetadataFields.songTitle,
      authority: MetadataAuthority.imported,
    );

    final proposal = await service.previewTrack(
      songId: 'song_1',
      candidate: trackCandidate(duration: null),
    );

    expect(proposal.fields, hasLength(2));
    expect(proposal.fields[1].fieldName, MetadataFields.songDuration);
    expect(
      proposal.fields[1].status,
      ExternalMetadataProposalFieldStatus.notProposed,
    );
  });

  test('imported track duration proposes numeric value change', () async {
    await seedState(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: MetadataFields.songTitle,
      authority: MetadataAuthority.imported,
    );

    await seedState(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: MetadataFields.songDuration,
      authority: MetadataAuthority.imported,
    );

    final proposal = await service.previewTrack(
      songId: 'song_1',
      candidate: trackCandidate(),
    );

    expect(
      proposal.fields[1].status,
      ExternalMetadataProposalFieldStatus.valueChange,
    );
    expect(proposal.fields[1].currentValue, 200);
    expect(proposal.fields[1].proposedValue, 220);
  });

  test('wrong candidate kind is rejected', () async {
    await expectLater(
      service.previewArtist(
        artistId: 'artist_1',
        candidate: albumCandidate('Wrong Kind'),
      ),
      throwsArgumentError,
    );
  });

  test('missing artist fails without creating an entity', () async {
    await expectLater(
      service.previewArtist(
        artistId: 'missing_artist',
        candidate: artistCandidate('New Artist'),
      ),
      throwsStateError,
    );
  });

  test('identical manual artist name is still protected', () async {
    await seedState(
      entityType: MetadataEntityType.artist,
      entityId: 'artist_1',
      fieldName: MetadataFields.artistName,
      authority: MetadataAuthority.manual,
    );

    final proposal = await service.previewArtist(
      artistId: 'artist_1',
      candidate: artistCandidate('Beyonce'),
    );

    expect(
      proposal.fields.single.status,
      ExternalMetadataProposalFieldStatus.protected,
    );
    expect(proposal.hasApplicableChanges, isFalse);
  });

  test('different MusicBrainz identity updates provenance only', () async {
    final candidate = albumCandidate('Old Album');

    await seedState(
      entityType: MetadataEntityType.album,
      entityId: 'album_1',
      fieldName: MetadataFields.albumTitle,
      authority: MetadataAuthority.external,
      source: MetadataProvenanceSource.musicBrainz,
      sourceReference: 'musicbrainz:album:previous-record',
    );

    final proposal = await service.previewAlbum(
      albumId: 'album_1',
      candidate: candidate,
    );

    expect(
      proposal.fields.first.status,
      ExternalMetadataProposalFieldStatus.provenanceOnly,
    );
    expect(proposal.hasValueChanges, isFalse);
    expect(proposal.hasProvenanceUpdates, isTrue);
  });

  test('blank MusicBrainz artist name is not proposed', () async {
    final proposal = await service.previewArtist(
      artistId: 'artist_1',
      candidate: artistCandidate('   '),
    );

    expect(
      proposal.fields.single.status,
      ExternalMetadataProposalFieldStatus.notProposed,
    );
    expect(proposal.fields.single.proposedValue, isNull);
    expect(proposal.hasApplicableChanges, isFalse);
  });

  test('zero-second MusicBrainz duration is not proposed', () async {
    final proposal = await service.previewTrack(
      songId: 'song_1',
      candidate: trackCandidate(duration: 0),
    );

    expect(
      proposal.fields[1].status,
      ExternalMetadataProposalFieldStatus.notProposed,
    );
    expect(proposal.fields[1].proposedValue, isNull);
  });
  test('preview does not persist changes or provenance', () async {
    await seedState(
      entityType: MetadataEntityType.artist,
      entityId: 'artist_1',
      fieldName: MetadataFields.artistName,
      authority: MetadataAuthority.imported,
    );

    await service.previewArtist(
      artistId: 'artist_1',
      candidate: artistCandidate('Beyoncé'),
    );

    final db = await database.database;
    final artist = await ArtistDao(db).findById('artist_1');
    final state = await MetadataFieldStateDao(db).find(
      entityType: MetadataEntityType.artist,
      entityId: 'artist_1',
      fieldName: MetadataFields.artistName,
    );

    expect(artist!.name, 'Beyonce');
    expect(state!.authority, MetadataAuthority.imported);
    expect(state.source, MetadataProvenanceSource.embeddedTag);

    final pending = await LocalSyncDao(db).findPending('user_1');
    expect(pending, isEmpty);
  });

  group('SN-49 release date', () {
    test('a year from a file tag is refined by MusicBrainz\'s day', () async {
      await dateEdition(ReleaseDate.of(2019)!);
      await seedState(
        entityType: MetadataEntityType.albumEdition,
        entityId: 'edition_1',
        fieldName: MetadataFields.editionReleaseDate,
        authority: MetadataAuthority.imported,
      );

      final field = await releaseDateField(
        datedAlbumCandidate(ReleaseDate.of(2019, 3, 15)),
      );

      expect(field.status, ExternalMetadataProposalFieldStatus.valueChange);
      expect(field.currentValue, ReleaseDate.of(2019));
      expect(field.proposedValue, ReleaseDate.of(2019, 3, 15));
    });

    test('a less exact form of the saved date is never proposed', () async {
      await dateEdition(ReleaseDate.of(2019, 3, 15)!);
      await seedState(
        entityType: MetadataEntityType.albumEdition,
        entityId: 'edition_1',
        fieldName: MetadataFields.editionReleaseDate,
        authority: MetadataAuthority.imported,
      );

      for (final partial in [ReleaseDate.of(2019), ReleaseDate.of(2019, 3)]) {
        final field = await releaseDateField(datedAlbumCandidate(partial));
        expect(field.status, ExternalMetadataProposalFieldStatus.unchanged);
        expect(field.willUpdateProvenance, isFalse);
      }
    });

    test('a missing date takes MusicBrainz\'s month', () async {
      final field = await releaseDateField(
        datedAlbumCandidate(ReleaseDate.of(2021, 5)),
      );

      expect(field.status, ExternalMetadataProposalFieldStatus.valueChange);
      expect(field.currentValue, isNull);
    });

    test('a date someone typed is protected', () async {
      await dateEdition(ReleaseDate.of(2018, 6)!);
      await seedState(
        entityType: MetadataEntityType.albumEdition,
        entityId: 'edition_1',
        fieldName: MetadataFields.editionReleaseDate,
        authority: MetadataAuthority.manual,
        source: MetadataProvenanceSource.user,
      );

      final field = await releaseDateField(
        datedAlbumCandidate(ReleaseDate.of(2019, 3, 15)),
      );

      expect(field.status, ExternalMetadataProposalFieldStatus.protected);
    });

    test('the note says which date is proposed, and names edition dates '
        'that differ instead of mixing them in', () async {
      final field = await releaseDateField(
        ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.album,
          providerEntityId: 'mb-album-1',
          displayName: 'Old Album',
          releaseDate: ReleaseDate.of(2021, 5),
          releaseOptions: [
            ExternalMetadataReleaseOption(
              releaseId: 'r-standard',
              title: 'Old Album',
              releaseDate: ReleaseDate.of(2021, 5),
            ),
            ExternalMetadataReleaseOption(
              releaseId: 'r-deluxe',
              title: 'Old Album (Deluxe)',
              releaseDate: ReleaseDate.of(2022, 3, 4),
            ),
          ],
        ),
      );

      expect(field.proposedValue, ReleaseDate.of(2021, 5));
      expect(
        field.note,
        'The first release of this album on MusicBrainz, for the "Standard" '
        'edition. MusicBrainz gives only the month. Other dates MusicBrainz '
        'lists for its editions (Old Album (Deluxe): March 4, 2022) are not '
        'used.',
      );
    });

    test('no MusicBrainz date proposes nothing', () async {
      final field = await releaseDateField(datedAlbumCandidate(null));

      expect(field.status, ExternalMetadataProposalFieldStatus.notProposed);
    });
  });
}
