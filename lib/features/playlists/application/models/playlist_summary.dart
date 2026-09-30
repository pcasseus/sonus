import '../../domain/entities/playlist.dart';

class PlaylistSummary {
  const PlaylistSummary({required this.playlist, required this.trackCount});

  final Playlist playlist;
  final int trackCount;
}
