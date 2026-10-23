import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/cloud_sync_reader.dart';
import '../../domain/models/sync_data_contract.dart';
import '../mappers/supabase_cloud_record_mapper.dart';
import 'supabase_cloud_sync_row_source.dart';

class SupabaseCloudSyncReader implements CloudSyncReader {
  SupabaseCloudSyncReader({required SupabaseClient client})
    : this.withRowSource(SupabaseClientCloudSyncRowSource(client: client));

  const SupabaseCloudSyncReader.withRowSource(this._rowSource);

  final SupabaseCloudSyncRowSource _rowSource;

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    final trimmedUserId = userId.trim();

    if (trimmedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be greater than zero.');
    }

    if (after != null && fromServerUpdatedAtInclusive != null) {
      throw ArgumentError(
        'after and fromServerUpdatedAtInclusive cannot both be provided.',
      );
    }

    final table = SupabaseCloudRecordMapper.tableForEntity(entityType);

    if (fromServerUpdatedAtInclusive != null) {
      final rows = await _rowSource.readFromServerTimestampInclusive(
        table: table,
        userId: trimmedUserId,
        serverUpdatedAt: fromServerUpdatedAtInclusive.toUtc(),
        limit: limit + 1,
      );

      return _pageFromRows(rows: rows, entityType: entityType, limit: limit);
    }

    if (after == null) {
      final rows = await _rowSource.readInitial(
        table: table,
        userId: trimmedUserId,
        limit: limit + 1,
      );

      return _pageFromRows(rows: rows, entityType: entityType, limit: limit);
    }

    final sameTimestampRows = await _rowSource.readAtCursorTimestamp(
      table: table,
      userId: trimmedUserId,
      serverUpdatedAt: after.serverUpdatedAt,
      afterId: after.id,
      limit: limit + 1,
    );

    final sameTimestampItems = _itemsFromRows(
      rows: sameTimestampRows,
      entityType: entityType,
    );

    if (sameTimestampItems.length > limit) {
      return CloudSyncPage(
        items: sameTimestampItems.take(limit).toList(growable: false),
        hasMore: true,
      );
    }

    final remaining = limit - sameTimestampItems.length;

    final laterRows = await _rowSource.readAfterCursorTimestamp(
      table: table,
      userId: trimmedUserId,
      serverUpdatedAt: after.serverUpdatedAt,
      limit: remaining + 1,
    );

    final laterItems = _itemsFromRows(rows: laterRows, entityType: entityType);

    final hasMore = laterItems.length > remaining;

    return CloudSyncPage(
      items: [...sameTimestampItems, ...laterItems.take(remaining)],
      hasMore: hasMore,
    );
  }

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    final trimmedUserId = userId.trim();
    final trimmedEntityId = entityId.trim();

    if (trimmedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    if (trimmedEntityId.isEmpty) {
      throw ArgumentError.value(entityId, 'entityId', 'Must not be blank.');
    }

    final rows = await _rowSource.readById(
      table: SupabaseCloudRecordMapper.tableForEntity(entityType),
      userId: trimmedUserId,
      id: trimmedEntityId,
    );

    if (rows.isEmpty) {
      return null;
    }

    if (rows.length > 1) {
      throw StateError('Cloud returned more than one row for $entityId.');
    }

    final item = SupabaseCloudRecordMapper.fromRow(
      entityType: entityType,
      row: rows.single,
    );

    if (item.record.userId != trimmedUserId ||
        item.record.id != trimmedEntityId) {
      throw StateError('Fetched cloud row does not match the requested owner.');
    }

    return item;
  }

  CloudSyncPage _pageFromRows({
    required List<Map<String, dynamic>> rows,
    required CloudDataEntity entityType,
    required int limit,
  }) {
    final items = _itemsFromRows(rows: rows, entityType: entityType);

    final hasMore = items.length > limit;

    return CloudSyncPage(
      items: hasMore ? items.take(limit).toList(growable: false) : items,
      hasMore: hasMore,
    );
  }

  List<CloudSyncItem> _itemsFromRows({
    required List<Map<String, dynamic>> rows,
    required CloudDataEntity entityType,
  }) {
    return rows
        .map(
          (row) => SupabaseCloudRecordMapper.fromRow(
            entityType: entityType,
            row: row,
          ),
        )
        .toList(growable: false);
  }
}
