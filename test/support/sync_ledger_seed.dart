import 'package:sqflite/sqflite.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';

import 'library_seed.dart';

/// A durable inbound replay obligation for [entityId].
Future<void> seedDeferredRecord(
  DatabaseExecutor db, {
  required String userId,
  required String entityId,
  String entityType = 'song',
  int serverRevision = 2,
}) => db.insert(SyncSchema.inboundDeferredRecordsTable, {
  'user_id': userId,
  'entity_type': entityType,
  'entity_id': entityId,
  'server_revision': serverRevision,
  'server_updated_at': fixtureTimestamp,
  'reason': 'missingLocalParent',
  'deferred_at': fixtureTimestamp,
});

/// A recorded outbound conflict for [entityId].
Future<void> seedOutboundConflict(
  DatabaseExecutor db, {
  required String userId,
  required String entityId,
  String outboxId = 'outbox-conflict',
  String entityType = 'song',
}) => db.insert(SyncSchema.outboundConflictsTable, {
  'user_id': userId,
  'entity_type': entityType,
  'entity_id': entityId,
  'outbox_id': outboxId,
  'mutation_revision': 1,
  'operation': 'upsert',
  'expected_server_revision': 1,
  'observed_server_revision': 2,
  'observed_state': 'live',
  'detected_at': fixtureTimestamp,
});
