class CloudMetadataFieldState {
  const CloudMetadataFieldState({
    required this.fieldName,
    required this.authority,
    required this.source,
    required this.updatedAt,
    this.sourceReference,
  });

  final String fieldName;
  final String authority;
  final String source;
  final String? sourceReference;
  final DateTime updatedAt;
}

abstract class CloudOwnedRecord {
  const CloudOwnedRecord({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
}

class CloudArtistRecord extends CloudOwnedRecord {
  const CloudArtistRecord({
    required super.id,
    required super.userId,
    required this.name,
    required this.canonicalName,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    this.headerArtworkId,
    this.topArtistsArtworkId,
    this.metadataFieldStates,
  });

  final String name;
  final String canonicalName;
  final String? headerArtworkId;
  final String? topArtistsArtworkId;
  final List<CloudMetadataFieldState>? metadataFieldStates;
}

class CloudAlbumRecord extends CloudOwnedRecord {
  const CloudAlbumRecord({
    required super.id,
    required super.userId,
    required this.artistId,
    required this.title,
    required this.canonicalTitle,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    this.metadataFieldStates,
  });

  final String artistId;
  final String title;
  final String canonicalTitle;
  final List<CloudMetadataFieldState>? metadataFieldStates;
}

class CloudAlbumEditionRecord extends CloudOwnedRecord {
  const CloudAlbumEditionRecord({
    required super.id,
    required super.userId,
    required this.albumId,
    required this.title,
    required this.type,
    required this.isPrimary,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    this.releaseDate,
    this.genre,
    this.artworkId,
    this.metadataFieldStates,
  });

  final String albumId;
  final String title;
  final String type;
  final bool isPrimary;
  final DateTime? releaseDate;
  final String? genre;
  final String? artworkId;
  final List<CloudMetadataFieldState>? metadataFieldStates;
}

class CloudSongRecord extends CloudOwnedRecord {
  const CloudSongRecord({
    required super.id,
    required super.userId,
    required this.artistId,
    required this.albumId,
    required this.albumEditionId,
    required this.title,
    required this.canonicalTitle,
    required this.trackNumber,
    this.discNumber = 1,
    required this.durationSeconds,
    required this.isSingle,
    this.isBlocked = false,
    required this.featuredArtists,
    this.versionLabel,
    this.versionCharacteristics = const [],
    this.releaseStatus = 'released',
    this.isLeak = false,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    this.artworkId,
    this.metadataFieldStates,
  });

  final String artistId;
  final String albumId;
  final String albumEditionId;
  final String title;
  final String canonicalTitle;
  final int trackNumber;
  final int discNumber;
  final int durationSeconds;
  final bool isSingle;
  final bool isBlocked;
  final List<String> featuredArtists;
  final String? versionLabel;
  final List<String> versionCharacteristics;
  final String releaseStatus;
  final bool isLeak;
  final String? artworkId;
  final List<CloudMetadataFieldState>? metadataFieldStates;
}

class CloudArtworkAssetRecord extends CloudOwnedRecord {
  const CloudArtworkAssetRecord({
    required super.id,
    required super.userId,
    required this.storageObjectKey,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
  });

  final String storageObjectKey;
}
