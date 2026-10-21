enum AccountRecoveryEligibilityStatus {
  eligible,
  authenticationRequired,
  accountBindingConflict,
}

class AccountRecoveryEligibility {
  const AccountRecoveryEligibility({
    required this.status,
    required this.requiresLocalBinding,
  });

  final AccountRecoveryEligibilityStatus status;
  final bool requiresLocalBinding;

  bool get canAssess => status == AccountRecoveryEligibilityStatus.eligible;

  bool get canRestore => canAssess && !requiresLocalBinding;
}
