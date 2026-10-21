import '../models/account_recovery_eligibility.dart';
import '../models/cloud_recovery_consistency.dart';
import '../models/recovery_readiness_report.dart';
import 'account_recovery_eligibility_service.dart';
import 'cloud_recovery_consistency_probe.dart';
import 'recovery_contract_service.dart';

class RecoveryReadinessService {
  const RecoveryReadinessService({
    required this.eligibilityService,
    required this.consistencyProbe,
    this.contractService = const RecoveryContractService(),
  });

  final AccountRecoveryEligibilityService eligibilityService;
  final CloudRecoveryConsistencyProbe consistencyProbe;
  final RecoveryContractService contractService;

  Future<RecoveryReadinessReport> assess({
    required String? authenticatedUserId,
    int pageSize = 100,
  }) async {
    final coverage = contractService.assess();

    if (pageSize <= 0) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Must be greater than zero.',
      );
    }

    AccountRecoveryEligibility eligibility;

    try {
      eligibility = await eligibilityService.assess(
        authenticatedUserId: authenticatedUserId,
      );
    } catch (_) {
      return RecoveryReadinessReport(
        status: RecoveryReadinessStatus.assessmentInterrupted,
        coverage: coverage,
        failureReason: 'Account eligibility could not be assessed.',
      );
    }

    switch (eligibility.status) {
      case AccountRecoveryEligibilityStatus.authenticationRequired:
        return RecoveryReadinessReport(
          status: RecoveryReadinessStatus.authenticationRequired,
          coverage: coverage,
          accountEligibility: eligibility,
        );

      case AccountRecoveryEligibilityStatus.accountBindingConflict:
        return RecoveryReadinessReport(
          status: RecoveryReadinessStatus.accountConflict,
          coverage: coverage,
          accountEligibility: eligibility,
        );

      case AccountRecoveryEligibilityStatus.eligible:
        break;
    }

    final userId = authenticatedUserId!.trim();

    try {
      final inventory = await consistencyProbe.inspect(
        userId: userId,
        pageSize: pageSize,
      );

      final status = switch (inventory.consistency.status) {
        CloudRecoveryConsistencyStatus.observedInstability =>
          RecoveryReadinessStatus.observedInstability,

        CloudRecoveryConsistencyStatus.unverified ||
        CloudRecoveryConsistencyStatus.verified =>
          inventory.hasDependencyIssues
              ? RecoveryReadinessStatus.incompleteDependencies
              : inventory.totalActive == 0
              ? RecoveryReadinessStatus.emptyCloud
              : RecoveryReadinessStatus.incompleteCoverage,
      };

      return RecoveryReadinessReport(
        status: status,
        coverage: coverage,
        accountEligibility: eligibility,
        inventory: inventory,
      );
    } catch (_) {
      return RecoveryReadinessReport(
        status: RecoveryReadinessStatus.assessmentInterrupted,
        coverage: coverage,
        accountEligibility: eligibility,
        failureReason: 'Cloud recovery assessment could not be completed.',
      );
    }
  }
}
