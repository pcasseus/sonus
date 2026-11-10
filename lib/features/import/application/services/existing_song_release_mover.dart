import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
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
import '../../domain/models/import_scan_snapshot.dart';
import '../../domain/models/resolved_metadata.dart';
import '../folders/source_folder_key.dart';
import '../identity/import_identity_metadata_normalizer.dart';
import '../identity/library_identity_resolver.dart';
import '../metadata/track_title_version_interpreter.dart';

/// What came of a file's new artist, album or edition tags.
/// What a file's tags ask for its song (see ExistingSongReleaseMover).
class ReleaseMoveIntent {
  const ReleaseMoveIntent._({
    required this.song,
    required this.filePath,
    required this.artistId,
    required this.albumId,
    required this.editionId,
    required this.authority,
  }) : needsReview = false;

  ReleaseMoveIntent.review(this.song, this.filePath)
    : needsReview = true,
      artistId = song.artistId,
      albumId = song.albumId,
      editionId = song.albumEditionId,
      authority = MetadataAuthority.imported;

  final Song song;

  /// The file the tags were read from; its folder groups the release.
  final String filePath;

  /// Ambiguous, not in the library, or set or confirmed in Sonus.
  final bool needsReview;

  final String artistId;
  final String albumId;
  final String editionId;
  final MetadataAuthority authority;
}

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

  /// One file's tags, settled on their own (a decision in Import Review).
  Future<ReleaseMoveOutcome> apply({
    required String songId,
    required ResolvedMetadata metadata,
    required ImportCandidate candidate,
    required DateTime now,
  }) async {
    final intent = await evaluate(
      songId: songId,
      metadata: metadata,
      candidate: candidate,
    );
    if (intent == null) return ReleaseMoveOutcome.unchanged;
    final outcomes = await settle([intent], now: now);
    return outcomes[songId] ?? ReleaseMoveOutcome.unchanged;
  }

  /// What [candidate]'s tags ask for [songId]: nothing (null), Import
  /// Review, or a move to releases already in the library. Writes nothing.
  Future<ReleaseMoveIntent?> evaluate({
    required String songId,
    required ResolvedMetadata metadata,
    required ImportCandidate candidate,
  }) async {
    final db = await appDatabase.database;
    final song = await SqliteSongRepository(SongDao(db)).getById(songId);
    if (song == null) return null;

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
      return null;
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
      return null;
    }

    final review = ReleaseMoveIntent.review(song, candidate.filePath);
    if (match.artistAmbiguous ||
        match.albumArtistAmbiguous ||
        match.albumAmbiguous ||
        match.editionAmbiguous ||
        artist == null ||
        album == null ||
        edition == null) {
      return review;
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
      if (!allowed) return review;
    }

    return ReleaseMoveIntent._(
      song: song,
      filePath: candidate.filePath,
      artistId: artist.id,
      albumId: album.id,
      editionId: edition.id,
      authority: _authority(null, metadata.source),
    );
  }

  /// Settles a scan's intents together, so a release is never split
  /// silently (SN-45: a folder's songs stay together as one album).
  ///
  /// A move to another album or edition happens only when every playable
  /// song filed in the same folder on the same album (or edition) moves to
  /// the same place in this batch: the whole release was retagged. When one
  /// song of a folder is retagged on its own, or songs of one folder are
  /// retagged to different releases, the songs wait in Import Review and
  /// nothing moves. A change of track artist alone is not a split.
  Future<Map<String, ReleaseMoveOutcome>> settle(
    List<ReleaseMoveIntent> intents, {
    ImportScanSnapshot? scan,
    required DateTime now,
  }) async {
    final db = await appDatabase.database;
    final outcomes = <String, ReleaseMoveOutcome>{};
    final bySong = {for (final i in intents) i.song.id: i};

    for (final intent in intents) {
      if (intent.needsReview ||
          await _wouldSplitRelease(db, intent, bySong, scan)) {
        outcomes[intent.song.id] = await _review(db, intent.song, now);
      }
    }
    for (final intent in intents) {
      if (outcomes.containsKey(intent.song.id)) continue;
      await _move(intent, now);
      outcomes[intent.song.id] = ReleaseMoveOutcome.moved;
    }
    return outcomes;
  }

  /// Whether moving [intent]'s song would leave another playable song of
  /// its folder behind on the release it is leaving.
  Future<bool> _wouldSplitRelease(
    DatabaseExecutor db,
    ReleaseMoveIntent intent,
    Map<String, ReleaseMoveIntent> bySong,
    ImportScanSnapshot? scan,
  ) async {
    final song = intent.song;
    final leavesAlbum = intent.albumId != song.albumId;
    final leavesEdition = intent.editionId != song.albumEditionId;
    if (!leavesAlbum && !leavesEdition) return false;

    final folder = SourceFolderKey.of(intent.filePath);
    if (folder == null) return false; // no reliable folder: nothing grouped

    final rows = await db.rawQuery(
      'SELECT m.song_id, m.file_path, m.normalized_path, m.is_available, '
      'm.source_id, m.updated_at, s.album_edition_id '
      'FROM ${DatabaseTables.mediaFileBindings} m '
      'JOIN ${DatabaseTables.songs} s ON s.id = m.song_id '
      'WHERE s.album_id = ? AND m.song_id <> ?',
      [song.albumId, song.id],
    );
    for (final row in rows) {
      if (!ImportScanSnapshot.isLiveRow(row, scan)) continue;
      if (SourceFolderKey.of(row['file_path']! as String) != folder) continue;
      if (!leavesAlbum && row['album_edition_id'] != song.albumEditionId) {
        continue;
      }
      final sibling = bySong[row['song_id']! as String];
      if (sibling == null ||
          sibling.needsReview ||
          sibling.albumId != intent.albumId ||
          sibling.editionId != intent.editionId) {
        return true;
      }
    }
    return false;
  }

  Future<void> _move(ReleaseMoveIntent intent, DateTime now) async {
    final song = intent.song;
    final db = await appDatabase.database;
    final previousEditionListing =
        (await SqliteAlbumEditionTrackRepository(
              AlbumEditionTrackDao(db),
            ).getBySongId(song.id))
            .where((m) => m.albumEditionId == song.albumEditionId)
            .toList();

    await TrackProfileEditingService(
          mutationRunner: SyncMutationTransactionRunner(
            appDatabase: appDatabase,
          ),
        )
        .withMetadataProvenance(
          authority: intent.authority,
          source: intent.authority == MetadataAuthority.imported
              ? MetadataProvenanceSource.embeddedTag
              : MetadataProvenanceSource.filename,
        )
        .updateTrack(
          userId: userId,
          songId: song.id,
          title: song.title,
          trackNumber: song.trackNumber,
          discNumber: song.discNumber,
          featuredArtists: song.featuredArtists,
          isSingle: song.isSingle,
          artistId: intent.artistId,
          albumId: intent.albumId,
          albumEditionId: intent.editionId,
          now: now,
        );

    // Within one album the editor keeps the old edition's listing; one that
    // came from tags is the file's old place, so it does not stay behind.
    // Removed only once the move has succeeded.
    if (intent.albumId == song.albumId &&
        intent.editionId != song.albumEditionId) {
      for (final listing in previousEditionListing) {
        if (listing.numberingAuthority != AlbumEditionTrackAuthority.inferred ||
            listing.orderingAuthority != AlbumEditionTrackAuthority.inferred) {
          continue;
        }
        await appDatabase.transaction(
          (txn) => SqliteAlbumEditionTrackRepository(
            AlbumEditionTrackDao(txn),
          ).delete(editionId: listing.albumEditionId, songId: song.id),
        );
      }
    }
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
