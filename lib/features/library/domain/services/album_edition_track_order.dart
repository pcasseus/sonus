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

/// Whether an edition's listings really span more than one disc (SN-50
/// A-Q8A). Public disc headings and disc-track numbers appear only then; an
/// unknown disc counts as disc 1.
bool spansMultipleDiscs(Iterable<int> discNumbers) =>
    {for (final disc in discNumbers) disc <= 0 ? 1 : disc}.length > 1;

/// The disc a track is shown on: an unknown disc (0) is disc 1.
int shownDisc(int disc) => disc <= 0 ? 1 : disc;

/// [items] grouped by shown disc in ascending order, keeping their order
/// within each disc (App Update 1.2, REF-13). Stable: items already
/// grouped come back in the same order.
List<T> groupedByDisc<T>(List<T> items, int Function(T item) discOf) {
  final indexed = [for (final (i, item) in items.indexed) (i, item)];
  indexed.sort((a, b) {
    final byDisc = shownDisc(discOf(a.$2)).compareTo(shownDisc(discOf(b.$2)));
    return byDisc != 0 ? byDisc : a.$1.compareTo(b.$1);
  });
  return [for (final (_, item) in indexed) item];
}
