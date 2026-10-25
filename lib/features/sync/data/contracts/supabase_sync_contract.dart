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
  static const String serverRevisionColumn = 'server_revision';
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

  /// SN-45 song columns, added by migration 20261025000001. Sent only to a
  /// server that has them.
  static const String editionMembershipsColumn = 'edition_memberships';
  static const String artistCreditsColumn = 'artist_credits';
  static const Set<String> songExtensionColumns = {
    editionMembershipsColumn,
    artistCreditsColumn,
  };

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

  /// Image extensions accepted when downloading cloud artwork.
  static const Set<String> downloadableArtworkExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
  };

  /// Returns the extension of [objectKey] when it is a legacy or versioned
  /// artwork key for exactly [userId] and [artworkId] with an accepted
  /// image extension, otherwise null.
  static String? verifiedArtworkObjectKeyExtension({
    required String userId,
    required String artworkId,
    required String objectKey,
  }) {
    final safeSegment = RegExp(r'^[A-Za-z0-9_-]+$');

    if (!safeSegment.hasMatch(userId) || !safeSegment.hasMatch(artworkId)) {
      return null;
    }

    final prefix = '$userId/$artworkId';

    if (!objectKey.startsWith(prefix)) {
      return null;
    }

    final match = RegExp(
      r'^(?:/[A-Za-z0-9_-]+)?\.([a-z0-9]+)$',
    ).firstMatch(objectKey.substring(prefix.length));
    final extension = match?.group(1);

    return extension != null &&
            downloadableArtworkExtensions.contains(extension)
        ? extension
        : null;
  }

  /// Immutable key for one uploaded version of an artwork asset.
  static String versionedArtworkObjectKey({
    required String userId,
    required String artworkId,
    required String version,
    required String extension,
  }) {
    final normalizedVersion = version.trim();

    if (normalizedVersion.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalizedVersion)) {
      throw ArgumentError.value(
        version,
        'version',
        'Artwork version must be a non-empty key-safe token.',
      );
    }

    final legacyKey = artworkObjectKey(
      userId: userId,
      artworkId: artworkId,
      extension: extension,
    );
    final dot = legacyKey.lastIndexOf('.');

    return '${legacyKey.substring(0, dot)}/$normalizedVersion'
        '${legacyKey.substring(dot)}';
  }
}
