import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/data/contracts/supabase_sync_contract.dart';

void main() {
  group('SupabaseSyncContract', () {
    test('declares only logical library tables as cloud tables', () {
      expect(SupabaseSyncContract.cloudTables, {
        'artists',
        'albums',
        'album_editions',
        'songs',
        'artwork_assets',
      });
    });

    test('keeps device-specific tables outside the cloud model', () {
      expect(SupabaseSyncContract.deviceLocalTables, {
        'media_file_bindings',
        'import_batches',
      });

      expect(
        SupabaseSyncContract.cloudTables.intersection(
          SupabaseSyncContract.deviceLocalTables,
        ),
        isEmpty,
      );
    });

    test('requires ownership and timestamps on cloud rows', () {
      expect(SupabaseSyncContract.requiredOwnedColumns, {
        'id',
        'user_id',
        'created_at',
        'updated_at',
        'server_updated_at',
        'deleted_at',
      });
    });

    test('declares song version metadata columns', () {
      expect(SupabaseSyncContract.versionLabelColumn, 'version_label');
      expect(
        SupabaseSyncContract.versionCharacteristicsColumn,
        'version_characteristics',
      );
      expect(SupabaseSyncContract.releaseStatusColumn, 'release_status');
      expect(SupabaseSyncContract.isLeakColumn, 'is_leak');
    });
    test('declares artwork storage separately from local file paths', () {
      expect(SupabaseSyncContract.artworkBucket, 'artwork');
      expect(SupabaseSyncContract.storageObjectKeyColumn, 'storage_object_key');
    });

    test('builds deterministic user-owned artwork object key', () {
      expect(
        SupabaseSyncContract.artworkObjectKey(
          userId: 'user_1',
          artworkId: 'artwork_1',
          extension: '.JPG',
        ),
        'user_1/artwork_1.jpg',
      );
    });

    test('rejects incomplete artwork object key components', () {
      expect(
        () => SupabaseSyncContract.artworkObjectKey(
          userId: ' ',
          artworkId: 'artwork_1',
          extension: 'jpg',
        ),
        throwsArgumentError,
      );

      expect(
        () => SupabaseSyncContract.artworkObjectKey(
          userId: 'user_1',
          artworkId: ' ',
          extension: 'jpg',
        ),
        throwsArgumentError,
      );

      expect(
        () => SupabaseSyncContract.artworkObjectKey(
          userId: 'user_1',
          artworkId: 'artwork_1',
          extension: ' ',
        ),
        throwsArgumentError,
      );
    });
  });
}
