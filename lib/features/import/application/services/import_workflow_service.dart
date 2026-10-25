import '../../../../core/identity/entity_id.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../domain/entities/import_source.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/repositories/import_source_repository.dart';
import '../../domain/repositories/media_file_binding_repository.dart';
import '../../domain/services/import_candidate_discovery.dart';
import '../models/import_batch.dart';
import '../models/import_batch_item.dart';
import '../models/import_execution_summary.dart';
import 'import_batch_runner.dart';
import 'import_source_reconciliation_service.dart';

typedef ImportBatchIdFactory = String Function();
typedef ImportSourceIdFactory = String Function();
typedef SongsBecameUnavailableCallback =
    Future<void> Function(Set<String> songIds);

class ImportWorkflowService {
  const ImportWorkflowService({
    required this.candidateDiscovery,
    required this.batchRunner,
    this.importSourceRepository,
    this.mediaFileBindingRepository,
    this.onSongsBecameUnavailable,
    this.sourceReconciliationService,
    this.batchIdFactory = EntityId.importBatch,
    this.sourceIdFactory = EntityId.importSource,
    this.changes,
  });

  final ImportCandidateDiscovery candidateDiscovery;
  final ImportBatchRunner batchRunner;
  final ImportSourceRepository? importSourceRepository;
  final MediaFileBindingRepository? mediaFileBindingRepository;
  final SongsBecameUnavailableCallback? onSongsBecameUnavailable;
  final ImportSourceReconciliationService? sourceReconciliationService;
  final ImportBatchIdFactory batchIdFactory;
  final ImportSourceIdFactory sourceIdFactory;

  /// Told when an import finishes; [LibraryChangeSignal.shared] if null.
  final LibraryChangeSignal? changes;

  Future<ImportExecutionSummary> importSingleSong(
    String filePath, {
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  }) async {
    final timestamp = createdAt ?? DateTime.now();

    final candidate = await candidateDiscovery.discoverFile(
      filePath,
      discoveredAt: timestamp,
    );

    return _executeCandidates(
      [candidate],
      createdAt: timestamp,
      startedAt: startedAt,
      completedAt: completedAt,
      onProgress: onProgress,
    );
  }

  Future<ImportExecutionSummary> importStructuredFolder(
    String rootPath, {
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  }) async {
    final timestamp = createdAt ?? DateTime.now();

    final source = await _getOrCreateSource(rootPath, timestamp: timestamp);

    final discovered = await candidateDiscovery.discoverFolder(
      rootPath,
      discoveredAt: timestamp,
    );

    final candidates = source == null
        ? discovered
        : discovered
              .map((candidate) => candidate.copyWith(sourceId: source.id))
              .toList(growable: false);

    final summary = await _executeCandidates(
      candidates,
      createdAt: timestamp,
      startedAt: startedAt,
      completedAt: completedAt,
      onProgress: onProgress,
    );

    if (source != null) {
      await _reconcileSource(
        source,
        candidates,
        discoveredAt: timestamp,
        scannedAt: completedAt ?? DateTime.now(),
      );
    }

    return summary;
  }

  Future<ImportExecutionSummary> rescanSource(
    String sourceId, {
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  }) async {
    final sourceRepository = importSourceRepository;

    if (sourceRepository == null) {
      throw StateError('Import source persistence is unavailable.');
    }

    final source = await sourceRepository.getById(sourceId);

    if (source == null) {
      throw StateError('Import source not found: $sourceId');
    }

    final timestamp = createdAt ?? DateTime.now();

    final discovered = await candidateDiscovery.discoverFolder(
      source.rootPath,
      discoveredAt: timestamp,
    );

    final candidates = discovered
        .map((candidate) => candidate.copyWith(sourceId: source.id))
        .toList(growable: false);

    final summary = await _executeCandidates(
      candidates,
      createdAt: timestamp,
      startedAt: startedAt,
      completedAt: completedAt,
      onProgress: onProgress,
    );

    await _reconcileSource(
      source,
      candidates,
      discoveredAt: timestamp,
      scannedAt: completedAt ?? DateTime.now(),
    );

    return summary;
  }

  Future<List<ImportSource>> getSources() {
    final repository = importSourceRepository;

    if (repository == null) {
      return Future<List<ImportSource>>.value(const []);
    }

    return repository.getAll();
  }

  Future<ImportSource?> _getOrCreateSource(
    String rootPath, {
    required DateTime timestamp,
  }) async {
    final repository = importSourceRepository;

    if (repository == null) {
      return null;
    }

    final trimmedRoot = rootPath.trim();
    final normalizedRoot = TextNormalizer.normalizePath(trimmedRoot);

    final existing = await repository.getByNormalizedRootPath(normalizedRoot);

    if (existing != null) {
      return existing;
    }

    final source = ImportSource(
      id: sourceIdFactory(),
      rootPath: trimmedRoot,
      normalizedRootPath: normalizedRoot,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    await repository.create(source);

    return source;
  }

  Future<void> _reconcileSource(
    ImportSource source,
    List<ImportCandidate> candidates, {
    required DateTime discoveredAt,
    required DateTime scannedAt,
  }) async {
    final sourceRepository = importSourceRepository;
    final bindingRepository = mediaFileBindingRepository;

    if (sourceRepository == null || bindingRepository == null) {
      return;
    }

    final seenPaths = candidates
        .map((candidate) => candidate.normalizedPath)
        .toSet();

    final reconciler = sourceReconciliationService;
    if (reconciler != null) {
      await reconciler.reconcile(
        sourceId: source.id,
        seenPaths: seenPaths,
        discoveredAt: discoveredAt,
        scannedAt: scannedAt,
        onSongsBecameUnavailable: onSongsBecameUnavailable,
      );
      return;
    }

    final bindings = await bindingRepository.getBySourceId(source.id);
    final potentiallyUnavailableSongIds = <String>{};

    for (final binding in bindings) {
      if (seenPaths.contains(binding.normalizedPath)) {
        continue;
      }

      if (!binding.isAvailable) {
        continue;
      }

      await bindingRepository.save(
        binding.copyWith(isAvailable: false, updatedAt: scannedAt),
      );

      potentiallyUnavailableSongIds.add(binding.songId);
    }

    await sourceRepository.save(
      source.copyWith(lastScannedAt: scannedAt, updatedAt: scannedAt),
    );

    final callback = onSongsBecameUnavailable;

    if (callback == null || potentiallyUnavailableSongIds.isEmpty) {
      return;
    }

    final unavailableSongIds = <String>{};

    for (final songId in potentiallyUnavailableSongIds) {
      final songBindings = await bindingRepository.getBySongId(songId);

      final hasUsableBinding = songBindings.any(
        (binding) => binding.isAvailable && binding.filePath.trim().isNotEmpty,
      );

      if (!hasUsableBinding) {
        unavailableSongIds.add(songId);
      }
    }

    if (unavailableSongIds.isNotEmpty) {
      await callback(Set<String>.unmodifiable(unavailableSongIds));
    }
  }

  Future<ImportExecutionSummary> _executeCandidates(
    List<ImportCandidate> candidates, {
    required DateTime createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  }) async {
    final batch = ImportBatch(
      id: batchIdFactory(),
      items: List.unmodifiable(
        candidates.map((candidate) => ImportBatchItem(candidate: candidate)),
      ),
      createdAt: createdAt,
    );

    final summary = await batchRunner.execute(
      batch,
      startedAt: startedAt,
      completedAt: completedAt,
      onProgress: onProgress,
    );

    (changes ?? LibraryChangeSignal.shared).notify(
      LibraryChangeKind.importCompleted,
    );

    return summary;
  }
}
