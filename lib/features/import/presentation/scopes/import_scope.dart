import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:saf/saf.dart';

import '../../../../core/database/app_database.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../library/application/services/artist_creation_service.dart';
import '../../../library/application/services/malformed_artist_identity_repair_scan_service.dart';
import '../../../library/application/services/malformed_artist_identity_repair_service.dart';
import '../../../library/data/daos/artist_dao.dart';
import '../../../library/data/repositories/sqlite_artist_repository.dart';
import '../../../library/application/services/track_profile_editing_service.dart';
import '../../../library/data/daos/song_dao.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../library/data/repositories/sqlite_song_repository.dart';
import '../../../player/data/daos/track_lyrics_dao.dart';
import '../../../player/data/repositories/sqlite_track_lyrics_repository.dart';
import '../../../sync/data/repositories/sync_mutation_transaction_runner.dart';
import '../../application/services/atomic_library_importer.dart';
import '../../application/services/import_batch_executor.dart';
import '../../application/services/import_duration_repair_service.dart';
import '../../application/services/import_review_cleanup_service.dart';
import '../../application/services/import_review_service.dart';
import '../../application/services/import_source_picker.dart';
import '../../application/services/import_source_reconciliation_service.dart';
import '../../application/services/import_workflow_service.dart';
import '../../application/services/library_import_service.dart';
import '../../application/services/lyrics_ingestion_service.dart';
import '../../application/services/metadata_resolver.dart';
import '../../data/daos/import_batch_dao.dart';
import '../../data/daos/import_source_dao.dart';
import '../../data/daos/media_file_binding_dao.dart';
import '../../data/daos/song_import_review_dao.dart';
import '../../data/repositories/sqlite_import_batch_repository.dart';
import '../../data/repositories/sqlite_import_source_repository.dart';
import '../../data/repositories/sqlite_media_file_binding_repository.dart';
import '../../data/repositories/sqlite_song_import_review_repository.dart';
import '../../data/services/file_system_import_candidate_discovery.dart';
import '../../data/services/local_lyrics_source_reader.dart';
import '../../data/services/media_metadata_reader.dart';
import '../../data/services/path_fallback_metadata_reader.dart';
import '../../data/services/saf_import_candidate_discovery.dart';
import '../services/file_picker_import_source_picker.dart';

class ImportScope extends StatefulWidget {
  const ImportScope({super.key, required this.child});

  final Widget child;

  @override
  State<ImportScope> createState() => _ImportScopeState();
}

class _ImportScopeState extends State<ImportScope> {
  final Saf _saf = Saf();

  AppDatabase? _database;
  String? _userId;
  LibraryQueryRepository? _libraryQueryRepository;
  ArtistCreationService? _artistCreationService;
  TrackProfileEditingService? _trackProfileEditingService;
  PlaybackCoordinator? _playbackCoordinator;
  ImportWorkflowService? _workflowService;
  ImportReviewService? _reviewService;
  int _initializationVersion = 0;
  bool _durationRepairStarted = false;
  bool _artistIdentityRepairStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final database = context.watch<AppDatabase>();
    final accountController = context.watch<AccountController?>();
    final libraryQueryRepository = context.watch<LibraryQueryRepository?>();
    final artistCreationService = context.watch<ArtistCreationService?>();
    final trackProfileEditingService = context
        .watch<TrackProfileEditingService?>();
    final playbackCoordinator = context.read<PlaybackCoordinator>();
    final rawUserId = accountController?.user?.id.trim();
    final userId = rawUserId == null || rawUserId.isEmpty ? null : rawUserId;

    if (identical(database, _database) &&
        userId == _userId &&
        identical(libraryQueryRepository, _libraryQueryRepository) &&
        identical(trackProfileEditingService, _trackProfileEditingService) &&
        identical(artistCreationService, _artistCreationService) &&
        identical(playbackCoordinator, _playbackCoordinator)) {
      return;
    }

    _database = database;
    _userId = userId;
    _libraryQueryRepository = libraryQueryRepository;
    _artistCreationService = artistCreationService;
    _trackProfileEditingService = trackProfileEditingService;
    _playbackCoordinator = playbackCoordinator;
    _workflowService = null;
    _reviewService = null;

    final version = ++_initializationVersion;
    _initialize(
      database: database,
      userId: userId,
      libraryQueryRepository: libraryQueryRepository,
      trackProfileEditingService: trackProfileEditingService,
      artistCreationService: artistCreationService,
      playbackCoordinator: playbackCoordinator,
      version: version,
    );
  }

  Future<void> _initialize({
    required AppDatabase database,
    required String? userId,
    required LibraryQueryRepository? libraryQueryRepository,
    required TrackProfileEditingService? trackProfileEditingService,
    required ArtistCreationService? artistCreationService,
    required PlaybackCoordinator playbackCoordinator,
    required int version,
  }) async {
    final sqliteDatabase = await database.database;

    if (!mounted || version != _initializationVersion) {
      return;
    }

    final batchRepository = SqliteImportBatchRepository(
      ImportBatchDao(sqliteDatabase),
      appDatabase: database,
    );

    final importSourceRepository = SqliteImportSourceRepository(
      ImportSourceDao(sqliteDatabase),
      appDatabase: database,
    );

    // Standalone binding writes, such as reactivating an existing binding
    // during import, participate in restore admission.
    final mediaFileBindingRepository = SqliteMediaFileBindingRepository(
      MediaFileBindingDao(sqliteDatabase),
      appDatabase: database,
    );

    final trackLyricsRepository = SqliteTrackLyricsRepository(
      TrackLyricsDao(sqliteDatabase),
    );

    final reviewRepository = SqliteSongImportReviewRepository(
      SongImportReviewDao(sqliteDatabase),
    );
    final reviewCleanupService = ImportReviewCleanupService(
      reviewRepository: reviewRepository,
      songRepository: SqliteSongRepository(SongDao(sqliteDatabase)),
    );

    final reviewService =
        libraryQueryRepository != null &&
            trackProfileEditingService != null &&
            artistCreationService != null
        ? ImportReviewService(
            reviewRepository: reviewRepository,
            libraryQueryRepository: libraryQueryRepository,
            trackProfileEditingService: trackProfileEditingService,
            artistCreationService: artistCreationService,
          )
        : null;

    final mediaMetadataReader = MediaMetadataReader(
      saf: Platform.isAndroid ? _saf : null,
    );

    final metadataResolver = MetadataResolver(
      primaryReader: mediaMetadataReader,
      fallbackReader: const PathFallbackMetadataReader(),
    );

    final durationRepairService = ImportDurationRepairService(
      mediaFileBindingRepository: mediaFileBindingRepository,
      metadataReader: mediaMetadataReader,
      mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
    );

    final artistIdentityRepairService = MalformedArtistIdentityRepairService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
    );

    final artistIdentityRepairScanService =
        MalformedArtistIdentityRepairScanService(
          artistRepository: SqliteArtistRepository(ArtistDao(sqliteDatabase)),
          repairArtist: artistIdentityRepairService.repairArtist,
        );

    final atomicImporter = AtomicLibraryImporter(
      appDatabase: database,
      userId: userId,
    );

    final lyricsIngestionService = LyricsIngestionService(
      sourceReader: LocalLyricsSourceReader(
        saf: Platform.isAndroid ? _saf : null,
      ),
      trackLyricsRepository: trackLyricsRepository,
    );

    final libraryImportService = LibraryImportService(
      metadataResolver: metadataResolver,
      atomicImporter: atomicImporter,
      mediaFileBindingRepository: mediaFileBindingRepository,
      lyricsIngestionService: lyricsIngestionService,
    );

    final batchExecutor = ImportBatchExecutor(
      libraryImportService: libraryImportService,
      batchRepository: batchRepository,
    );

    final workflowService = ImportWorkflowService(
      candidateDiscovery: Platform.isAndroid
          ? SafImportCandidateDiscovery(saf: _saf)
          : const FileSystemImportCandidateDiscovery(),
      batchRunner: batchExecutor,
      importSourceRepository: importSourceRepository,
      mediaFileBindingRepository: mediaFileBindingRepository,
      onSongsBecameUnavailable: playbackCoordinator.removeSongsFromQueue,
      sourceReconciliationService: ImportSourceReconciliationService(
        appDatabase: database,
      ),
    );

    if (!mounted || version != _initializationVersion) {
      return;
    }

    setState(() {
      _workflowService = workflowService;
      _reviewService = reviewService;
    });

    if (!_durationRepairStarted) {
      _durationRepairStarted = true;

      unawaited(
        durationRepairService
            .repair(userId: userId)
            .then((_) => reviewCleanupService.cleanupStaleDurationReasons()),
      );
    }

    if (!_artistIdentityRepairStarted) {
      _artistIdentityRepairStarted = true;

      unawaited(artistIdentityRepairScanService.repairAll(userId: userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ImportWorkflowService?>.value(value: _workflowService),
        Provider<ImportReviewService?>.value(value: _reviewService),
        Provider<ImportSourcePicker>.value(
          value: FilePickerImportSourcePicker(saf: _saf),
        ),
      ],
      child: widget.child,
    );
  }
}
