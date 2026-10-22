import '../../../../core/database/app_database.dart';
import '../../../import/application/services/atomic_library_importer.dart';
import '../../../import/application/services/import_batch_executor.dart';
import '../../../import/application/services/import_batch_runner.dart';
import '../../../import/application/services/import_workflow_service.dart';
import '../../../import/application/services/library_import_service.dart';
import '../../../import/application/services/metadata_resolver.dart';
import '../../../import/data/daos/import_batch_dao.dart';
import '../../../import/data/daos/import_source_dao.dart';
import '../../../import/data/daos/media_file_binding_dao.dart';
import '../../../import/data/repositories/sqlite_import_batch_repository.dart';
import '../../../import/data/repositories/sqlite_import_source_repository.dart';
import '../../../import/data/repositories/sqlite_media_file_binding_repository.dart';
import '../../../import/domain/services/import_candidate_discovery.dart';
import '../../../../core/database/database_tables.dart';

class MissingAudioSong {
  const MissingAudioSong({
    required this.songId,
    required this.title,
    required this.artistName,
  });

  final String songId;
  final String title;
  final String artistName;
}

class RecoveryAudioStatus {
  RecoveryAudioStatus({
    required this.totalSongs,
    required this.songsWithoutAudio,
    required List<MissingAudioSong> sample,
  }) : sample = List.unmodifiable(sample);

  final int totalSongs;

  /// Songs with no available audio file on this device.
  final int songsWithoutAudio;

  /// The first missing songs, ordered by artist and title.
  final List<MissingAudioSong> sample;

  int get songsWithAudio => totalSongs - songsWithoutAudio;
}

/// Reports restored songs whose audio is not present on this device.
///
/// Uses the same rule as the library: a song is playable only through an
/// available media binding. Old-device paths are never restored, so a new
/// device starts with every song missing until it is relinked.
class RecoveryAudioStatusService {
  const RecoveryAudioStatusService({required this.appDatabase});

  final AppDatabase appDatabase;

  static const _missingCondition =
      'NOT EXISTS (SELECT 1 FROM ${DatabaseTables.mediaFileBindings} m '
      'WHERE m.song_id = s.id AND m.is_available = 1)';

  Future<RecoveryAudioStatus> status({int sampleLimit = 50}) async {
    final db = await appDatabase.database;

    final total = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DatabaseTables.songs}',
    );
    final missing = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DatabaseTables.songs} s '
      'WHERE $_missingCondition',
    );
    final sample = await db.rawQuery(
      'SELECT s.id, s.title, a.name AS artist_name '
      'FROM ${DatabaseTables.songs} s '
      'JOIN ${DatabaseTables.artists} a ON a.id = s.artist_id '
      'WHERE $_missingCondition '
      'ORDER BY a.canonical_name, s.canonical_title, s.id '
      'LIMIT ?',
      [sampleLimit],
    );

    return RecoveryAudioStatus(
      totalSongs: total.single['c'] as int,
      songsWithoutAudio: missing.single['c'] as int,
      sample: [
        for (final row in sample)
          MissingAudioSong(
            songId: row['id'] as String,
            title: row['title'] as String,
            artistName: row['artist_name'] as String,
          ),
      ],
    );
  }
}

class RecoveryRelinkResult {
  const RecoveryRelinkResult({
    required this.filesScanned,
    required this.relinked,
    required this.unmatchedOrAlreadyLinked,
    required this.failed,
    required this.missingBefore,
    required this.missingAfter,
  });

  final int filesScanned;
  final int relinked;

  /// Files skipped because no existing song matched, or because the song
  /// already had available audio.
  final int unmatchedOrAlreadyLinked;
  final int failed;

  final int missingBefore;
  final int missingAfter;
}

/// Reconnects restored songs to audio files on this device.
///
/// Runs the existing import pipeline in relink-only mode: a file is bound
/// to a song only when existing identity resolution finds that song. No
/// artist, album, edition, song, credit, lyric, or metadata record is
/// created or changed, and nothing is queued for cloud sync.
class RecoveryAudioRelinkService {
  const RecoveryAudioRelinkService({
    required this.appDatabase,
    required this.candidateDiscovery,
    required this.metadataResolver,
    this.onSongsBecameUnavailable,
  });

  final AppDatabase appDatabase;
  final ImportCandidateDiscovery candidateDiscovery;
  final MetadataResolver metadataResolver;
  final SongsBecameUnavailableCallback? onSongsBecameUnavailable;

  Future<RecoveryRelinkResult> relinkFolder(
    String rootPath, {
    ImportBatchProgressCallback? onProgress,
  }) async {
    final statusService = RecoveryAudioStatusService(appDatabase: appDatabase);
    final before = await statusService.status(sampleLimit: 0);
    final db = await appDatabase.database;

    final bindingRepository = SqliteMediaFileBindingRepository(
      MediaFileBindingDao(db),
    );

    final workflow = ImportWorkflowService(
      candidateDiscovery: candidateDiscovery,
      batchRunner: ImportBatchExecutor(
        libraryImportService: LibraryImportService(
          metadataResolver: metadataResolver,
          atomicImporter: AtomicLibraryImporter(
            appDatabase: appDatabase,
            relinkOnly: true,
          ),
          mediaFileBindingRepository: bindingRepository,
          // Restored lyrics are authoritative; sidecars must not replace them.
          lyricsIngestionService: null,
        ),
        batchRepository: SqliteImportBatchRepository(ImportBatchDao(db)),
      ),
      importSourceRepository: SqliteImportSourceRepository(
        ImportSourceDao(db),
      ),
      mediaFileBindingRepository: bindingRepository,
      onSongsBecameUnavailable: onSongsBecameUnavailable,
    );

    final summary = await workflow.importStructuredFolder(
      rootPath,
      onProgress: onProgress,
    );

    if (summary.importedCount != 0) {
      throw StateError('Relink-only import created library entries.');
    }

    final after = await statusService.status(sampleLimit: 0);

    return RecoveryRelinkResult(
      filesScanned: summary.totalCount,
      relinked: summary.relinkedCount,
      unmatchedOrAlreadyLinked: summary.skippedCount,
      failed: summary.failedCount,
      missingBefore: before.songsWithoutAudio,
      missingAfter: after.songsWithoutAudio,
    );
  }
}
