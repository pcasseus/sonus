import 'metadata_field_state.dart';

enum MetadataMutationOrigin {
  userEdit,
  reviewConfirmation;

  MetadataAuthority get authority {
    return switch (this) {
      MetadataMutationOrigin.userEdit => MetadataAuthority.manual,
      MetadataMutationOrigin.reviewConfirmation => MetadataAuthority.confirmed,
    };
  }

  MetadataProvenanceSource get source {
    return switch (this) {
      MetadataMutationOrigin.userEdit => MetadataProvenanceSource.user,
      MetadataMutationOrigin.reviewConfirmation =>
        MetadataProvenanceSource.review,
    };
  }
}
