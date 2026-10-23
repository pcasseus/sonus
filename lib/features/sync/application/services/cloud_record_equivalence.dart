import '../../domain/models/cloud_records.dart';

/// Complete canonical comparison of two cloud records.
///
/// Every synchronized field takes part, including identity, ownership,
/// timestamps and tombstone state. Timestamps compare as UTC instants and
/// lists compare in order. Used to prove that a cloud row already holds
/// exactly the payload an outbound mutation intended to write.
abstract final class CloudRecordEquivalence {
  static bool isEquivalent(CloudOwnedRecord left, CloudOwnedRecord right) {
    final leftForm = canonicalForm(left);
    final rightForm = canonicalForm(right);

    return _deepEquals(leftForm, rightForm);
  }

  /// The full field set compared by [isEquivalent].
  static Map<String, Object?> canonicalForm(CloudOwnedRecord record) {
    final form = <String, Object?>{
      // Prefixed so it cannot collide with a record field such as an
      // edition's own type.
      r'$recordType': _typeName(record),
      'id': record.id,
      'userId': record.userId,
      'createdAt': _instant(record.createdAt),
      'updatedAt': _instant(record.updatedAt),
      'deletedAt': _instant(record.deletedAt),
    };

    switch (record) {
      case CloudArtistRecord():
        form.addAll({
          'name': record.name,
          'canonicalName': record.canonicalName,
          'headerArtworkId': record.headerArtworkId,
          'topArtistsArtworkId': record.topArtistsArtworkId,
          'metadataFieldStates': _states(record.metadataFieldStates),
        });

      case CloudAlbumRecord():
        form.addAll({
          'artistId': record.artistId,
          'title': record.title,
          'canonicalTitle': record.canonicalTitle,
          'metadataFieldStates': _states(record.metadataFieldStates),
        });

      case CloudAlbumEditionRecord():
        form.addAll({
          'albumId': record.albumId,
          'title': record.title,
          'type': record.type,
          'isPrimary': record.isPrimary,
          'releaseDate': _instant(record.releaseDate),
          'genre': record.genre,
          'artworkId': record.artworkId,
          'metadataFieldStates': _states(record.metadataFieldStates),
        });

      case CloudSongRecord():
        form.addAll({
          'artistId': record.artistId,
          'albumId': record.albumId,
          'albumEditionId': record.albumEditionId,
          'title': record.title,
          'canonicalTitle': record.canonicalTitle,
          'trackNumber': record.trackNumber,
          'discNumber': record.discNumber,
          'durationSeconds': record.durationSeconds,
          'isSingle': record.isSingle,
          'isBlocked': record.isBlocked,
          'featuredArtists': List<Object?>.of(record.featuredArtists),
          'versionLabel': record.versionLabel,
          'versionCharacteristics': List<Object?>.of(
            record.versionCharacteristics,
          ),
          'releaseStatus': record.releaseStatus,
          'isLeak': record.isLeak,
          'artworkId': record.artworkId,
          'metadataFieldStates': _states(record.metadataFieldStates),
        });

      case CloudArtworkAssetRecord():
        form.addAll({'storageObjectKey': record.storageObjectKey});

      default:
        throw ArgumentError.value(
          record,
          'record',
          'Unsupported cloud record type.',
        );
    }

    return form;
  }

  static String _typeName(CloudOwnedRecord record) {
    return switch (record) {
      CloudArtistRecord() => 'artist',
      CloudAlbumRecord() => 'album',
      CloudAlbumEditionRecord() => 'albumEdition',
      CloudSongRecord() => 'song',
      CloudArtworkAssetRecord() => 'artworkAsset',
      _ => throw ArgumentError.value(
        record,
        'record',
        'Unsupported cloud record type.',
      ),
    };
  }

  static int? _instant(DateTime? value) {
    return value?.toUtc().microsecondsSinceEpoch;
  }

  // Null (provenance never synced) differs from an explicit empty list.
  static List<Object?>? _states(List<CloudMetadataFieldState>? states) {
    if (states == null) {
      return null;
    }

    return [
      for (final state in states)
        <String, Object?>{
          'fieldName': state.fieldName,
          'authority': state.authority,
          'source': state.source,
          'sourceReference': state.sourceReference,
          'updatedAt': _instant(state.updatedAt),
        },
    ];
  }

  static bool _deepEquals(Object? left, Object? right) {
    if (left is Map<String, Object?> && right is Map<String, Object?>) {
      if (left.length != right.length) {
        return false;
      }

      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_deepEquals(entry.value, right[entry.key])) {
          return false;
        }
      }

      return true;
    }

    if (left is List<Object?> && right is List<Object?>) {
      if (left.length != right.length) {
        return false;
      }

      for (var index = 0; index < left.length; index++) {
        if (!_deepEquals(left[index], right[index])) {
          return false;
        }
      }

      return true;
    }

    return left == right;
  }
}
