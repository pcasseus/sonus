import 'account_recovery_eligibility.dart';
import 'cloud_recovery_inventory.dart';
import 'recovery_assessment.dart';

enum RecoveryReadinessStatus {
  authenticationRequired,
  accountConflict,
  assessmentInterrupted,
  emptyCloud,
  observedInstability,
  incompleteDependencies,
  incompleteCoverage,
}

class RecoveryReadinessReport {
  const RecoveryReadinessReport({
    required this.status,
    required this.coverage,
    this.accountEligibility,
    this.inventory,
    this.failureReason,
  });

  final RecoveryReadinessStatus status;
  final RecoveryAssessment coverage;
  final AccountRecoveryEligibility? accountEligibility;
  final CloudRecoveryInventory? inventory;
  final String? failureReason;

  bool get canRestore => false;

  bool get assessmentInterrupted =>
      status == RecoveryReadinessStatus.assessmentInterrupted;

  bool get accountEligible => accountEligibility?.canAssess ?? false;

  bool get hasVerifiedCloudSnapshot =>
      inventory?.consistency.isVerified ?? false;

  bool get hasDependencyIssues => inventory?.hasDependencyIssues ?? false;

  bool get hasUnsupportedCoverage => coverage.hasUnsupportedCoverage;

  bool get hasCloudRecords => inventory?.hasCloudRecords ?? false;
}
