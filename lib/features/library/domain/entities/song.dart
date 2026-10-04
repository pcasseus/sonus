enum SongReleaseStatus { released, unreleased }

enum SongVersionCharacteristic {
  remix,
  live,
  acoustic,
  demo,
  instrumental,
  edit,
  radioEdit,
  extended,
  remaster,
  alternate,
}

class Song {
  static const Object _unset = Object();

  const Song({
    required this.id,
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
    required this.createdAt,
    required this.updatedAt,
    this.featuredArtists = const [],
    this.artworkId,
    this.versionLabel,
    this.versionCharacteristics = const [],
    this.releaseStatus = SongReleaseStatus.released,
    this.isLeak = false,
  });

  final String id;
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
  final String? artworkId;
  final String? versionLabel;
  final List<SongVersionCharacteristic> versionCharacteristics;
  final SongReleaseStatus releaseStatus;
  final bool isLeak;
  final DateTime createdAt;
  final DateTime updatedAt;

  Song copyWith({
    String? id,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    String? title,
    String? canonicalTitle,
    int? trackNumber,
    int? discNumber,
    int? durationSeconds,
    bool? isSingle,
    bool? isBlocked,
    List<String>? featuredArtists,
    Object? artworkId = _unset,
    Object? versionLabel = _unset,
    List<SongVersionCharacteristic>? versionCharacteristics,
    SongReleaseStatus? releaseStatus,
    bool? isLeak,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Song(
      id: id ?? this.id,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      albumEditionId: albumEditionId ?? this.albumEditionId,
      title: title ?? this.title,
      canonicalTitle: canonicalTitle ?? this.canonicalTitle,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isSingle: isSingle ?? this.isSingle,
      isBlocked: isBlocked ?? this.isBlocked,
      featuredArtists: featuredArtists ?? this.featuredArtists,
      artworkId: identical(artworkId, _unset)
          ? this.artworkId
          : artworkId as String?,
      versionLabel: identical(versionLabel, _unset)
          ? this.versionLabel
          : versionLabel as String?,
      versionCharacteristics:
          versionCharacteristics ?? this.versionCharacteristics,
      releaseStatus: releaseStatus ?? this.releaseStatus,
      isLeak: isLeak ?? this.isLeak,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is Song && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
