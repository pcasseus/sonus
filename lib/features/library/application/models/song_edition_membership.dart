/// One edition of a song's own release that lists the song.
///
/// Read-only: a row of the edition's track list (`album_edition_tracks`),
/// kept only when the edition belongs to the same release as the song.
class SongEditionMembership {
  const SongEditionMembership({required this.songId, required this.editionId});

  final String songId;
  final String editionId;

  @override
  bool operator ==(Object other) =>
      other is SongEditionMembership &&
      other.songId == songId &&
      other.editionId == editionId;

  @override
  int get hashCode => Object.hash(songId, editionId);

  @override
  String toString() => 'SongEditionMembership($songId, $editionId)';
}
