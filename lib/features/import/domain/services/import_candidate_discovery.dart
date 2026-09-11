import '../models/import_candidate.dart';

abstract interface class ImportCandidateDiscovery {
  Future<ImportCandidate> discoverFile(
    String filePath, {
    DateTime? discoveredAt,
  });

  Future<List<ImportCandidate>> discoverFolder(
    String rootPath, {
    DateTime? discoveredAt,
  });
}
