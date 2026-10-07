import '../metadata/metadata_field_state.dart';

enum MetadataReplacementDecision {
  accept,
  rejectLowerAuthority,
  requireReviewUnknownAuthority,
}

abstract final class MetadataAuthorityPolicy {
  static MetadataReplacementDecision evaluate({
    MetadataFieldState? existing,
    required MetadataAuthority incomingAuthority,
  }) {
    if (existing == null) {
      return MetadataReplacementDecision.accept;
    }

    if (_rank(incomingAuthority) >= _rank(existing.authority)) {
      return MetadataReplacementDecision.accept;
    }

    return MetadataReplacementDecision.rejectLowerAuthority;
  }

  static bool canReplace({
    MetadataFieldState? existing,
    required MetadataAuthority incomingAuthority,
  }) {
    return evaluate(existing: existing, incomingAuthority: incomingAuthority) ==
        MetadataReplacementDecision.accept;
  }

  static MetadataReplacementDecision evaluateAutomaticReplacement({
    required bool existingValuePresent,
    MetadataFieldState? existing,
    required MetadataAuthority incomingAuthority,
  }) {
    if (!existingValuePresent) {
      return MetadataReplacementDecision.accept;
    }

    if (existing == null) {
      return MetadataReplacementDecision.requireReviewUnknownAuthority;
    }

    return evaluate(existing: existing, incomingAuthority: incomingAuthority);
  }

  static bool canAutomaticallyReplace({
    required bool existingValuePresent,
    MetadataFieldState? existing,
    required MetadataAuthority incomingAuthority,
  }) {
    return evaluateAutomaticReplacement(
          existingValuePresent: existingValuePresent,
          existing: existing,
          incomingAuthority: incomingAuthority,
        ) ==
        MetadataReplacementDecision.accept;
  }

  static int _rank(MetadataAuthority authority) {
    return switch (authority) {
      MetadataAuthority.inferred => 0,
      MetadataAuthority.imported => 1,
      MetadataAuthority.external => 2,
      MetadataAuthority.confirmed => 3,
      MetadataAuthority.manual => 4,
    };
  }
}
