import '../models/external_metadata_candidate.dart';
import '../models/external_metadata_search_query.dart';

abstract interface class MetadataProvider {
  ExternalMetadataProviderKind get providerKind;

  Future<List<ExternalMetadataCandidate>> search(
    ExternalMetadataSearchQuery query,
  );

  Future<ExternalMetadataCandidate?> lookup({
    required ExternalMetadataEntityKind entityKind,
    required String providerEntityId,
  });
}
