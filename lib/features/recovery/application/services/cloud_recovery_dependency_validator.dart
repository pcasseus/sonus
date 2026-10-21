import '../../../sync/domain/models/cloud_records.dart';
import '../models/cloud_recovery_dependency_issue.dart';

class CloudRecoveryDependencyValidator {
  const CloudRecoveryDependencyValidator();

  List<CloudRecoveryDependencyIssue> validate(
    Iterable<CloudOwnedRecord> records,
  ) {
    final all = records.toList(growable: false);

    final artists = <String, CloudArtistRecord>{};
    final albums = <String, CloudAlbumRecord>{};
    final editions = <String, CloudAlbumEditionRecord>{};
    final artwork = <String, CloudArtworkAssetRecord>{};
    final songs = <String, CloudSongRecord>{};

    final issues = <CloudRecoveryDependencyIssue>[];

    for (final record in all) {
      switch (record) {
        case CloudArtistRecord():
          _insert(artists, record);
        case CloudAlbumRecord():
          _insert(albums, record);
        case CloudAlbumEditionRecord():
          _insert(editions, record);
        case CloudArtworkAssetRecord():
          _insert(artwork, record);
        case CloudSongRecord():
          _insert(songs, record);
        default:
          throw StateError('Unsupported cloud record type.');
      }
    }

    void requireReference(
      CloudOwnedRecord owner,
      String field,
      String? referenceId,
      Map<String, CloudOwnedRecord> available,
    ) {
      if (owner.isDeleted || referenceId == null) return;

      final target = available[referenceId];

      if (target == null) {
        issues.add(
          CloudRecoveryDependencyIssue(
            kind: CloudRecoveryDependencyIssueKind.missingReference,
            entityId: owner.id,
            fieldName: field,
            referencedId: referenceId,
          ),
        );
      } else if (target.isDeleted) {
        issues.add(
          CloudRecoveryDependencyIssue(
            kind: CloudRecoveryDependencyIssueKind.deletedReference,
            entityId: owner.id,
            fieldName: field,
            referencedId: referenceId,
          ),
        );
      }
    }

    for (final record in all) {
      if (record.isDeleted) continue;

      switch (record) {
        case CloudArtistRecord():
          requireReference(
            record,
            'headerArtworkId',
            record.headerArtworkId,
            artwork,
          );
          requireReference(
            record,
            'topArtistsArtworkId',
            record.topArtistsArtworkId,
            artwork,
          );

        case CloudAlbumRecord():
          requireReference(record, 'artistId', record.artistId, artists);

        case CloudAlbumEditionRecord():
          requireReference(record, 'albumId', record.albumId, albums);
          requireReference(record, 'artworkId', record.artworkId, artwork);

        case CloudSongRecord():
          requireReference(record, 'artistId', record.artistId, artists);
          requireReference(record, 'albumId', record.albumId, albums);
          requireReference(
            record,
            'albumEditionId',
            record.albumEditionId,
            editions,
          );
          requireReference(record, 'artworkId', record.artworkId, artwork);

          final edition = editions[record.albumEditionId];

          if (edition != null &&
              !edition.isDeleted &&
              edition.albumId != record.albumId) {
            issues.add(
              CloudRecoveryDependencyIssue(
                kind: CloudRecoveryDependencyIssueKind.editionAlbumMismatch,
                entityId: record.id,
                fieldName: 'albumEditionId',
                referencedId: record.albumEditionId,
              ),
            );
          }

        case CloudArtworkAssetRecord():
          if (record.storageObjectKey.trim().isEmpty) {
            issues.add(
              CloudRecoveryDependencyIssue(
                kind: CloudRecoveryDependencyIssueKind.missingStorageKey,
                entityId: record.id,
                fieldName: 'storageObjectKey',
              ),
            );
          }

        default:
          throw StateError('Unsupported cloud record type.');
      }
    }

    return List.unmodifiable(issues);
  }

  void _insert<T extends CloudOwnedRecord>(Map<String, T> target, T record) {
    if (record.id.trim().isEmpty) {
      throw StateError('Cloud record ID must not be blank.');
    }

    if (target.containsKey(record.id)) {
      throw StateError('Duplicate cloud record ID: ${record.id}');
    }

    target[record.id] = record;
  }
}
