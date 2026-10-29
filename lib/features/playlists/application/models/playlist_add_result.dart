/// What adding songs to a playlist did. A playlist holds each song once,
/// so a song already in it is counted, never added again.
class PlaylistAddResult {
  const PlaylistAddResult({
    required this.playlistName,
    required this.added,
    required this.alreadyPresent,
    required this.failed,
  });

  final String playlistName;
  final int added;
  final int alreadyPresent;

  /// Songs that no longer exist in the library.
  final int failed;
}
