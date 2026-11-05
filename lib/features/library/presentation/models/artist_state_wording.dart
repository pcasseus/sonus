import '../../../../core/design/sonus_count_label.dart';
import '../../domain/repositories/artist_reference_repository.dart';

/// The name of each artist state on the Artists page (A2).
String artistStateLabel(ArtistLibraryState state) => switch (state) {
  ArtistLibraryState.active => 'In use',
  ArtistLibraryState.retired => 'Kept for history',
  ArtistLibraryState.waitingForSync => 'Waiting for sync',
  ArtistLibraryState.removable => 'Removable',
};

/// What each state means, shown above its list.
String artistStateExplanation(ArtistLibraryState state) => switch (state) {
  ArtistLibraryState.active =>
    'Songs, albums, credits or a Library grouping use these artists.',
  ArtistLibraryState.retired =>
    'No songs use these artists now, but your listening history, charts '
        'or Moments still name them. Sonus keeps them so those records stay '
        'complete, so they cannot be removed. They are left out of artist '
        'pickers and Search, and return as soon as a song uses them again.',
  ArtistLibraryState.waitingForSync =>
    'Changes to these artists are still being confirmed with the cloud. '
        'They cannot be removed until sync finishes.',
  ArtistLibraryState.removable =>
    'Nothing in Sonus refers to these artists. You can remove them one at '
        'a time. Your music and audio files are not affected.',
};

/// What refers to an artist, as counts: "12 plays · 3 chart weeks ·
/// 4 Moments", "2 songs · 1 album". Empty when nothing does.
String artistReferenceCounts(ArtistReferenceSummary summary) {
  final parts = [
    if (summary.songs > 0) sonusCount(summary.songs, 'song'),
    if (summary.albums > 0) sonusCount(summary.albums, 'album'),
    if (summary.credits > 0) sonusCount(summary.credits, 'credit'),
    if (summary.projectAssignments > 0) 'Library grouping',
    if (summary.qualifiedPlays > 0)
      sonusCount(summary.qualifiedPlays, 'play')
    else if (summary.listeningSessions > 0)
      sonusCount(summary.listeningSessions, 'listening session'),
    if (summary.chartWeeks > 0) sonusCount(summary.chartWeeks, 'chart week'),
    if (summary.moments > 0) sonusCount(summary.moments, 'Moment'),
    if (summary.pendingCloudWrites > 0) 'changes syncing',
  ];
  return parts.join(' · ');
}
