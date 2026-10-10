import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../../library/domain/services/metadata_authority_policy.dart';

abstract final class AlbumEditionArtworkAuthority {
  static MetadataReplacementDecision evaluateAutomatic({
    required String? currentArtworkId,
    required MetadataFieldState? currentState,
  }) {
    // An empty artwork ID with manual authority represents a user choice
    // to leave the edition without artwork. Do not refill it automatically.
    if ((currentArtworkId == null || currentArtworkId.trim().isEmpty) &&
        currentState?.authority == MetadataAuthority.manual) {
      return MetadataReplacementDecision.rejectLowerAuthority;
    }

    return MetadataAuthorityPolicy.evaluateAutomaticReplacement(
      existingValuePresent:
          currentArtworkId != null && currentArtworkId.trim().isNotEmpty,
      existing: currentState,
      incomingAuthority: MetadataAuthority.external,
    );
  }
}
