import '../../application/services/cloud_sync_reader.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/sync_data_contract.dart';
import '../contracts/supabase_sync_contract.dart';

abstract final class SupabaseCloudRecordMapper {
  static String tableFor(CloudOwnedRecord record) {
    return switch (record) {
      CloudArtistRecord() => SupabaseSyncContract.artistsTable,
      CloudAlbumRecord() => SupabaseSyncContract.albumsTable,
      CloudAlbumEditionRecord() => SupabaseSyncContract.albumEditionsTable,
      CloudSongRecord() => SupabaseSyncContract.songsTable,
      CloudArtworkAssetRecord() => SupabaseSyncContract.artworkAssetsTable,
      _ => throw ArgumentError.value(
        record,
        'record',
        'Unsupported cloud record type.',
      ),
    };
  }

  static String tableForEntity(CloudDataEntity entityType) {
    return switch (entityType) {
      CloudDataEntity.artist => SupabaseSyncContract.artistsTable,
      CloudDataEntity.album => SupabaseSyncContract.albumsTable,
      CloudDataEntity.albumEdition => SupabaseSyncContract.albumEditionsTable,
      CloudDataEntity.song => SupabaseSyncContract.songsTable,
      CloudDataEntity.artworkAsset => SupabaseSyncContract.artworkAssetsTable,
    };
  }

  static Map<String, dynamic> toRow(CloudOwnedRecord record) {
    final row = <String, dynamic>{
      SupabaseSyncContract.idColumn: record.id,
      SupabaseSyncContract.userIdColumn: record.userId,
      SupabaseSyncContract.createdAtColumn: record.createdAt
          .toUtc()
          .toIso8601String(),
      SupabaseSyncContract.updatedAtColumn: record.updatedAt
          .toUtc()
          .toIso8601String(),
      SupabaseSyncContract.deletedAtColumn: record.deletedAt
          ?.toUtc()
          .toIso8601String(),
    };

    switch (record) {
      case CloudArtistRecord():
        row.addAll({
          SupabaseSyncContract.nameColumn: record.name,
          SupabaseSyncContract.canonicalNameColumn: record.canonicalName,
          SupabaseSyncContract.isBlacklistedColumn: false,
          SupabaseSyncContract.headerArtworkIdColumn: record.headerArtworkId,
          SupabaseSyncContract.topArtistsArtworkIdColumn:
              record.topArtistsArtworkId,
          SupabaseSyncContract.metadataFieldStatesColumn:
              _metadataFieldStatesToJson(record.metadataFieldStates),
        });

      case CloudAlbumRecord():
        row.addAll({
          SupabaseSyncContract.artistIdColumn: record.artistId,
          SupabaseSyncContract.titleColumn: record.title,
          SupabaseSyncContract.canonicalTitleColumn: record.canonicalTitle,
          SupabaseSyncContract.metadataFieldStatesColumn:
              _metadataFieldStatesToJson(record.metadataFieldStates),
        });

      case CloudAlbumEditionRecord():
        row.addAll({
          SupabaseSyncContract.albumIdColumn: record.albumId,
          SupabaseSyncContract.titleColumn: record.title,
          SupabaseSyncContract.typeColumn: record.type,
          SupabaseSyncContract.isPrimaryColumn: record.isPrimary,
          SupabaseSyncContract.releaseDateColumn: record.releaseDate
              ?.toUtc()
              .toIso8601String(),
          SupabaseSyncContract.genreColumn: record.genre,
          SupabaseSyncContract.artworkIdColumn: record.artworkId,
          SupabaseSyncContract.metadataFieldStatesColumn:
              _metadataFieldStatesToJson(record.metadataFieldStates),
        });

      case CloudSongRecord():
        row.addAll({
          SupabaseSyncContract.artistIdColumn: record.artistId,
          SupabaseSyncContract.albumIdColumn: record.albumId,
          SupabaseSyncContract.albumEditionIdColumn: record.albumEditionId,
          SupabaseSyncContract.titleColumn: record.title,
          SupabaseSyncContract.canonicalTitleColumn: record.canonicalTitle,
          SupabaseSyncContract.trackNumberColumn: record.trackNumber,
          SupabaseSyncContract.discNumberColumn: record.discNumber,
          SupabaseSyncContract.durationSecondsColumn: record.durationSeconds,
          SupabaseSyncContract.isSingleColumn: record.isSingle,
          SupabaseSyncContract.isBlockedColumn: record.isBlocked,
          SupabaseSyncContract.featuredArtistsColumn: record.featuredArtists,
          SupabaseSyncContract.versionLabelColumn: record.versionLabel,
          SupabaseSyncContract.versionCharacteristicsColumn:
              record.versionCharacteristics,
          SupabaseSyncContract.releaseStatusColumn: record.releaseStatus,
          SupabaseSyncContract.isLeakColumn: record.isLeak,
          SupabaseSyncContract.artworkIdColumn: record.artworkId,
          SupabaseSyncContract.metadataFieldStatesColumn:
              _metadataFieldStatesToJson(record.metadataFieldStates),
          if (record.editionMemberships case final memberships?)
            SupabaseSyncContract.editionMembershipsColumn: [
              for (final membership in memberships)
                {
                  'album_edition_id': membership.albumEditionId,
                  'disc_number': membership.discNumber,
                  'track_number': membership.trackNumber,
                  'sort_position': membership.sortPosition,
                  'numbering_authority': membership.numberingAuthority,
                  'ordering_authority': membership.orderingAuthority,
                },
            ],
          if (record.artistCredits case final credits?)
            SupabaseSyncContract.artistCreditsColumn: [
              for (final credit in credits)
                {
                  'id': credit.id,
                  'artist_id': credit.artistId,
                  'credited_name': credit.creditedName,
                  'canonical_credited_name': credit.canonicalCreditedName,
                  'role': credit.role,
                  'position': credit.position,
                },
            ],
        });

      case CloudArtworkAssetRecord():
        row.addAll({
          SupabaseSyncContract.storageObjectKeyColumn: record.storageObjectKey,
        });

      default:
        throw ArgumentError.value(
          record,
          'record',
          'Unsupported cloud record type.',
        );
    }

    return row;
  }

  static CloudSyncItem fromRow({
    required CloudDataEntity entityType,
    required Map<String, dynamic> row,
  }) {
    final serverUpdatedAt = _requiredDateTime(
      row,
      SupabaseSyncContract.serverUpdatedAtColumn,
    );

    final record = switch (entityType) {
      CloudDataEntity.artist => _artistFromRow(row),
      CloudDataEntity.album => _albumFromRow(row),
      CloudDataEntity.albumEdition => _albumEditionFromRow(row),
      CloudDataEntity.song => _songFromRow(row),
      CloudDataEntity.artworkAsset => _artworkFromRow(row),
    };

    final serverRevision = _requiredInt(
      row,
      SupabaseSyncContract.serverRevisionColumn,
    );

    if (serverRevision < 1) {
      throw StateError('Invalid cloud server revision.');
    }

    return CloudSyncItem(
      record: record,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
    );
  }

  static CloudArtistRecord _artistFromRow(Map<String, dynamic> row) {
    return CloudArtistRecord(
      id: _requiredString(row, SupabaseSyncContract.idColumn),
      userId: _requiredString(row, SupabaseSyncContract.userIdColumn),
      name: _requiredString(row, SupabaseSyncContract.nameColumn),
      canonicalName: _requiredString(
        row,
        SupabaseSyncContract.canonicalNameColumn,
      ),
      headerArtworkId: _optionalString(
        row,
        SupabaseSyncContract.headerArtworkIdColumn,
      ),
      topArtistsArtworkId: _optionalString(
        row,
        SupabaseSyncContract.topArtistsArtworkIdColumn,
      ),
      metadataFieldStates: _metadataFieldStatesFromJson(row),
      createdAt: _requiredDateTime(row, SupabaseSyncContract.createdAtColumn),
      updatedAt: _requiredDateTime(row, SupabaseSyncContract.updatedAtColumn),
      deletedAt: _optionalDateTime(row, SupabaseSyncContract.deletedAtColumn),
    );
  }

  static CloudAlbumRecord _albumFromRow(Map<String, dynamic> row) {
    return CloudAlbumRecord(
      id: _requiredString(row, SupabaseSyncContract.idColumn),
      userId: _requiredString(row, SupabaseSyncContract.userIdColumn),
      artistId: _requiredString(row, SupabaseSyncContract.artistIdColumn),
      title: _requiredString(row, SupabaseSyncContract.titleColumn),
      canonicalTitle: _requiredString(
        row,
        SupabaseSyncContract.canonicalTitleColumn,
      ),
      metadataFieldStates: _metadataFieldStatesFromJson(row),
      createdAt: _requiredDateTime(row, SupabaseSyncContract.createdAtColumn),
      updatedAt: _requiredDateTime(row, SupabaseSyncContract.updatedAtColumn),
      deletedAt: _optionalDateTime(row, SupabaseSyncContract.deletedAtColumn),
    );
  }

  static CloudAlbumEditionRecord _albumEditionFromRow(
    Map<String, dynamic> row,
  ) {
    return CloudAlbumEditionRecord(
      id: _requiredString(row, SupabaseSyncContract.idColumn),
      userId: _requiredString(row, SupabaseSyncContract.userIdColumn),
      albumId: _requiredString(row, SupabaseSyncContract.albumIdColumn),
      title: _requiredString(row, SupabaseSyncContract.titleColumn),
      type: _requiredString(row, SupabaseSyncContract.typeColumn),
      isPrimary: _requiredBool(row, SupabaseSyncContract.isPrimaryColumn),
      releaseDate: _optionalDateTime(
        row,
        SupabaseSyncContract.releaseDateColumn,
      ),
      genre: _optionalString(row, SupabaseSyncContract.genreColumn),
      artworkId: _optionalString(row, SupabaseSyncContract.artworkIdColumn),
      metadataFieldStates: _metadataFieldStatesFromJson(row),
      createdAt: _requiredDateTime(row, SupabaseSyncContract.createdAtColumn),
      updatedAt: _requiredDateTime(row, SupabaseSyncContract.updatedAtColumn),
      deletedAt: _optionalDateTime(row, SupabaseSyncContract.deletedAtColumn),
    );
  }

  static CloudSongRecord _songFromRow(Map<String, dynamic> row) {
    return CloudSongRecord(
      id: _requiredString(row, SupabaseSyncContract.idColumn),
      userId: _requiredString(row, SupabaseSyncContract.userIdColumn),
      artistId: _requiredString(row, SupabaseSyncContract.artistIdColumn),
      albumId: _requiredString(row, SupabaseSyncContract.albumIdColumn),
      albumEditionId: _requiredString(
        row,
        SupabaseSyncContract.albumEditionIdColumn,
      ),
      title: _requiredString(row, SupabaseSyncContract.titleColumn),
      canonicalTitle: _requiredString(
        row,
        SupabaseSyncContract.canonicalTitleColumn,
      ),
      trackNumber: _requiredInt(row, SupabaseSyncContract.trackNumberColumn),
      discNumber: _intOrDefault(row, SupabaseSyncContract.discNumberColumn, 1),
      durationSeconds: _requiredInt(
        row,
        SupabaseSyncContract.durationSecondsColumn,
      ),
      isSingle: _requiredBool(row, SupabaseSyncContract.isSingleColumn),
      isBlocked: _boolOrDefault(
        row,
        SupabaseSyncContract.isBlockedColumn,
        false,
      ),
      featuredArtists: _requiredStringList(
        row,
        SupabaseSyncContract.featuredArtistsColumn,
      ),
      versionLabel: _optionalString(
        row,
        SupabaseSyncContract.versionLabelColumn,
      ),
      versionCharacteristics: _stringListOrDefault(
        row,
        SupabaseSyncContract.versionCharacteristicsColumn,
        const [],
      ),
      releaseStatus: _stringOrDefault(
        row,
        SupabaseSyncContract.releaseStatusColumn,
        'released',
      ),
      isLeak: _boolOrDefault(row, SupabaseSyncContract.isLeakColumn, false),
      artworkId: _optionalString(row, SupabaseSyncContract.artworkIdColumn),
      metadataFieldStates: _metadataFieldStatesFromJson(row),
      editionMemberships: _optionalObjectList(
        row,
        SupabaseSyncContract.editionMembershipsColumn,
        (item) => CloudEditionMembership(
          albumEditionId: _requiredString(item, 'album_edition_id'),
          discNumber: _requiredInt(item, 'disc_number'),
          trackNumber: _requiredInt(item, 'track_number'),
          sortPosition: _requiredInt(item, 'sort_position'),
          numberingAuthority: _requiredString(item, 'numbering_authority'),
          orderingAuthority: _requiredString(item, 'ordering_authority'),
        ),
      ),
      artistCredits: _optionalObjectList(
        row,
        SupabaseSyncContract.artistCreditsColumn,
        (item) => CloudSongCredit(
          id: _requiredString(item, 'id'),
          artistId: _optionalString(item, 'artist_id'),
          creditedName: _requiredString(item, 'credited_name'),
          canonicalCreditedName: _requiredString(
            item,
            'canonical_credited_name',
          ),
          role: _requiredString(item, 'role'),
          position: _requiredInt(item, 'position'),
        ),
      ),
      createdAt: _requiredDateTime(row, SupabaseSyncContract.createdAtColumn),
      updatedAt: _requiredDateTime(row, SupabaseSyncContract.updatedAtColumn),
      deletedAt: _optionalDateTime(row, SupabaseSyncContract.deletedAtColumn),
    );
  }

  /// A JSON array column. Missing or null means not provided.
  static List<T>? _optionalObjectList<T>(
    Map<String, dynamic> row,
    String column,
    T Function(Map<String, dynamic> item) parse,
  ) {
    final value = row[column];
    if (value == null) return null;
    if (value is! List) throw StateError('Invalid $column.');

    return List<T>.unmodifiable([
      for (final item in value)
        if (item is Map)
          parse(Map<String, dynamic>.from(item))
        else
          throw StateError('Invalid $column item.'),
    ]);
  }

  static CloudArtworkAssetRecord _artworkFromRow(Map<String, dynamic> row) {
    return CloudArtworkAssetRecord(
      id: _requiredString(row, SupabaseSyncContract.idColumn),
      userId: _requiredString(row, SupabaseSyncContract.userIdColumn),
      storageObjectKey: _requiredString(
        row,
        SupabaseSyncContract.storageObjectKeyColumn,
      ),
      createdAt: _requiredDateTime(row, SupabaseSyncContract.createdAtColumn),
      updatedAt: _requiredDateTime(row, SupabaseSyncContract.updatedAtColumn),
      deletedAt: _optionalDateTime(row, SupabaseSyncContract.deletedAtColumn),
    );
  }

  static const Set<String> _metadataAuthorities = {
    'inferred',
    'imported',
    'external',
    'confirmed',
    'manual',
  };

  static const Set<String> _metadataSources = {
    'filename',
    'embeddedTag',
    'musicBrainz',
    'coverArtArchive',
    'review',
    'user',
    'legacy',
  };

  static List<Map<String, dynamic>>? _metadataFieldStatesToJson(
    List<CloudMetadataFieldState>? states,
  ) {
    if (states == null) {
      return null;
    }

    return states
        .map(
          (state) => <String, dynamic>{
            'field_name': state.fieldName,
            'authority': state.authority,
            'source': state.source,
            'source_reference': state.sourceReference,
            'updated_at': state.updatedAt.toUtc().toIso8601String(),
          },
        )
        .toList(growable: false);
  }

  static List<CloudMetadataFieldState>? _metadataFieldStatesFromJson(
    Map<String, dynamic> row,
  ) {
    final value = row[SupabaseSyncContract.metadataFieldStatesColumn];

    // Historical cloud rows predate provenance sync.
    // Null means provenance is unknown, not authoritatively empty.
    if (value == null) {
      return null;
    }

    if (value is! List) {
      throw StateError(
        'Invalid ${SupabaseSyncContract.metadataFieldStatesColumn}.',
      );
    }

    return value
        .map((item) {
          if (item is! Map) {
            throw StateError(
              'Invalid ${SupabaseSyncContract.metadataFieldStatesColumn} item.',
            );
          }

          final map = Map<String, dynamic>.from(item);

          final fieldName = map['field_name'];
          final authority = map['authority'];
          final source = map['source'];
          final sourceReference = map['source_reference'];
          final updatedAtRaw = map['updated_at'];

          if (fieldName is! String || fieldName.trim().isEmpty) {
            throw StateError('Invalid metadata field_name.');
          }

          if (authority is! String ||
              !_metadataAuthorities.contains(authority)) {
            throw StateError('Invalid metadata authority.');
          }

          if (source is! String || !_metadataSources.contains(source)) {
            throw StateError('Invalid metadata source.');
          }

          if (sourceReference != null && sourceReference is! String) {
            throw StateError('Invalid metadata source_reference.');
          }

          if (updatedAtRaw is! String) {
            throw StateError('Invalid metadata updated_at.');
          }

          final DateTime updatedAt;

          try {
            updatedAt = DateTime.parse(updatedAtRaw).toUtc();
          } on FormatException {
            throw StateError('Invalid metadata updated_at.');
          }

          return CloudMetadataFieldState(
            fieldName: fieldName,
            authority: authority,
            source: source,
            sourceReference: sourceReference as String?,
            updatedAt: updatedAt,
          );
        })
        .toList(growable: false);
  }

  static String _requiredString(Map<String, dynamic> row, String column) {
    final value = row[column];

    if (value is! String || value.trim().isEmpty) {
      throw StateError('Invalid or missing $column.');
    }

    return value;
  }

  static String? _optionalString(Map<String, dynamic> row, String column) {
    final value = row[column];

    if (value == null) {
      return null;
    }

    if (value is! String) {
      throw StateError('Invalid $column.');
    }

    return value;
  }

  static String _stringOrDefault(
    Map<String, dynamic> row,
    String column,
    String defaultValue,
  ) {
    final value = row[column];

    if (value == null) {
      return defaultValue;
    }

    if (value is! String) {
      throw StateError('Invalid $column.');
    }

    return value;
  }

  static int _requiredInt(Map<String, dynamic> row, String column) {
    final value = row[column];

    if (value is! int) {
      throw StateError('Invalid or missing $column.');
    }

    return value;
  }

  static int _intOrDefault(
    Map<String, dynamic> row,
    String column,
    int defaultValue,
  ) {
    final value = row[column];

    if (value == null) {
      return defaultValue;
    }

    if (value is! int) {
      throw StateError('Invalid $column.');
    }

    return value;
  }

  static bool _boolOrDefault(
    Map<String, dynamic> row,
    String column,
    bool defaultValue,
  ) {
    final value = row[column];

    if (value == null) {
      return defaultValue;
    }

    if (value is! bool) {
      throw StateError('Invalid $column.');
    }

    return value;
  }

  static bool _requiredBool(Map<String, dynamic> row, String column) {
    final value = row[column];

    if (value is! bool) {
      throw StateError('Invalid or missing $column.');
    }

    return value;
  }

  static List<String> _requiredStringList(
    Map<String, dynamic> row,
    String column,
  ) {
    final value = row[column];

    if (value is! List) {
      throw StateError('Invalid or missing $column.');
    }

    return value
        .map((item) {
          if (item is! String) {
            throw StateError('Invalid $column item.');
          }

          return item;
        })
        .toList(growable: false);
  }

  static List<String> _stringListOrDefault(
    Map<String, dynamic> row,
    String column,
    List<String> defaultValue,
  ) {
    final value = row[column];

    if (value == null) {
      return List<String>.unmodifiable(defaultValue);
    }

    if (value is! List) {
      throw StateError('Invalid $column.');
    }

    return value
        .map((item) {
          if (item is! String) {
            throw StateError('Invalid $column item.');
          }

          return item;
        })
        .toList(growable: false);
  }

  static DateTime _requiredDateTime(Map<String, dynamic> row, String column) {
    final value = row[column];

    if (value is! String) {
      throw StateError('Invalid or missing $column.');
    }

    return DateTime.parse(value).toUtc();
  }

  static DateTime? _optionalDateTime(Map<String, dynamic> row, String column) {
    final value = row[column];

    if (value == null) {
      return null;
    }

    if (value is! String) {
      throw StateError('Invalid $column.');
    }

    return DateTime.parse(value).toUtc();
  }
}
