import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../../../library/application/services/track_profile_editing_service.dart';
import '../../../library/data/daos/album_dao.dart';
import '../../../library/data/daos/album_edition_dao.dart';
import '../../../library/data/daos/album_edition_track_dao.dart';
import '../../../library/data/daos/artist_dao.dart';
import '../../../library/data/daos/metadata_field_state_dao.dart';
import '../../../library/data/daos/song_dao.dart';
import '../../../library/data/repositories/sqlite_album_edition_repository.dart';
import '../../../library/data/repositories/sqlite_album_edition_track_repository.dart';
import '../../../library/data/repositories/sqlite_album_repository.dart';
import '../../../library/data/repositories/sqlite_artist_repository.dart';
import '../../../library/data/repositories/sqlite_metadata_field_state_repository.dart';
import '../../../library/data/repositories/sqlite_song_repository.dart';
import '../../../library/domain/entities/album_edition_track.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../../library/domain/metadata/metadata_fields.dart';
import '../../../library/domain/services/metadata_authority_policy.dart';
import '../../../sync/data/repositories/sync_mutation_transaction_runner.dart';
import '../../data/daos/song_import_review_dao.dart';
import '../../data/repositories/sqlite_song_import_review_repository.dart';
import '../../domain/entities/song_import_review.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/models/resolved_metadata.dart';
import '../identity/import_identity_metadata_normalizer.dart';
import '../identity/library_identity_resolver.dart';
import '../metadata/track_title_version_interpreter.dart';

/// What came of a file's new artist, album or edition tags.
enum ReleaseMoveOutcome {
  /// The tags name the song's own artist, album and edition.
  unchanged,

  /// The song now belongs where its tags say; Song ID and history kept.
  moved,

  /// The song was not moved; it waits in Import Review (the tags name a
  /// release that is ambiguous or not in the library yet, or a value set
  /// or confirmed in Sonus).
  needsReview,
}

/// Moves an existing song to the artist, album and edition its file's tags
/// now name (App Update 1.2, BUG-09 Refinement A), keeping its Song ID and
/// so its plays, charts, playlists, Moments and sync record.
///
/// Conservative by design:
/// - the target is found with the importer's own identity resolution
///   (LibraryIdentityResolver); an ambiguous match is never guessed;
/// - only a target already in the library is moved to. Tags naming an
///   artist, album or edition the library does not have may mean the
///   release itself was renamed, so the user decides;
/// - each changed field must be replaceable by a tag under the field-state
///   contract (MetadataAuthorityPolicy); one value set or confirmed in Sonus
///   stops the whole move, so a song is never left half moved;
/// - the move itself is the track editor's (TrackProfileEditingService):
///   moving to another album removes the song's listings on the old one,
///   and moving to another edition of the same album removes the old
///   edition's listing when that listing came from tags;
/// - nothing is merged and nothing is deleted.
class ExistingSongReleaseMover {
  ExistingSongReleaseMover({required this.appDatabase, this.userId});

  final AppDatabase appDatabase;
  final String? userId;

  Future<ReleaseMoveOutcome> apply({
    required String songId,
    required ResolvedMetadata metadata,
    required ImportCandidate candidate,
    required DateTime now,
  }) async {
    final db = await appDatabase.database;
    final song = await SqliteSongRepository(SongDao(db)).getById(songId);
    if (song == null) return ReleaseMoveOutcome.unchanged;

    const normalizer = ImportIdentityMetadataNormalizer();
    var tags = normalizer.normalize(
      candidate: candidate,
      metadata: metadata.metadata,
    );
    // The importer's own reading of an ambiguous "A & B" credit: the album
    // artist is the primary artist (see AtomicLibraryImporter).
    if (normalizer.ambiguousSeparatorArtistCredit(
              candidate: candidate,
              metadata: metadata.metadata,
            ) !=
            null &&
        tags.effectiveAlbumArtistName.trim().isNotEmpty) {
      tags = tags.copyWith(artistName: tags.effectiveAlbumArtistName.trim());
    }

    // Tags still naming the song's own artist and album (or one of its
    // editions) are no reason to move it, whatever else the resolver might
    // pick: a folder's album (SN-45) may be titled apart from its tags.
    if (await _tagsNameCurrentRelease(
      db,
      song,
      tags.artistName,
      tags.albumTitle,
    )) {
      return ReleaseMoveOutcome.unchanged;
    }

    final title = const TrackTitleVersionInterpreter().interpret(tags.title);
    final match =
        await LibraryIdentityResolver(
          artistRepository: SqliteArtistRepository(ArtistDao(db)),
          albumRepository: SqliteAlbumRepository(AlbumDao(db)),
          albumEditionRepository: SqliteAlbumEditionRepository(
            AlbumEditionDao(db),
          ),
          songRepository: SqliteSongRepository(SongDao(db)),
        ).resolve(
          tags.copyWith(title: title.title),
          versionLabel: title.versionLabel,
          versionCharacteristics: title.versionCharacteristics,
        );

    final artist = match.artist;
    final album = match.album;
    final edition = match.edition;

    // Nothing named anew: the song is where its tags say.
    if (artist?.id == song.artistId &&
        album?.id == song.albumId &&
        edition?.id == song.albumEditionId) {
      return ReleaseMoveOutcome.unchanged;
    }

    if (match.artistAmbiguous ||
        match.albumArtistAmbiguous ||
        match.albumAmbiguous ||
        match.editionAmbiguous ||
        artist == null ||
        album == null ||
        edition == null) {
      return _review(db, song, now);
    }

    final origins = metadata.origins;
    final changes = <String, ImportMetadataFieldSource?>{
      if (artist.id != song.artistId)
        MetadataFields.songArtist: origins?.artistName,
      if (album.id != song.albumId)
        MetadataFields.songAlbum: origins?.albumTitle,
      if (edition.id != song.albumEditionId)
        MetadataFields.songAlbumEdition: origins?.albumTitle,
    };
    final states = SqliteMetadataFieldStateRepository(
      MetadataFieldStateDao(db),
    );
    for (final MapEntry(key: field, value: origin) in changes.entries) {
      final allowed = MetadataAuthorityPolicy.canAutomaticallyReplace(
        existingValuePresent: true,
        existing: await states.get(
          entityType: MetadataEntityType.song,
          entityId: songId,
          fieldName: field,
        ),
        incomingAuthority: _authority(origin, metadata.source),
      );
      if (!allowed) return _review(db, song, now);
    }

    final previousEditionListing =
        (await SqliteAlbumEditionTrackRepository(
          AlbumEditionTrackDao(db),
        ).getBySongId(songId)).where(
          (m) => m.albumEditionId == song.albumEditionId,
        );

    final authority = _authority(null, metadata.source);
    await TrackProfileEditingService(
          mutationRunner: SyncMutationTransactionRunner(
            appDatabase: appDatabase,
          ),
        )
        .withMetadataProvenance(
          authority: authority,
          source: authority == MetadataAuthority.imported
              ? MetadataProvenanceSource.embeddedTag
              : MetadataProvenanceSource.filename,
        )
        .updateTrack(
          userId: userId,
          songId: songId,
          title: song.title,
          trackNumber: song.trackNumber,
          discNumber: song.discNumber,
          featuredArtists: song.featuredArtists,
          isSingle: song.isSingle,
          artistId: artist.id,
          albumId: album.id,
          albumEditionId: edition.id,
          now: now,
        );

    // Within one album the editor keeps the old edition's listing; one that
    // came from tags is the file's old place, so it does not stay behind.
    if (album.id == song.albumId && edition.id != song.albumEditionId) {
      for (final listing in previousEditionListing) {
        if (listing.numberingAuthority != AlbumEditionTrackAuthority.inferred ||
            listing.orderingAuthority != AlbumEditionTrackAuthority.inferred) {
          continue;
        }
        await appDatabase.transaction(
          (txn) => SqliteAlbumEditionTrackRepository(
            AlbumEditionTrackDao(txn),
          ).delete(editionId: listing.albumEditionId, songId: songId),
        );
      }
    }
    return ReleaseMoveOutcome.moved;
  }

  /// Whether [artistName] is the song's artist and [albumTitle] its album's
  /// title or the title of the edition it is on.
  Future<bool> _tagsNameCurrentRelease(
    DatabaseExecutor db,
    Song song,
    String artistName,
    String albumTitle,
  ) async {
    final artist = await SqliteArtistRepository(
      ArtistDao(db),
    ).getById(song.artistId);
    final album = await SqliteAlbumRepository(
      AlbumDao(db),
    ).getById(song.albumId);
    final edition = await SqliteAlbumEditionRepository(
      AlbumEditionDao(db),
    ).getById(song.albumEditionId);
    if (artist == null || album == null) return false;

    final tagAlbum = TextNormalizer.canonicalize(albumTitle);
    return artist.canonicalName == TextNormalizer.canonicalize(artistName) &&
        (album.canonicalTitle == tagAlbum ||
            (edition != null &&
                TextNormalizer.canonicalize(edition.title) == tagAlbum));
  }

  /// Lists the song in Import Review, once, with why.
  Future<ReleaseMoveOutcome> _review(
    DatabaseExecutor db,
    Song song,
    DateTime now,
  ) async {
    final reviews = SqliteSongImportReviewRepository(
      SongImportReviewDao(db),
      appDatabase: appDatabase,
    );
    final existing = await reviews.getBySongId(song.id);
    if (existing == null) {
      await reviews.create(
        SongImportReview(
          songId: song.id,
          metadataSource: MetadataSource.embedded,
          reasons: const [ImportReviewReason.tagsNameAnotherRelease],
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else if (existing.resolvedAt != null ||
        !existing.reasons.contains(ImportReviewReason.tagsNameAnotherRelease)) {
      await reviews.save(
        existing.copyWith(
          reasons: List.unmodifiable({
            if (existing.resolvedAt == null) ...existing.reasons,
            ImportReviewReason.tagsNameAnotherRelease,
          }),
          resolvedAt: null,
          updatedAt: now,
        ),
      );
    }
    return ReleaseMoveOutcome.needsReview;
  }

  static MetadataAuthority _authority(
    ImportMetadataFieldSource? origin,
    MetadataSource source,
  ) => switch (origin) {
    ImportMetadataFieldSource.embedded => MetadataAuthority.imported,
    ImportMetadataFieldSource.fallback => MetadataAuthority.inferred,
    null =>
      source == MetadataSource.fallback
          ? MetadataAuthority.inferred
          : MetadataAuthority.imported,
  };
}
