import '../../../artwork/domain/repositories/artwork_asset_repository.dart';
import '../../../library/domain/repositories/album_edition_repository.dart';
import '../../../library/domain/repositories/album_edition_track_repository.dart';
import '../../../library/domain/repositories/album_repository.dart';
import '../../../library/domain/repositories/artist_repository.dart';
import '../../../library/domain/repositories/song_repository.dart';
import '../../../library/domain/repositories/song_artist_credit_repository.dart';
import '../../../playlists/domain/repositories/playlist_repository.dart';
import '../repositories/local_sync_repository.dart';

class SyncMutationContext {
  const SyncMutationContext({
    required this.artistRepository,
    required this.albumRepository,
    required this.albumEditionRepository,
    this.albumEditionTrackRepository,
    required this.songRepository,
    required this.songArtistCreditRepository,
    required this.artworkAssetRepository,
    required this.localSyncRepository,
    this.playlistRepository,
  });

  final ArtistRepository artistRepository;
  final AlbumRepository albumRepository;
  final AlbumEditionRepository albumEditionRepository;
  final AlbumEditionTrackRepository? albumEditionTrackRepository;
  final SongRepository songRepository;
  final SongArtistCreditRepository songArtistCreditRepository;
  final ArtworkAssetRepository artworkAssetRepository;
  final LocalSyncRepository localSyncRepository;
  final PlaylistRepository? playlistRepository;
}
