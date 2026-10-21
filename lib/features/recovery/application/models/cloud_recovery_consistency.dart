enum CloudRecoveryConsistencyStatus {
  observedInstability,
  unverified,
  verified,
}

class CloudRecoveryConsistency {
  const CloudRecoveryConsistency({required this.status, this.reason});

  final CloudRecoveryConsistencyStatus status;
  final String? reason;

  bool get isVerified => status == CloudRecoveryConsistencyStatus.verified;

  bool get hasObservedInstability =>
      status == CloudRecoveryConsistencyStatus.observedInstability;
}
