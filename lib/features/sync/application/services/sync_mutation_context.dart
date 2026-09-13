import '../../../artwork/domain/repositories/artwork_asset_repository.dart';
import '../../../library/domain/repositories/album_edition_repository.dart';
import '../../../library/domain/repositories/album_repository.dart';
import '../../../library/domain/repositories/artist_repository.dart';
import '../../../library/domain/repositories/song_repository.dart';
import '../repositories/local_sync_repository.dart';

class SyncMutationContext {
  const SyncMutationContext({
    required this.artistRepository,
    required this.albumRepository,
    required this.albumEditionRepository,
    required this.songRepository,
    required this.artworkAssetRepository,
    required this.localSyncRepository,
  });

  final ArtistRepository artistRepository;
  final AlbumRepository albumRepository;
  final AlbumEditionRepository albumEditionRepository;
  final SongRepository songRepository;
  final ArtworkAssetRepository artworkAssetRepository;
  final LocalSyncRepository localSyncRepository;
}
