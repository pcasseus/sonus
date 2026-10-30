// SN-50 #23: an inbound record and its cursor commit together or not at
// all, also when the run is cancelled while it is being applied.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/inbound_cloud_record_applier.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_reconciler.dart';
import 'package:sonus_next/features/sync/application/services/sync_cancellation.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_context.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;
  late SyncMutationTransactionRunner runner;
  late _Reader reader;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await appDatabase.database;
    runner = SyncMutationTransactionRunner(appDatabase: appDatabase);
    reader = _Reader();
  });

  tearDown(() => appDatabase.close());

  InboundSyncReconciler reconciler({InboundCloudRecordApplier? applier}) {
    return InboundSyncReconciler(
      reader: reader,
      localSyncRepository: SqliteLocalSyncRepository(
        dao: LocalSyncDao(db),
        generateId: () => 'outbox-id',
        now: () => DateTime.utc(2026, 10, 16, 12),
      ),
      mutationRunner: runner,
      applier: applier,
    );
  }

  Future<({bool a1, bool a2, String? cursor})> stored() {
    return runner.run((context) async {
      final cursor = await context.localSyncRepository.getCursor(
        'user-1',
        CloudDataEntity.artist,
      );
      return (
        a1: await context.artistRepository.getById('artist-1') != null,
        a2: await context.artistRepository.getById('artist-2') != null,
        cursor: cursor?.lastServerId,
      );
    });
  }

  test('a run cancelled while a record is applied rolls that record and its '
      'cursor back whole; earlier records stay', () async {
    reader.items = [_artist('artist-1', 10), _artist('artist-2', 11)];
    final cancellation = SyncCancellation('user-1');

    await expectLater(
      cancellation.run(
        () =>
            reconciler(
              applier: _CancelAfterApplying('artist-2', cancellation),
            ).reconcilePage(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              limit: 10,
            ),
      ),
      throwsA(isA<SyncCancelled>()),
    );

    final after = await stored();
    expect(after.a1, isTrue);
    expect(after.a2, isFalse, reason: 'rolled back with its transaction');
    expect(after.cursor, 'artist-1');
  });

  test(
    'a page that arrives after the run was cancelled applies nothing',
    () async {
      reader.items = [_artist('artist-1', 10)];
      final cancellation = SyncCancellation('user-1');
      reader.onRead = () => cancellation.cancel('account switched');

      await expectLater(
        cancellation.run(
          () => reconciler().reconcilePage(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            limit: 10,
          ),
        ),
        throwsA(isA<SyncCancelled>()),
      );

      final after = await stored();
      expect(after.a1, isFalse);
      expect(after.cursor, isNull);
    },
  );

  test('the next run resumes from the last committed record', () async {
    reader.items = [_artist('artist-1', 10), _artist('artist-2', 11)];
    final cancelled = SyncCancellation('user-1');
    await expectLater(
      cancelled.run(
        () => reconciler(applier: _CancelAfterApplying('artist-2', cancelled))
            .reconcilePage(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              limit: 10,
            ),
      ),
      throwsA(isA<SyncCancelled>()),
    );

    reader.items = [_artist('artist-2', 11)];
    final result = await SyncCancellation('user-1').run(
      () => reconciler().reconcilePage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        limit: 10,
      ),
    );

    expect(result.processedCount, 1);
    final after = await stored();
    expect(after.a1, isTrue);
    expect(after.a2, isTrue);
    expect(after.cursor, 'artist-2');
  });
}

/// Applies the record, then cancels the run when it is [cancelOn], as a
/// sign-out arriving while that record's transaction is open would.
class _CancelAfterApplying extends InboundCloudRecordApplier {
  const _CancelAfterApplying(this.cancelOn, this.cancellation);

  final String cancelOn;
  final SyncCancellation cancellation;

  @override
  Future<InboundApplyResult> apply({
    required CloudOwnedRecord record,
    required SyncMutationContext context,
  }) async {
    final result = await super.apply(record: record, context: context);
    if (record.id == cancelOn) cancellation.cancel('signed out');
    return result;
  }
}

CloudSyncItem _artist(String id, int minute) {
  return CloudSyncItem(
    record: CloudArtistRecord(
      id: id,
      userId: 'user-1',
      name: 'Artist $id',
      canonicalName: 'artist $id',
      createdAt: DateTime.utc(2026, 10, 15),
      updatedAt: DateTime.utc(2026, 10, 16),
    ),
    serverUpdatedAt: DateTime.utc(2026, 10, 16, 10, minute),
    serverRevision: 1,
  );
}

class _Reader implements CloudSyncReader {
  List<CloudSyncItem> items = [];
  void Function()? onRead;

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    for (final item in items) {
      if (item.record.id == entityId) return item;
    }
    return null;
  }

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    onRead?.call();
    return CloudSyncPage(items: items, hasMore: false);
  }
}
