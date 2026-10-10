import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../../library/domain/services/metadata_authority_policy.dart';

abstract final class AlbumEditionArtworkAuthority {
  static MetadataReplacementDecision evaluateAutomatic({
    required String? currentArtworkId,
    required MetadataFieldState? currentState,
  }) {
    return MetadataAuthorityPolicy.evaluateAutomaticReplacement(
      existingValuePresent:
          currentArtworkId != null && currentArtworkId.trim().isNotEmpty,
      existing: currentState,
      incomingAuthority: MetadataAuthority.external,
    );
  }
}
