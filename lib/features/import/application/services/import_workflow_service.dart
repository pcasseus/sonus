import '../../../../core/identity/entity_id.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/services/import_candidate_discovery.dart';
import '../models/import_batch.dart';
import '../models/import_batch_item.dart';
import '../models/import_execution_summary.dart';
import 'import_batch_runner.dart';

typedef ImportBatchIdFactory = String Function();

class ImportWorkflowService {
  const ImportWorkflowService({
    required this.candidateDiscovery,
    required this.batchRunner,
    this.batchIdFactory = EntityId.importBatch,
  });

  final ImportCandidateDiscovery candidateDiscovery;
  final ImportBatchRunner batchRunner;
  final ImportBatchIdFactory batchIdFactory;

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

    final candidates = await candidateDiscovery.discoverFolder(
      rootPath,
      discoveredAt: timestamp,
    );

    return _executeCandidates(
      candidates,
      createdAt: timestamp,
      startedAt: startedAt,
      completedAt: completedAt,
      onProgress: onProgress,
    );
  }

  Future<ImportExecutionSummary> _executeCandidates(
    List<ImportCandidate> candidates, {
    required DateTime createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  }) {
    final batch = ImportBatch(
      id: batchIdFactory(),
      items: List.unmodifiable(
        candidates.map((candidate) => ImportBatchItem(candidate: candidate)),
      ),
      createdAt: createdAt,
    );

    return batchRunner.execute(
      batch,
      startedAt: startedAt,
      completedAt: completedAt,
      onProgress: onProgress,
    );
  }
}
