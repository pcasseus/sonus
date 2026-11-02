import 'library_track.dart';

/// One track whose number a numbering repair would change.
class EditionNumberChange {
  const EditionNumberChange({
    required this.track,
    required this.from,
    required this.to,
  });

  final LibraryTrack track;
  final int from;
  final int to;
}

/// What numbering an edition's [tracks], given in the order they are
/// shown, 1, 2, 3… on each disc would change, as `renumberEditionTracks`
/// does (SN-50 A-Q7D). Empty when every disc already starts at 1 without
/// gaps. Tracks with an unknown number (0) keep it.
List<EditionNumberChange> editionNumberingRepair(
  Iterable<LibraryTrack> tracks,
) {
  final nextByDisc = <int, int>{};
  final changes = <EditionNumberChange>[];

  for (final track in tracks) {
    if (track.trackNumber <= 0) continue;

    final target = nextByDisc.update(
      track.discNumber <= 0 ? 1 : track.discNumber,
      (number) => number + 1,
      ifAbsent: () => 1,
    );

    if (track.trackNumber != target) {
      changes.add(
        EditionNumberChange(track: track, from: track.trackNumber, to: target),
      );
    }
  }

  return List.unmodifiable(changes);
}
