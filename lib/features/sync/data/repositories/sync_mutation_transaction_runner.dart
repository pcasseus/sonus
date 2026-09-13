import '../../../../core/database/app_database.dart';
import '../../../../core/identity/entity_id.dart';
import '../../../artwork/data/daos/artwork_asset_dao.dart';
import '../../../artwork/data/repositories/sqlite_artwork_asset_repository.dart';
import '../../../library/data/daos/album_dao.dart';
import '../../../library/data/daos/album_edition_dao.dart';
import '../../../library/data/daos/artist_dao.dart';
import '../../../library/data/daos/song_dao.dart';
import '../../../library/data/repositories/sqlite_album_edition_repository.dart';
import '../../../library/data/repositories/sqlite_album_repository.dart';
import '../../../library/data/repositories/sqlite_artist_repository.dart';
import '../../../library/data/repositories/sqlite_song_repository.dart';
import '../../application/services/sync_mutation_context.dart';
import '../../application/services/sync_mutation_runner.dart';
import '../daos/local_sync_dao.dart';
import 'sqlite_local_sync_repository.dart';

class SyncMutationTransactionRunner implements SyncMutationRunner {
  SyncMutationTransactionRunner({
    required this.appDatabase,
    SyncIdGenerator? generateId,
    SyncClock? now,
  }) : _generateId = generateId ?? EntityId.syncOutbox,
       _now = now ?? DateTime.now;

  final AppDatabase appDatabase;
  final SyncIdGenerator _generateId;
  final SyncClock _now;

  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    return appDatabase.transaction((transaction) async {
      final context = SyncMutationContext(
        artistRepository: SqliteArtistRepository(ArtistDao(transaction)),
        albumRepository: SqliteAlbumRepository(AlbumDao(transaction)),
        albumEditionRepository: SqliteAlbumEditionRepository(
          AlbumEditionDao(transaction),
        ),
        songRepository: SqliteSongRepository(SongDao(transaction)),
        artworkAssetRepository: SqliteArtworkAssetRepository(
          ArtworkAssetDao(transaction),
        ),
        localSyncRepository: SqliteLocalSyncRepository(
          dao: LocalSyncDao(transaction),
          generateId: _generateId,
          now: _now,
        ),
      );

      return action(context);
    });
  }
}
