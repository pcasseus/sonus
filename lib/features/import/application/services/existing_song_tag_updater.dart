import 'package:sqflite/sqflite.dart';

import '../../../../core/identity/entity_id.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../../../library/data/daos/album_edition_track_dao.dart';
import '../../../library/data/daos/metadata_field_state_dao.dart';
import '../../../library/data/daos/song_dao.dart';
import '../../../library/data/repositories/sqlite_album_edition_track_repository.dart';
import '../../../library/data/repositories/sqlite_metadata_field_state_repository.dart';
import '../../../library/data/repositories/sqlite_song_repository.dart';
import '../../../library/domain/entities/album_edition_track.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../../library/domain/metadata/metadata_fields.dart';
import '../../../library/domain/services/metadata_authority_policy.dart';
import '../../../sync/data/daos/local_sync_dao.dart';
import '../../../sync/data/repositories/sqlite_local_sync_repository.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/models/resolved_metadata.dart';
import '../identity/import_identity_metadata_normalizer.dart';
import '../metadata/track_title_version_interpreter.dart';

/// Brings an existing song up to date with its file's changed tags (App
/// Update 1.2, BUG-09), keeping its Song ID and everything attached to it.
///
/// Each field changes only where the existing field-state contract allows
/// a tag to replace it (MetadataAuthorityPolicy): over a value that came
/// from a tag or a file name, or over no value at all. A value someone set
/// in Sonus (manual), confirmed in review or took from MusicBrainz is kept,
/// and so is a value with no recorded authority (it would need review). A
/// track position set by hand (manual numbering) is kept too.
///
/// Fields: title and its version label and characteristics, track and
/// disc number. Artist, album and edition are not moved by a tag change.
class ExistingSongTagUpdater {
  const ExistingSongTagUpdater({this.userId});

  /// The account the change is recorded for in sync, if any.
  final String? userId;

  /// Applies [metadata] to [songId]; whether anything changed. Writing the
  /// same tags again changes nothing.
  Future<bool> apply(
    DatabaseExecutor txn, {
    required String songId,
    required ResolvedMetadata metadata,
    required DateTime now,
    ImportCandidate? candidate,
  }) async {
    final songs = SqliteSongRepository(SongDao(txn));
    final states = SqliteMetadataFieldStateRepository(
      MetadataFieldStateDao(txn),
    );
    final song = await songs.getById(songId);
    if (song == null) return false;

    final tags = candidate == null
        ? metadata.metadata
        : const ImportIdentityMetadataNormalizer().normalize(
            candidate: candidate,
            metadata: metadata.metadata,
          );
    final title = const TrackTitleVersionInterpreter().interpret(tags.title);
    final origins = metadata.origins;

    Future<bool> allowed(
      String field,
      ImportMetadataFieldSource? origin, {
      required bool hasValue,
    }) async {
      final existing = await states.get(
        entityType: MetadataEntityType.song,
        entityId: songId,
        fieldName: field,
      );
      return MetadataAuthorityPolicy.canAutomaticallyReplace(
        existingValuePresent: hasValue,
        existing: existing,
        incomingAuthority: _authority(origin, metadata.source),
      );
    }

    final changedFields = <String, ImportMetadataFieldSource?>{};
    var updated = song;

    if (title.title.trim().isNotEmpty &&
        title.title != song.title &&
        await allowed(
          MetadataFields.songTitle,
          origins?.title,
          hasValue: song.title.trim().isNotEmpty,
        )) {
      updated = updated.copyWith(
        title: title.title,
        canonicalTitle: TextNormalizer.canonicalize(title.title),
      );
      changedFields[MetadataFields.songTitle] = origins?.title;

      if (title.versionLabel != song.versionLabel &&
          await allowed(
            MetadataFields.songVersionLabel,
            origins?.title,
            hasValue: song.versionLabel?.trim().isNotEmpty ?? false,
          )) {
        updated = updated.copyWith(versionLabel: title.versionLabel);
        changedFields[MetadataFields.songVersionLabel] = origins?.title;
      }
      if (!_sameList(
            title.versionCharacteristics,
            song.versionCharacteristics,
          ) &&
          await allowed(
            MetadataFields.songVersionCharacteristics,
            origins?.title,
            hasValue: song.versionCharacteristics.isNotEmpty,
          )) {
        updated = updated.copyWith(
          versionCharacteristics: title.versionCharacteristics,
        );
        changedFields[MetadataFields.songVersionCharacteristics] =
            origins?.title;
      }
    }

    if (tags.trackNumber > 0 &&
        tags.trackNumber != song.trackNumber &&
        await allowed(
          MetadataFields.songTrackNumber,
          origins?.trackNumber,
          hasValue: song.trackNumber > 0,
        )) {
      updated = updated.copyWith(trackNumber: tags.trackNumber);
      changedFields[MetadataFields.songTrackNumber] = origins?.trackNumber;
    }

    if (tags.discNumber > 0 &&
        tags.discNumber != song.discNumber &&
        await allowed(
          MetadataFields.songDiscNumber,
          origins?.discNumber,
          hasValue: song.discNumber > 0,
        )) {
      updated = updated.copyWith(discNumber: tags.discNumber);
      changedFields[MetadataFields.songDiscNumber] = origins?.discNumber;
    }

    final movedOnEdition = await _renumberOnEdition(
      txn,
      song: song,
      updated: updated,
      now: now,
    );

    if (changedFields.isEmpty && !movedOnEdition) return false;

    if (changedFields.isNotEmpty) {
      await songs.save(updated.copyWith(updatedAt: now));
      for (final MapEntry(key: field, value: origin) in changedFields.entries) {
        await states.save(
          MetadataFieldState(
            entityType: MetadataEntityType.song,
            entityId: songId,
            fieldName: field,
            authority: _authority(origin, metadata.source),
            source: _provenance(origin, metadata.source),
            updatedAt: now,
          ),
        );
      }
    }

    final syncUser = userId?.trim();
    if (syncUser != null && syncUser.isNotEmpty) {
      await SqliteLocalSyncRepository(
        dao: LocalSyncDao(txn),
        generateId: EntityId.syncOutbox,
        now: () => now,
      ).recordUpsert(
        userId: syncUser,
        entityType: CloudDataEntity.song,
        entityId: songId,
      );
    }
    return true;
  }

  /// Moves the song to its new number on its own edition, unless that
  /// listing was numbered by hand.
  Future<bool> _renumberOnEdition(
    DatabaseExecutor txn, {
    required Song song,
    required Song updated,
    required DateTime now,
  }) async {
    if (updated.trackNumber == song.trackNumber &&
        updated.discNumber == song.discNumber) {
      return false;
    }
    final memberships = SqliteAlbumEditionTrackRepository(
      AlbumEditionTrackDao(txn),
    );
    for (final membership in await memberships.getBySongId(song.id)) {
      if (membership.albumEditionId != song.albumEditionId ||
          membership.numberingAuthority !=
              AlbumEditionTrackAuthority.inferred) {
        continue;
      }
      if (membership.trackNumber == updated.trackNumber &&
          membership.discNumber == updated.discNumber) {
        return false;
      }
      await memberships.save(
        membership.copyWith(
          trackNumber: updated.trackNumber,
          discNumber: updated.discNumber,
          updatedAt: now,
        ),
      );
      return true;
    }
    return false;
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

  static MetadataProvenanceSource _provenance(
    ImportMetadataFieldSource? origin,
    MetadataSource source,
  ) => _authority(origin, source) == MetadataAuthority.imported
      ? MetadataProvenanceSource.embeddedTag
      : MetadataProvenanceSource.filename;

  static bool _sameList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
