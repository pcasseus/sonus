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
    required this.isBlacklisted,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    this.headerArtworkId,
    this.topArtistsArtworkId,
  });

  final String name;
  final String canonicalName;
  final bool isBlacklisted;
  final String? headerArtworkId;
  final String? topArtistsArtworkId;
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
  });

  final String artistId;
  final String title;
  final String canonicalTitle;
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
  });

  final String albumId;
  final String title;
  final String type;
  final bool isPrimary;
  final DateTime? releaseDate;
  final String? genre;
  final String? artworkId;
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
    required this.durationSeconds,
    required this.isSingle,
    required this.featuredArtists,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    this.artworkId,
  });

  final String artistId;
  final String albumId;
  final String albumEditionId;
  final String title;
  final String canonicalTitle;
  final int trackNumber;
  final int durationSeconds;
  final bool isSingle;
  final List<String> featuredArtists;
  final String? artworkId;
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
