import 'package:supabase_flutter/supabase_flutter.dart';

import '../contracts/supabase_sync_contract.dart';

abstract interface class SupabaseCloudSyncRowSource {
  Future<List<Map<String, dynamic>>> readInitial({
    required String table,
    required String userId,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> readFromServerTimestampInclusive({
    required String table,
    required String userId,
    required DateTime serverUpdatedAt,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> readAtCursorTimestamp({
    required String table,
    required String userId,
    required DateTime serverUpdatedAt,
    required String afterId,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> readAfterCursorTimestamp({
    required String table,
    required String userId,
    required DateTime serverUpdatedAt,
    required int limit,
  });
}

class SupabaseClientCloudSyncRowSource implements SupabaseCloudSyncRowSource {
  const SupabaseClientCloudSyncRowSource({required this.client});

  final SupabaseClient client;

  @override
  Future<List<Map<String, dynamic>>> readInitial({
    required String table,
    required String userId,
    required int limit,
  }) {
    return client
        .from(table)
        .select()
        .eq(SupabaseSyncContract.userIdColumn, userId)
        .order(SupabaseSyncContract.serverUpdatedAtColumn, ascending: true)
        .order(SupabaseSyncContract.idColumn, ascending: true)
        .limit(limit);
  }

  @override
  Future<List<Map<String, dynamic>>> readFromServerTimestampInclusive({
    required String table,
    required String userId,
    required DateTime serverUpdatedAt,
    required int limit,
  }) {
    return client
        .from(table)
        .select()
        .eq(SupabaseSyncContract.userIdColumn, userId)
        .gte(
          SupabaseSyncContract.serverUpdatedAtColumn,
          serverUpdatedAt.toUtc().toIso8601String(),
        )
        .order(SupabaseSyncContract.serverUpdatedAtColumn, ascending: true)
        .order(SupabaseSyncContract.idColumn, ascending: true)
        .limit(limit);
  }

  @override
  Future<List<Map<String, dynamic>>> readAtCursorTimestamp({
    required String table,
    required String userId,
    required DateTime serverUpdatedAt,
    required String afterId,
    required int limit,
  }) {
    return client
        .from(table)
        .select()
        .eq(SupabaseSyncContract.userIdColumn, userId)
        .eq(
          SupabaseSyncContract.serverUpdatedAtColumn,
          serverUpdatedAt.toUtc().toIso8601String(),
        )
        .gt(SupabaseSyncContract.idColumn, afterId)
        .order(SupabaseSyncContract.idColumn, ascending: true)
        .limit(limit);
  }

  @override
  Future<List<Map<String, dynamic>>> readAfterCursorTimestamp({
    required String table,
    required String userId,
    required DateTime serverUpdatedAt,
    required int limit,
  }) {
    return client
        .from(table)
        .select()
        .eq(SupabaseSyncContract.userIdColumn, userId)
        .gt(
          SupabaseSyncContract.serverUpdatedAtColumn,
          serverUpdatedAt.toUtc().toIso8601String(),
        )
        .order(SupabaseSyncContract.serverUpdatedAtColumn, ascending: true)
        .order(SupabaseSyncContract.idColumn, ascending: true)
        .limit(limit);
  }
}
