import '../entities/album_edition_track.dart';

/// Automatic edition order: disc, then track number, with unknown numbers
/// after the numbered tracks of their disc. Matches the SQL ordering used
/// when an edition has not been reordered by hand.
int compareByDiscAndTrack(AlbumEditionTrack a, AlbumEditionTrack b) {
  int disc(AlbumEditionTrack m) => m.discNumber <= 0 ? 1 : m.discNumber;
  int unnumbered(AlbumEditionTrack m) => m.trackNumber <= 0 ? 1 : 0;

  for (final comparison in [
    disc(a).compareTo(disc(b)),
    unnumbered(a).compareTo(unnumbered(b)),
    a.trackNumber.compareTo(b.trackNumber),
    a.sortPosition.compareTo(b.sortPosition),
    a.songId.compareTo(b.songId),
  ]) {
    if (comparison != 0) {
      return comparison;
    }
  }

  return 0;
}
