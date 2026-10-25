import '../../../../core/database/app_database.dart';
import '../../../../core/identity/entity_id.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../../artwork/data/daos/artwork_asset_dao.dart';
import '../../../artwork/data/repositories/sqlite_artwork_asset_repository.dart';
import '../../../library/data/daos/album_dao.dart';
import '../../../library/data/daos/album_edition_dao.dart';
import '../../../library/data/repositories/sqlite_album_edition_track_repository.dart';
import '../../../library/data/daos/album_edition_track_dao.dart';
import '../../../library/data/daos/artist_dao.dart';
import '../../../library/data/daos/song_dao.dart';
import '../../../library/data/daos/song_artist_credit_dao.dart';
import '../../../library/data/daos/metadata_field_state_dao.dart';
import '../../../library/data/repositories/sqlite_album_edition_repository.dart';
import '../../../library/data/repositories/sqlite_album_repository.dart';
import '../../../library/data/repositories/sqlite_artist_repository.dart';
import '../../../library/data/repositories/sqlite_artist_identity_repair_repository.dart';
import '../../../library/data/repositories/sqlite_song_repository.dart';
import '../../../library/data/repositories/sqlite_song_artist_credit_repository.dart';
import '../../../library/data/repositories/sqlite_metadata_field_state_repository.dart';
import '../../../playlists/data/daos/playlist_dao.dart';
import '../../../playlists/data/repositories/sqlite_playlist_repository.dart';
import '../../application/services/sync_mutation_context.dart';
import '../../application/services/sync_mutation_runner.dart';
import '../daos/local_sync_dao.dart';
import '../daos/cloud_revision_baseline_dao.dart';
import '../daos/artist_write_journal_dao.dart';
import '../daos/artist_dependency_journal_dao.dart';
import '../daos/inbound_deferred_record_dao.dart';
import '../daos/outbound_conflict_dao.dart';
import 'sqlite_local_sync_repository.dart';
import 'sqlite_cloud_revision_baseline_repository.dart';
import 'sqlite_artist_write_journal_repository.dart';
import 'sqlite_artist_dependency_journal_repository.dart';
import 'sqlite_inbound_deferred_record_repository.dart';
import 'sqlite_outbound_conflict_repository.dart';

class SyncMutationTransactionRunner implements SyncMutationRunner {
  SyncMutationTransactionRunner({
    required this.appDatabase,
    SyncIdGenerator? generateId,
    SyncClock? now,
    LibraryChangeSignal? changes,
  }) : _generateId = generateId ?? EntityId.syncOutbox,
       _now = now ?? DateTime.now,
       _changes = changes ?? LibraryChangeSignal.shared;

  /// Told once each mutation has committed, so screens can reload.
  final LibraryChangeSignal _changes;

  final AppDatabase appDatabase;
  final SyncIdGenerator _generateId;
  final SyncClock _now;

  @override
  Future<T> run<T>(SyncMutationAction<T> action) async {
    final result = await _run(action);
    _changes.notify(LibraryChangeKind.libraryEdited);
    return result;
  }

  Future<T> _run<T>(SyncMutationAction<T> action) {
    return appDatabase.transaction((transaction) async {
      final context = SyncMutationContext(
        artistRepository: SqliteArtistRepository(ArtistDao(transaction)),
        artistIdentityRepairRepository: SqliteArtistIdentityRepairRepository(
          transaction,
        ),
        albumRepository: SqliteAlbumRepository(AlbumDao(transaction)),
        albumEditionRepository: SqliteAlbumEditionRepository(
          AlbumEditionDao(transaction),
        ),
        albumEditionTrackRepository: SqliteAlbumEditionTrackRepository(
          AlbumEditionTrackDao(transaction),
        ),
        songRepository: SqliteSongRepository(SongDao(transaction)),
        songArtistCreditRepository: SqliteSongArtistCreditRepository(
          SongArtistCreditDao(transaction),
        ),
        metadataFieldStateRepository: SqliteMetadataFieldStateRepository(
          MetadataFieldStateDao(transaction),
        ),
        artworkAssetRepository: SqliteArtworkAssetRepository(
          ArtworkAssetDao(transaction),
        ),
        localSyncRepository: SqliteLocalSyncRepository(
          dao: LocalSyncDao(transaction),
          generateId: _generateId,
          now: _now,
        ),
        cloudRevisionBaselineRepository: SqliteCloudRevisionBaselineRepository(
          dao: CloudRevisionBaselineDao(transaction),
        ),
        artistWriteJournalRepository: SqliteArtistWriteJournalRepository(
          ArtistWriteJournalDao(transaction),
        ),
        artistDependencyJournalRepository:
            SqliteArtistDependencyJournalRepository(
              ArtistDependencyJournalDao(transaction),
            ),
        inboundDeferredRecordRepository: SqliteInboundDeferredRecordRepository(
          dao: InboundDeferredRecordDao(transaction),
        ),
        outboundConflictRepository: SqliteOutboundConflictRepository(
          dao: OutboundConflictDao(transaction),
        ),
        playlistRepository: SqlitePlaylistRepository(PlaylistDao(transaction)),
      );

      return action(context);
    });
  }
}
