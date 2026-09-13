import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  group('SyncDataContract', () {
    test('marks logical library entities as cloud data', () {
      expect(SyncDataContract.cloudEntities, {
        CloudDataEntity.artist,
        CloudDataEntity.album,
        CloudDataEntity.albumEdition,
        CloudDataEntity.song,
        CloudDataEntity.artworkAsset,
      });
    });

    test('keeps device-specific persistence out of cloud data', () {
      expect(SyncDataContract.deviceLocalEntities, {
        DeviceLocalDataEntity.mediaFileBinding,
        DeviceLocalDataEntity.importBatch,
      });
    });

    test('recognizes every declared cloud entity', () {
      for (final entity in CloudDataEntity.values) {
        expect(SyncDataContract.isCloudEntity(entity), isTrue);
      }
    });

    test('recognizes every declared device-local entity', () {
      for (final entity in DeviceLocalDataEntity.values) {
        expect(SyncDataContract.isDeviceLocalEntity(entity), isTrue);
      }
    });
  });
}
