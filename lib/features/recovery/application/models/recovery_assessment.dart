import 'recovery_coverage.dart';
import 'recovery_data_category.dart';

class RecoveryAssessment {
  RecoveryAssessment({required Iterable<RecoveryCoverage> coverage})
    : coverage = List<RecoveryCoverage>.unmodifiable(coverage) {
    final categories = this.coverage.map((entry) => entry.category).toSet();

    if (categories.length != this.coverage.length ||
        categories.length != RecoveryDataCategory.values.length) {
      throw ArgumentError(
        'Recovery assessment must contain every category exactly once.',
      );
    }
  }

  final List<RecoveryCoverage> coverage;

  RecoveryCoverage forCategory(RecoveryDataCategory category) {
    return coverage.firstWhere((entry) => entry.category == category);
  }

  bool get isFullyRecoverable => false;

  bool get hasUnverifiedCloudCoverage => coverage.any(
    (entry) => entry.isCloudSupported && entry.requiresVerification,
  );

  bool get hasUnsupportedCoverage => coverage.any(
    (entry) => entry.status == RecoveryCoverageStatus.notCloudSupported,
  );
}
