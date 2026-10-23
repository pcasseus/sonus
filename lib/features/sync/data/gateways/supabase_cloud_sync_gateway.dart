import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/cloud_conditional_write_result.dart';
import '../../application/services/cloud_sync_gateway.dart';
import '../../application/services/cloud_sync_reader.dart';
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
  Future<CloudConditionalWriteResult> insertIfAbsent(
    CloudOwnedRecord record,
  ) async {
    if (record.isDeleted) {
      throw ArgumentError.value(record, 'record', 'Cannot insert a tombstone.');
    }

    final table = SupabaseCloudRecordMapper.tableFor(record);
    final row = SupabaseCloudRecordMapper.toRow(record);

    // INSERT ... ON CONFLICT (id) DO NOTHING never touches an existing row.
    final List<Map<String, dynamic>> inserted = await client
        .from(table)
        .upsert(
          row,
          onConflict: SupabaseSyncContract.idColumn,
          ignoreDuplicates: true,
        )
        .select(SupabaseSyncContract.serverRevisionColumn);

    if (inserted.isNotEmpty) {
      return _appliedResult(inserted);
    }

    return _observeUnapplied(table, record);
  }

  @override
  Future<CloudConditionalWriteResult> updateIfRevision(
    CloudOwnedRecord record, {
    required int expectedServerRevision,
  }) async {
    if (record.isDeleted) {
      throw ArgumentError.value(record, 'record', 'Cannot update a tombstone.');
    }

    if (expectedServerRevision < 1) {
      throw ArgumentError.value(
        expectedServerRevision,
        'expectedServerRevision',
        'Must be positive.',
      );
    }

    final table = SupabaseCloudRecordMapper.tableFor(record);
    final row = SupabaseCloudRecordMapper.toRow(record)
      ..remove(SupabaseSyncContract.idColumn)
      ..remove(SupabaseSyncContract.userIdColumn)
      ..remove(SupabaseSyncContract.createdAtColumn)
      ..remove(SupabaseSyncContract.deletedAtColumn);

    // A single compare-and-set UPDATE. Tombstones are never revived.
    final List<Map<String, dynamic>> updated = await client
        .from(table)
        .update(row)
        .eq(SupabaseSyncContract.userIdColumn, record.userId)
        .eq(SupabaseSyncContract.idColumn, record.id)
        .eq(SupabaseSyncContract.serverRevisionColumn, expectedServerRevision)
        .isFilter(SupabaseSyncContract.deletedAtColumn, null)
        .select(SupabaseSyncContract.serverRevisionColumn);

    if (updated.isNotEmpty) {
      return _appliedResult(updated);
    }

    return _observeUnapplied(table, record);
  }

  @override
  Future<CloudConditionalWriteResult> markDeletedIfRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
    required int expectedServerRevision,
  }) async {
    if (expectedServerRevision < 1) {
      throw ArgumentError.value(
        expectedServerRevision,
        'expectedServerRevision',
        'Must be positive.',
      );
    }

    final table = _tableFor(entityType);
    final timestamp = deletedAt.toUtc().toIso8601String();

    // A single compare-and-set UPDATE on a live row.
    final List<Map<String, dynamic>> updated = await client
        .from(table)
        .update({
          SupabaseSyncContract.deletedAtColumn: timestamp,
          SupabaseSyncContract.updatedAtColumn: timestamp,
        })
        .eq(SupabaseSyncContract.userIdColumn, userId)
        .eq(SupabaseSyncContract.idColumn, entityId)
        .eq(SupabaseSyncContract.serverRevisionColumn, expectedServerRevision)
        .isFilter(SupabaseSyncContract.deletedAtColumn, null)
        .select(SupabaseSyncContract.serverRevisionColumn);

    if (updated.isNotEmpty) {
      return _appliedResult(updated);
    }

    return _observeUnappliedRow(table, userId: userId, entityId: entityId);
  }

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    final List<Map<String, dynamic>> rows = await client
        .from(_tableFor(entityType))
        .select()
        .eq(SupabaseSyncContract.userIdColumn, userId)
        .eq(SupabaseSyncContract.idColumn, entityId)
        .limit(1);

    if (rows.isEmpty) {
      return null;
    }

    final item = SupabaseCloudRecordMapper.fromRow(
      entityType: entityType,
      row: rows.single,
    );

    if (item.record.userId != userId || item.record.id != entityId) {
      throw StateError('Fetched cloud row does not match the requested owner.');
    }

    return item;
  }

  CloudConditionalWriteResult _appliedResult(List<Map<String, dynamic>> rows) {
    if (rows.length != 1) {
      throw StateError('Expected exactly one conditionally written row.');
    }

    return CloudConditionalWriteResult.fromRpcRow({
      'outcome': 'applied',
      'server_revision': rows.single[SupabaseSyncContract.serverRevisionColumn],
    });
  }

  /// Reports the revision that prevented a write. Diagnostic only.
  Future<CloudConditionalWriteResult> _observeUnapplied(
    String table,
    CloudOwnedRecord record,
  ) {
    return _observeUnappliedRow(
      table,
      userId: record.userId,
      entityId: record.id,
    );
  }

  Future<CloudConditionalWriteResult> _observeUnappliedRow(
    String table, {
    required String userId,
    required String entityId,
  }) async {
    final List<Map<String, dynamic>> existing = await client
        .from(table)
        .select(SupabaseSyncContract.serverRevisionColumn)
        .eq(SupabaseSyncContract.userIdColumn, userId)
        .eq(SupabaseSyncContract.idColumn, entityId)
        .limit(1);

    if (existing.isEmpty) {
      return CloudConditionalWriteResult.fromRpcRow({
        'outcome': 'not_found',
        'server_revision': null,
      });
    }

    return CloudConditionalWriteResult.fromRpcRow({
      'outcome': 'conflict',
      'server_revision':
          existing.single[SupabaseSyncContract.serverRevisionColumn],
    });
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
