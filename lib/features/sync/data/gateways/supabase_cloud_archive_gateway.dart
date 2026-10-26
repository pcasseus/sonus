import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/cloud_archive_gateway.dart';
import '../../domain/models/cloud_archive_record.dart';

/// The archive table added by migration 20261026000001.
class SupabaseCloudArchiveGateway implements CloudArchiveGateway {
  SupabaseCloudArchiveGateway({required this.client});

  final SupabaseClient client;

  static const table = 'sonus_archive_records';
  static const libraryId = 'main';
  static const _conflictTarget = 'user_id,library_id,kind,record_key';

  bool? _available;

  @override
  Future<bool> isAvailable() async {
    final known = _available;
    if (known != null) return known;

    try {
      await client.from(table).select('record_key').limit(0);
      return _available = true;
    } on PostgrestException catch (error) {
      // Only a definite "no such table" means the server lacks the archive.
      if (error.code == 'PGRST205' || error.code == '42P01') {
        return _available = false;
      }
      rethrow;
    }
  }

  /// Kinds added by a newer app version are left alone, not misread.
  PostgrestFilterBuilder<List<Map<String, dynamic>>> _owned(String userId) =>
      client
          .from(table)
          .select()
          .eq('user_id', userId)
          .eq('library_id', libraryId)
          .inFilter('kind', [
            for (final kind in CloudArchiveKind.values) kind.wireName,
          ]);

  @override
  Future<List<CloudArchiveRecord>> readPage({
    required String userId,
    CloudArchiveCursor? after,
    required int limit,
  }) async {
    if (after == null) {
      final rows = await _owned(
        userId,
      ).order('server_updated_at').order('record_id').limit(limit);
      return [for (final row in rows) _fromRow(row)];
    }

    final at = after.serverUpdatedAt.toUtc().toIso8601String();
    final same = await _owned(userId)
        .eq('server_updated_at', at)
        .gt('record_id', after.recordId)
        .order('record_id')
        .limit(limit);
    final records = [for (final row in same) _fromRow(row)];

    if (records.length < limit) {
      final later = await _owned(userId)
          .gt('server_updated_at', at)
          .order('server_updated_at')
          .order('record_id')
          .limit(limit - records.length);
      records.addAll([for (final row in later) _fromRow(row)]);
    }
    return records;
  }

  @override
  Future<List<CloudArchiveRecord>> fetch({
    required String userId,
    required CloudArchiveKind kind,
    required List<String> keys,
  }) async {
    if (keys.isEmpty) return const [];
    final rows = await _owned(
      userId,
    ).eq('kind', kind.wireName).inFilter('record_key', keys);
    return [for (final row in rows) _fromRow(row)];
  }

  @override
  Future<CloudArchiveWriteResult> insertIfAbsent({
    required String userId,
    required CloudArchiveRecord record,
  }) async {
    final List<Map<String, dynamic>> inserted = await client
        .from(table)
        .upsert(
          _toRow(userId, record),
          onConflict: _conflictTarget,
          ignoreDuplicates: true,
        )
        .select('server_revision');
    return _result(inserted);
  }

  @override
  Future<CloudArchiveWriteResult> updateIfRevision({
    required String userId,
    required CloudArchiveRecord record,
    required int expectedServerRevision,
  }) async {
    final List<Map<String, dynamic>> updated = await client
        .from(table)
        .update({
          'payload': record.payload,
          'is_deleted': record.isDeleted,
          'client_updated_at': record.clientUpdatedAt.toUtc().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('library_id', libraryId)
        .eq('kind', record.kind.wireName)
        .eq('record_key', record.key)
        .eq('server_revision', expectedServerRevision)
        .select('server_revision');
    return _result(updated);
  }

  static CloudArchiveWriteResult _result(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const CloudArchiveWriteResult(CloudArchiveWriteOutcome.conflict);
    }
    return CloudArchiveWriteResult(
      CloudArchiveWriteOutcome.applied,
      rows.single['server_revision'] as int,
    );
  }

  static Map<String, Object?> _toRow(
    String userId,
    CloudArchiveRecord record,
  ) => {
    'user_id': userId,
    'library_id': libraryId,
    'kind': record.kind.wireName,
    'record_key': record.key,
    'payload': record.payload,
    'is_deleted': record.isDeleted,
    'client_updated_at': record.clientUpdatedAt.toUtc().toIso8601String(),
  };

  static CloudArchiveRecord _fromRow(Map<String, dynamic> row) {
    final kind = CloudArchiveKind.fromWire(row['kind'] as String);
    if (kind == null) {
      throw StateError('Unknown archive kind ${row['kind']}.');
    }
    return CloudArchiveRecord(
      kind: kind,
      key: row['record_key'] as String,
      payload: Map<String, Object?>.from(row['payload'] as Map),
      isDeleted: row['is_deleted'] as bool? ?? false,
      clientUpdatedAt: DateTime.parse(
        row['client_updated_at'] as String,
      ).toUtc(),
      serverRevision: row['server_revision'] as int?,
      serverUpdatedAt: DateTime.parse(
        row['server_updated_at'] as String,
      ).toUtc(),
    );
  }
}
