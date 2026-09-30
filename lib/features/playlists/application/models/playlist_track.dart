import '../../../library/application/models/library_track.dart';
import '../../domain/entities/playlist_item.dart';

class PlaylistTrack {
  const PlaylistTrack({required this.item, required this.track});

  final PlaylistItem item;
  final LibraryTrack track;
}
