enum SongArtistCreditRole { primary, coPrimary, featured, guest }

class SongArtistCredit {
  static const Object _unset = Object();

  const SongArtistCredit({
    required this.id,
    required this.songId,
    required this.creditedName,
    required this.canonicalCreditedName,
    required this.role,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
    this.artistId,
  });

  final String id;
  final String songId;

  /// Links to a real library Artist when one exists.
  ///
  /// This intentionally remains nullable so feature-only credits do not
  /// manufacture otherwise-empty Artist profiles.
  final String? artistId;

  final String creditedName;
  final String canonicalCreditedName;
  final SongArtistCreditRole role;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isLinkedToLibraryArtist => artistId != null;

  SongArtistCredit copyWith({
    String? id,
    String? songId,
    Object? artistId = _unset,
    String? creditedName,
    String? canonicalCreditedName,
    SongArtistCreditRole? role,
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SongArtistCredit(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      artistId: identical(artistId, _unset)
          ? this.artistId
          : artistId as String?,
      creditedName: creditedName ?? this.creditedName,
      canonicalCreditedName:
          canonicalCreditedName ?? this.canonicalCreditedName,
      role: role ?? this.role,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SongArtistCredit && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
