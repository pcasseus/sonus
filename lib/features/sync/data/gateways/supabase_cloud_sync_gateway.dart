import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/cloud_sync_gateway.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/sync_data_contract.dart';
import '../contracts/supabase_sync_contract.dart';
import '../mappers/supabase_cloud_record_mapper.dart';

class SupabaseCloudSyncGateway implements CloudSyncGateway {
  const SupabaseCloudSyncGateway({required this.client});

  final SupabaseClient client;

  @override
  Future<void> upsert(CloudOwnedRecord record) async {
    final table = SupabaseCloudRecordMapper.tableFor(record);
    final row = SupabaseCloudRecordMapper.toRow(record);

    await client
        .from(table)
        .upsert(row, onConflict: SupabaseSyncContract.idColumn);
  }

  @override
  Future<void> markDeleted({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
  }) async {
    final table = _tableFor(entityType);

    await client
        .from(table)
        .update({
          SupabaseSyncContract.deletedAtColumn: deletedAt
              .toUtc()
              .toIso8601String(),
          SupabaseSyncContract.updatedAtColumn: deletedAt
              .toUtc()
              .toIso8601String(),
        })
        .eq(SupabaseSyncContract.userIdColumn, userId)
        .eq(SupabaseSyncContract.idColumn, entityId);
  }

  String _tableFor(CloudDataEntity entityType) {
    return switch (entityType) {
      CloudDataEntity.artist => SupabaseSyncContract.artistsTable,
      CloudDataEntity.album => SupabaseSyncContract.albumsTable,
      CloudDataEntity.albumEdition => SupabaseSyncContract.albumEditionsTable,
      CloudDataEntity.song => SupabaseSyncContract.songsTable,
      CloudDataEntity.artworkAsset => SupabaseSyncContract.artworkAssetsTable,
    };
  }
}
