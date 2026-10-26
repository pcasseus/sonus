import '../../domain/metadata/metadata_field_state.dart';
import 'external_metadata_candidate.dart';

enum ExternalMetadataProposalFieldStatus {
  valueChange,
  provenanceOnly,
  unchanged,
  protected,
  reviewRequired,
  notProposed,
}

class ExternalMetadataProposalField {
  const ExternalMetadataProposalField({
    required this.fieldName,
    required this.currentValue,
    required this.proposedValue,
    required this.status,
    this.existingState,
    this.note,
  });

  final String fieldName;
  final Object? currentValue;
  final Object? proposedValue;
  final ExternalMetadataProposalFieldStatus status;
  final MetadataFieldState? existingState;

  /// Where the proposed value comes from, when that is not obvious, such
  /// as which of a release's dates is proposed.
  final String? note;

  bool get willChangeValue =>
      status == ExternalMetadataProposalFieldStatus.valueChange;

  bool get willUpdateProvenance =>
      status == ExternalMetadataProposalFieldStatus.valueChange ||
      status == ExternalMetadataProposalFieldStatus.provenanceOnly;

  bool get isProtected =>
      status == ExternalMetadataProposalFieldStatus.protected;

  bool get requiresReview =>
      status == ExternalMetadataProposalFieldStatus.reviewRequired;
}

class ExternalMetadataProposal {
  const ExternalMetadataProposal({
    required this.entityType,
    required this.entityId,
    required this.candidate,
    required this.fields,
  });

  final MetadataEntityType entityType;
  final String entityId;
  final ExternalMetadataCandidate candidate;
  final List<ExternalMetadataProposalField> fields;

  bool get hasValueChanges => fields.any((field) => field.willChangeValue);

  bool get hasProvenanceUpdates =>
      fields.any((field) => field.willUpdateProvenance);

  bool get hasProtectedFields => fields.any((field) => field.isProtected);

  bool get requiresReview => fields.any((field) => field.requiresReview);

  bool get hasApplicableChanges => hasValueChanges || hasProvenanceUpdates;
}
