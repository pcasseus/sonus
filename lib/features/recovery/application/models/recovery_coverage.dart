import 'recovery_data_category.dart';

enum RecoveryCoverageStatus { cloudSupported, notCloudSupported, deviceLocal }

class RecoveryCoverage {
  const RecoveryCoverage({
    required this.category,
    required this.status,
    required this.requiresVerification,
  });

  final RecoveryDataCategory category;
  final RecoveryCoverageStatus status;
  final bool requiresVerification;

  bool get isCloudSupported => status == RecoveryCoverageStatus.cloudSupported;

  bool get isDeviceLocal => status == RecoveryCoverageStatus.deviceLocal;
}
