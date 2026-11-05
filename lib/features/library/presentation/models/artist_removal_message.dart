import '../../domain/repositories/artist_reference_repository.dart';

/// Why an artist could not be removed, in the listener's words.
///
/// Lists what still refers to the artist, in a stable order, and says
/// that nothing was changed.
String artistRemovalBlockedMessage(Set<ArtistReference> references) {
  if (references.isEmpty) {
    return 'This artist is still used in your library, so it was not '
        'removed.';
  }

  final reasons = [
    for (final reference in ArtistReference.values)
      if (references.contains(reference)) _reasonFor(reference),
  ];

  return 'This artist was not removed. Sonus keeps it because it still has '
      '${_joined(reasons)}.';
}

String _reasonFor(ArtistReference reference) => switch (reference) {
  ArtistReference.albums => 'albums',
  ArtistReference.songs => 'songs',
  ArtistReference.credits => 'song credits',
  ArtistReference.projectAssignment => 'a Library grouping',
  ArtistReference.listeningHistory => 'listening history',
  ArtistReference.charts => 'chart history',
  ArtistReference.moments => 'Moments',
  ArtistReference.pendingCloudWrite => 'changes still syncing to the cloud',
};

String _joined(List<String> items) => switch (items.length) {
  1 => items.single,
  2 => '${items.first} and ${items.last}',
  _ => '${items.take(items.length - 1).join(', ')} and ${items.last}',
};
