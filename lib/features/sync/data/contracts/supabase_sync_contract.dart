abstract final class SupabaseSyncContract {
  static const String artistsTable = 'artists';
  static const String albumsTable = 'albums';
  static const String albumEditionsTable = 'album_editions';
  static const String songsTable = 'songs';
  static const String artworkAssetsTable = 'artwork_assets';

  static const String artworkBucket = 'artwork';

  static const String idColumn = 'id';
  static const String userIdColumn = 'user_id';
  static const String createdAtColumn = 'created_at';
  static const String updatedAtColumn = 'updated_at';
  static const String serverUpdatedAtColumn = 'server_updated_at';
  static const String deletedAtColumn = 'deleted_at';

  static const String artistIdColumn = 'artist_id';
  static const String albumIdColumn = 'album_id';
  static const String albumEditionIdColumn = 'album_edition_id';
  static const String artworkIdColumn = 'artwork_id';
  static const String metadataFieldStatesColumn = 'metadata_field_states';

  static const String nameColumn = 'name';
  static const String canonicalNameColumn = 'canonical_name';
  static const String isBlacklistedColumn = 'is_blacklisted';

  static const String titleColumn = 'title';
  static const String canonicalTitleColumn = 'canonical_title';

  static const String headerArtworkIdColumn = 'header_artwork_id';
  static const String topArtistsArtworkIdColumn = 'top_artists_artwork_id';

  static const String typeColumn = 'type';
  static const String isPrimaryColumn = 'is_primary';
  static const String releaseDateColumn = 'release_date';
  static const String genreColumn = 'genre';

  static const String trackNumberColumn = 'track_number';
  static const String discNumberColumn = 'disc_number';
  static const String durationSecondsColumn = 'duration_seconds';
  static const String isSingleColumn = 'is_single';
  static const String isBlockedColumn = 'is_blocked';
  static const String featuredArtistsColumn = 'featured_artists';
  static const String versionLabelColumn = 'version_label';
  static const String versionCharacteristicsColumn = 'version_characteristics';
  static const String releaseStatusColumn = 'release_status';
  static const String isLeakColumn = 'is_leak';

  static const String storageObjectKeyColumn = 'storage_object_key';

  static const Set<String> cloudTables = {
    artistsTable,
    albumsTable,
    albumEditionsTable,
    songsTable,
    artworkAssetsTable,
  };

  static const Set<String> deviceLocalTables = {
    'media_file_bindings',
    'import_batches',
  };

  static const Set<String> requiredOwnedColumns = {
    idColumn,
    userIdColumn,
    createdAtColumn,
    updatedAtColumn,
    serverUpdatedAtColumn,
    deletedAtColumn,
  };

  static String artworkObjectKey({
    required String userId,
    required String artworkId,
    required String extension,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedArtworkId = artworkId.trim();
    final normalizedExtension = extension.trim().toLowerCase().replaceFirst(
      RegExp(r'^\.+'),
      '',
    );

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User ID cannot be empty.');
    }

    if (normalizedArtworkId.isEmpty) {
      throw ArgumentError.value(
        artworkId,
        'artworkId',
        'Artwork ID cannot be empty.',
      );
    }

    if (normalizedExtension.isEmpty) {
      throw ArgumentError.value(
        extension,
        'extension',
        'Artwork extension cannot be empty.',
      );
    }

    return '$normalizedUserId/$normalizedArtworkId.$normalizedExtension';
  }
}
