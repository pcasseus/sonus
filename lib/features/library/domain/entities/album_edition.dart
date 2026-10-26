import 'release_date.dart';

enum AlbumEditionType {
  standard,
  deluxe,
  expanded,
  anniversary,
  remaster,
  other,
}

class AlbumEdition {
  static const Object _unset = Object();

  const AlbumEdition({
    required this.id,
    required this.albumId,
    required this.title,
    required this.type,
    required this.isPrimary,
    required this.createdAt,
    required this.updatedAt,
    this.releaseDate,
    this.releaseDatePrecision,
    this.genre,
    this.artworkId,
  });

  final String id;
  final String albumId;
  final String title;
  final AlbumEditionType type;
  final bool isPrimary;
  final DateTime? releaseDate;

  /// How much of [releaseDate] is known; null for a date saved before
  /// precision was recorded, which is shown as the exact day it holds.
  final ReleaseDatePrecision? releaseDatePrecision;
  final String? genre;
  final String? artworkId;
  final DateTime createdAt;
  final DateTime updatedAt;

  AlbumEdition copyWith({
    String? id,
    String? albumId,
    String? title,
    AlbumEditionType? type,
    bool? isPrimary,
    Object? releaseDate = _unset,
    Object? releaseDatePrecision = _unset,
    Object? genre = _unset,
    Object? artworkId = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AlbumEdition(
      id: id ?? this.id,
      albumId: albumId ?? this.albumId,
      title: title ?? this.title,
      type: type ?? this.type,
      isPrimary: isPrimary ?? this.isPrimary,
      releaseDate: identical(releaseDate, _unset)
          ? this.releaseDate
          : releaseDate as DateTime?,
      releaseDatePrecision: identical(releaseDatePrecision, _unset)
          ? this.releaseDatePrecision
          : releaseDatePrecision as ReleaseDatePrecision?,
      genre: identical(genre, _unset) ? this.genre : genre as String?,
      artworkId: identical(artworkId, _unset)
          ? this.artworkId
          : artworkId as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// The release date as far as it is known.
  ReleaseDate? get releaseDateValue => releaseDate == null
      ? null
      : ReleaseDate.fromStored(releaseDate!, releaseDatePrecision);

  /// A copy dated [date], with its precision.
  AlbumEdition withReleaseDate(ReleaseDate? date, {DateTime? updatedAt}) =>
      copyWith(
        releaseDate: date?.instant,
        releaseDatePrecision: date?.precision,
        updatedAt: updatedAt,
      );

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is AlbumEdition && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
