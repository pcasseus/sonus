enum CoverArtArchiveEntity { release, releaseGroup }

extension CoverArtArchiveEntityPath on CoverArtArchiveEntity {
  String get path => switch (this) {
    CoverArtArchiveEntity.release => 'release',
    CoverArtArchiveEntity.releaseGroup => 'release-group',
  };
}

class CoverArtArchiveImage {
  const CoverArtArchiveImage({
    required this.entity,
    required this.entityId,
    required this.imageUrl,
    required this.front,
    required this.back,
    this.imageId,
    this.thumbnailUrl,
    this.types = const [],
    this.approved = false,
  });

  final CoverArtArchiveEntity entity;
  final String entityId;
  final String imageUrl;
  final String? imageId;
  final String? thumbnailUrl;
  final bool front;
  final bool back;
  final List<String> types;
  final bool approved;

  String get sourceReference => 'coverartarchive:${entity.path}:$entityId';
}
