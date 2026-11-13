import '../../domain/services/album_edition_track_order.dart';
import 'album_edition_track_ordering_service.dart';

// How Release Studio lays out an edition when songs move between discs or
// a disc is deleted (App Update 1.2, PATCH-02 and PATCH-03). Pure: each
// takes the edition as shown, in order, and returns the layout to save
// with AlbumEditionTrackOrderingService, which numbers each changed disc
// 1, 2, 3... (REF-13).

/// The discs of [placements], ascending, an unknown disc counting as 1.
List<int> discsOf(Iterable<EditionPlacement> placements) =>
    {for (final p in placements) shownDisc(p.discNumber)}.toList()..sort();

/// [placements] with the songs in [songIds] moved to the end of disc
/// [target], keeping their order relative to each other. On a disc with no
/// songs yet they go where that disc begins. Songs not named stay where
/// they are; no song is added or dropped.
List<EditionPlacement> movedToDisc(
  List<EditionPlacement> placements,
  Set<String> songIds,
  int target,
) {
  if (target < 1) {
    throw ArgumentError.value(target, 'target', 'Discs start at 1.');
  }
  final moving = [
    for (final p in placements)
      if (songIds.contains(p.songId))
        EditionPlacement(songId: p.songId, discNumber: target),
  ];
  final staying = [
    for (final p in placements)
      if (!songIds.contains(p.songId)) p,
  ];
  var at = staying.lastIndexWhere((p) => shownDisc(p.discNumber) == target);
  if (at >= 0) {
    at++;
  } else {
    final later = staying.indexWhere((p) => shownDisc(p.discNumber) > target);
    at = later < 0 ? staying.length : later;
  }
  return [...staying]..insertAll(at, moving);
}

/// The disc that [disc] becomes once [deleted] is gone: later discs move
/// down one, so no number is left empty.
int discAfterDeleting(int disc, int deleted) {
  final shown = shownDisc(disc);
  return shown > deleted ? shown - 1 : shown;
}

/// The songs of [placements] on [disc], in order.
List<String> songsOnDisc(List<EditionPlacement> placements, int disc) => [
  for (final p in placements)
    if (shownDisc(p.discNumber) == disc) p.songId,
];

/// The edition after deleting [disc]: its songs moved to the end of
/// [moveTo], or left out when [moveTo] is null (their listings on this
/// edition are then removed). Later discs move down one.
List<EditionPlacement> afterDeletingDisc(
  List<EditionPlacement> placements,
  int disc, {
  int? moveTo,
}) {
  if (moveTo == disc) {
    throw ArgumentError.value(moveTo, 'moveTo', 'Must be another disc.');
  }
  final onDisc = songsOnDisc(placements, disc).toSet();
  final kept = moveTo == null
      ? [
          for (final p in placements)
            if (!onDisc.contains(p.songId)) p,
        ]
      : movedToDisc(placements, onDisc, moveTo);
  return [
    for (final p in kept)
      EditionPlacement(
        songId: p.songId,
        discNumber: discAfterDeleting(p.discNumber, disc),
      ),
  ];
}

/// Disc names after deleting [disc]: its own name goes, and each later
/// disc keeps its name under its new number.
Map<int, String> labelsAfterDeletingDisc(Map<int, String> labels, int disc) => {
  for (final MapEntry(key: number, value: label) in labels.entries)
    if (number != disc) discAfterDeleting(number, disc): label,
};
