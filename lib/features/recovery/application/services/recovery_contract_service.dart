import '../../../sync/domain/models/sync_data_contract.dart';
import '../models/recovery_assessment.dart';
import '../models/recovery_coverage.dart';
import '../models/recovery_data_category.dart';

class RecoveryContractService {
  const RecoveryContractService();

  static const Map<RecoveryDataCategory, CloudDataEntity> _cloudMappings = {
    RecoveryDataCategory.artist: CloudDataEntity.artist,
    RecoveryDataCategory.album: CloudDataEntity.album,
    RecoveryDataCategory.albumEdition: CloudDataEntity.albumEdition,
    RecoveryDataCategory.song: CloudDataEntity.song,
    RecoveryDataCategory.artworkAsset: CloudDataEntity.artworkAsset,
  };

  static const Map<RecoveryDataCategory, DeviceLocalDataEntity>
  _deviceLocalMappings = {
    RecoveryDataCategory.mediaFileBindings:
        DeviceLocalDataEntity.mediaFileBinding,
    RecoveryDataCategory.importBatches: DeviceLocalDataEntity.importBatch,
  };

  RecoveryAssessment assess() {
    return RecoveryAssessment(
      coverage: [
        for (final category in RecoveryDataCategory.values)
          _coverageFor(category),
      ],
    );
  }

  RecoveryCoverage _coverageFor(RecoveryDataCategory category) {
    final cloudEntity = _cloudMappings[category];

    if (cloudEntity != null && SyncDataContract.isCloudEntity(cloudEntity)) {
      return RecoveryCoverage(
        category: category,
        status: RecoveryCoverageStatus.cloudSupported,
        requiresVerification: true,
      );
    }

    final deviceLocalEntity = _deviceLocalMappings[category];

    if (deviceLocalEntity != null &&
        SyncDataContract.isDeviceLocalEntity(deviceLocalEntity)) {
      return RecoveryCoverage(
        category: category,
        status: RecoveryCoverageStatus.deviceLocal,
        requiresVerification: false,
      );
    }

    return RecoveryCoverage(
      category: category,
      status: RecoveryCoverageStatus.notCloudSupported,
      requiresVerification: false,
    );
  }
}
