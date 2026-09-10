import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';

class LibraryImportService {
  const LibraryImportService({
    required this.metadataResolver,
    required this.atomicImporter,
  });

  final MetadataResolver metadataResolver;
  final AtomicLibraryImporter atomicImporter;

  Future<ImportResult> importCandidate(
    ImportCandidate candidate, {
    DateTime? now,
  }) async {
    try {
      final metadata = await metadataResolver.resolve(candidate);

      return atomicImporter.import(
        candidate: candidate,
        metadata: metadata,
        now: now,
      );
    } catch (error) {
      return ImportResult(
        status: ImportResultStatus.failed,
        filePath: candidate.filePath,
        failure: ImportFailure(
          type: ImportFailureType.metadataUnreadable,
          message: 'Unable to resolve audio metadata: $error',
        ),
      );
    }
  }
}
