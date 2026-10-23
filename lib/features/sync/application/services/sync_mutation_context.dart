import '../../../artwork/domain/repositories/artwork_asset_repository.dart';
import '../../../library/domain/repositories/album_edition_repository.dart';
import '../../../library/domain/repositories/album_edition_track_repository.dart';
import '../../../library/domain/repositories/album_repository.dart';
import '../../../library/domain/repositories/artist_repository.dart';
import '../../../library/domain/repositories/artist_identity_repair_repository.dart';
import '../../../library/domain/repositories/song_repository.dart';
import '../../../library/domain/repositories/song_artist_credit_repository.dart';
import '../../../library/domain/repositories/metadata_field_state_repository.dart';
import '../../../playlists/domain/repositories/playlist_repository.dart';
import '../repositories/local_sync_repository.dart';
import '../repositories/cloud_revision_baseline_repository.dart';
import '../repositories/artist_write_journal_repository.dart';
import '../repositories/artist_dependency_journal_repository.dart';
import '../repositories/inbound_deferred_record_repository.dart';

class SyncMutationContext {
  const SyncMutationContext({
    required this.artistRepository,
    this.artistIdentityRepairRepository,
    required this.albumRepository,
    required this.albumEditionRepository,
    required this.albumEditionTrackRepository,
    required this.songRepository,
    required this.songArtistCreditRepository,
    this.metadataFieldStateRepository,
    required this.artworkAssetRepository,
    required this.localSyncRepository,
    this.cloudRevisionBaselineRepository,
    this.artistWriteJournalRepository,
    this.artistDependencyJournalRepository,
    this.inboundDeferredRecordRepository,
    this.playlistRepository,
  });

  final ArtistRepository artistRepository;
  final ArtistIdentityRepairRepository? artistIdentityRepairRepository;
  final AlbumRepository albumRepository;
  final AlbumEditionRepository albumEditionRepository;
  final AlbumEditionTrackRepository albumEditionTrackRepository;
  final SongRepository songRepository;
  final SongArtistCreditRepository songArtistCreditRepository;
  final MetadataFieldStateRepository? metadataFieldStateRepository;
  final ArtworkAssetRepository artworkAssetRepository;
  final LocalSyncRepository localSyncRepository;
  final CloudRevisionBaselineRepository? cloudRevisionBaselineRepository;
  final ArtistWriteJournalRepository? artistWriteJournalRepository;
  final ArtistDependencyJournalRepository? artistDependencyJournalRepository;
  final InboundDeferredRecordRepository? inboundDeferredRecordRepository;
  final PlaylistRepository? playlistRepository;
}
