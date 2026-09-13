import 'sync_data_contract.dart';

class SyncCursor {
  const SyncCursor({
    required this.userId,
    required this.entityType,
    required this.updatedAt,
    this.lastServerUpdatedAt,
    this.lastServerId,
  });

  final String userId;
  final CloudDataEntity entityType;
  final DateTime? lastServerUpdatedAt;
  final String? lastServerId;
  final DateTime updatedAt;
}

enum SyncOutboxOperation { upsert, delete }

class SyncOutboxEntry {
  const SyncOutboxEntry({
    required this.id,
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final CloudDataEntity entityType;
  final String entityId;
  final SyncOutboxOperation operation;
  final DateTime createdAt;
  final DateTime updatedAt;
}
