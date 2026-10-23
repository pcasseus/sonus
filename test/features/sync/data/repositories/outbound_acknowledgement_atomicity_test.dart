import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/sync/application/repositories/local_sync_repository.dart';
import 'package:sonus_next/features/sync/application/repositories/outbound_conflict_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/outbound_acknowledgement.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_write_committer.dart';
import 'package:sonus_next/features/sync/application/services/outbound_sync_processor.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_context.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/daos/outbound_conflict_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_outbound_conflict_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/outbound_sync_conflict.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

import '../../application/services/outbound_sync_processor_test.dart'
    show
        FakeAlbumEditionRepository,
        FakeAlbumRepository,
        FakeArtistRepository,
        FakeArtworkAssetRepository,
        FakeCloudArtworkStorage,
        FakeCloudSyncGateway,
        FakeMetadataFieldStateRepository,
        FakeSongRepository,
        album,
        artist;

// SN-47 integration: a cloud-accepted push acknowledges its outbox entry
// and clears the conflict it resolves in one coordinated SQLite
// transaction, so a conflict can never outlive its acknowledged mutation.
void main() {
  sqfliteFfiInit();

  final now = DateTime.utc(2026, 10, 23, 12);

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner runner;
  late _FaultInjectingRunner faults;
  late FakeCloudSyncGateway gateway;
  late FakeArtistRepository artists;
  late FakeAlbumRepository albums;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await appDatabase.database;

    var nextId = 0;
    runner = SyncMutationTransactionRunner(
      appDatabase: appDatabase,
      generateId: () => 'outbox_${nextId++}',
      now: () => now,
    );
    faults = _FaultInjectingRunner(runner);
    gateway = FakeCloudSyncGateway();
    artists = FakeArtistRepository()..values['artist_1'] = artist(now);
    albums = FakeAlbumRepository()..values['album_1'] = album(now);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<OutboundSyncProcessor> processor() async {
    final db = await appDatabase.database;

    return OutboundSyncProcessor(
      localSyncRepository: SqliteLocalSyncRepository(
        dao: LocalSyncDao(db),
        generateId: () => 'unused',
        now: () => now,
      ),
      artistRepository: artists,
      albumRepository: albums,
      albumEditionRepository: FakeAlbumEditionRepository(),
      songRepository: FakeSongRepository(),
      metadataFieldStateRepository: FakeMetadataFieldStateRepository(),
      artworkAssetRepository: FakeArtworkAssetRepository(),
      cloudArtworkStorage: FakeCloudArtworkStorage(),
      cloudSyncGateway: gateway,
      cloudRevisionBaselineRepository: SqliteCloudRevisionBaselineRepository(
        dao: CloudRevisionBaselineDao(db),
      ),
      pushArtistMutation: ({required userId, required entry, required artist}) {
        throw StateError('Unexpected explicit artist upload.');
      },
      ensureArtistDependency: ({required userId, required artist}) async {},
      outboundConflictRepository: SqliteOutboundConflictRepository(
        dao: OutboundConflictDao(db),
      ),
      acknowledgeEntry: TransactionalOutboundAcknowledgement(
        mutationRunner: faults,
      ).acknowledge,
      now: () => now,
    );
  }

  OutboundSyncConflict conflictFor(
    SyncOutboxEntry entry, {
    int? mutationRevision,
  }) {
    return OutboundSyncConflict(
      userId: 'user_1',
      entityType: entry.entityType,
      entityId: entry.entityId,
      outboxId: entry.id,
      mutationRevision: mutationRevision ?? entry.mutationRevision,
      operation: entry.operation,
      expectedServerRevision: 3,
      observedServerRevision: 4,
      observedState: OutboundConflictCloudState.live,
      detectedAt: now,
    );
  }

  Future<SyncOutboxEntry> recordEdit(
    String entityId, {
    CloudDataEntity type = CloudDataEntity.album,
  }) {
    return runner.run((context) async {
      await context.localSyncRepository.recordUpsert(
        userId: 'user_1',
        entityType: type,
        entityId: entityId,
      );

      return (await context.localSyncRepository.getPending(
        'user_1',
      )).singleWhere((entry) => entry.entityId == entityId);
    });
  }

  /// A pending album edit whose earlier push was rejected, now resolved in
  /// the cloud so the next push from baseline 4 is accepted.
  Future<SyncOutboxEntry> seedResolvableConflict() async {
    final entry = await recordEdit('album_1');

    await runner.run<void>((context) async {
      await context.outboundConflictRepository!.record(conflictFor(entry));
      for (final (type, id, revision) in [
        (CloudDataEntity.artist, 'artist_1', 2),
        (CloudDataEntity.album, 'album_1', 4),
      ]) {
        await context.cloudRevisionBaselineRepository!.saveObservedRevision(
          userId: 'user_1',
          entityType: type,
          entityId: id,
          serverRevision: revision,
        );
      }
    });

    return entry;
  }

  Future<List<SyncOutboxEntry>> pending() =>
      runner.run((context) => context.localSyncRepository.getPending('user_1'));

  Future<List<OutboundSyncConflict>> conflicts() => runner.run(
    (context) => context.outboundConflictRepository!.getAll('user_1'),
  );

  /// Starts a real restore and holds it open; admission closes at once.
  Future<void> Function() beginRestore() {
    final release = Completer<void>();
    final restore = appDatabase.mutationCoordinator.runExclusiveRestore(
      () => release.future,
    );

    return () async {
      release.complete();
      await restore;
    };
  }

  group('processor acknowledgement', () {
    test('a successful push acknowledges its entry and clears the '
        'conflict it resolved', () async {
      await seedResolvableConflict();

      final report = await (await processor()).pushPendingIsolated('user_1');

      expect(report.isComplete, isTrue);
      expect(gateway.calls, ['update:album:album_1@4']);
      expect(await pending(), isEmpty);
      expect(await conflicts(), isEmpty);
    });

    for (final step in _FailingStep.values) {
      test('a failure while ${step.description} rolls back both writes '
          'and the push stays retryable', () async {
        final entry = await seedResolvableConflict();
        faults.failing = step;

        final report = await (await processor()).pushPendingIsolated('user_1');

        // The cloud accepted the write; nothing local was acknowledged.
        expect(gateway.calls, ['update:album:album_1@4']);
        expect(report.failures.single.error, isA<_InjectedFailure>());
        expect(faults.failedAfterWriting, isTrue);
        expect((await pending()).single.id, entry.id);
        expect((await conflicts()).single.outboxId, entry.id);

        faults.failing = null;
        final retry = await (await processor()).pushPendingIsolated('user_1');

        expect(retry.isComplete, isTrue);
        expect(await pending(), isEmpty);
        expect(await conflicts(), isEmpty);
      });
    }

    test('restore admission refuses the combined acknowledgement whole, '
        'and the push recovers afterwards', () async {
      final entry = await seedResolvableConflict();
      Future<void> Function()? endRestore;
      gateway.beforeUpsertCompletes = (_) async =>
          endRestore ??= beginRestore();

      final report = await (await processor()).pushPendingIsolated('user_1');
      await endRestore!();

      expect(report.failures.single.error, isA<LibraryMutationUnavailable>());
      expect((await pending()).single.id, entry.id);
      expect((await conflicts()).single.outboxId, entry.id);

      gateway.beforeUpsertCompletes = null;
      final retry = await (await processor()).pushPendingIsolated('user_1');

      expect(retry.isComplete, isTrue);
      expect(await pending(), isEmpty);
      expect(await conflicts(), isEmpty);
    });

    test('a conflict recorded for a newer local edit during the upload '
        'is kept with that edit', () async {
      final entry = await seedResolvableConflict();

      gateway.beforeUpsertCompletes = (_) async {
        final newer = await recordEdit('album_1');
        await runner.run<void>(
          (context) =>
              context.outboundConflictRepository!.record(conflictFor(newer)),
        );
      };

      final report = await (await processor()).pushPendingIsolated('user_1');

      expect(report.isComplete, isTrue);
      final kept = (await pending()).single;
      expect(kept.id, entry.id);
      expect(kept.mutationRevision, entry.mutationRevision + 1);
      final conflict = (await conflicts()).single;
      expect(conflict.mutationRevision, kept.mutationRevision);
    });

    test('a local edit during the upload keeps its entry while the '
        'accepted revision\'s conflict is cleared', () async {
      final entry = await seedResolvableConflict();
      gateway.beforeUpsertCompletes = (_) => recordEdit('album_1');

      final report = await (await processor()).pushPendingIsolated('user_1');

      expect(report.isComplete, isTrue);
      expect(
        (await pending()).single.mutationRevision,
        entry.mutationRevision + 1,
      );
      expect(await conflicts(), isEmpty);
    });

    test('a conflict resolved concurrently does not disturb the '
        'acknowledgement', () async {
      await seedResolvableConflict();
      gateway.beforeUpsertCompletes = (_) => runner.run<void>(
        (context) => context.outboundConflictRepository!.clear(
          userId: 'user_1',
          entityType: CloudDataEntity.album,
          entityId: 'album_1',
        ),
      );

      final report = await (await processor()).pushPendingIsolated('user_1');

      expect(report.isComplete, isTrue);
      expect(await pending(), isEmpty);
      expect(await conflicts(), isEmpty);
    });
  });

  group('acknowledgement contract', () {
    test('repeating an acknowledgement is a no-op that touches nothing '
        'else', () async {
      final entry = await seedResolvableConflict();
      final other = await recordEdit('artist_1', type: CloudDataEntity.artist);
      await runner.run<void>(
        (context) =>
            context.outboundConflictRepository!.record(conflictFor(other)),
      );
      final acknowledgement = TransactionalOutboundAcknowledgement(
        mutationRunner: runner,
      );

      await acknowledgement.acknowledge(userId: 'user_1', entry: entry);
      await acknowledgement.acknowledge(userId: 'user_1', entry: entry);

      expect((await pending()).single.id, other.id);
      expect((await conflicts()).single.entityId, 'artist_1');
    });

    test('an artist committer clears the conflict in its own '
        'transaction', () async {
      final entry = await recordEdit('artist_1', type: CloudDataEntity.artist);
      await runner.run<void>(
        (context) =>
            context.outboundConflictRepository!.record(conflictFor(entry)),
      );

      faults.failing = _FailingStep.clearingConflict;
      final committer = OutboundArtistWriteCommitter(mutationRunner: faults);
      const applied = CloudConditionalWriteResult(
        outcome: CloudConditionalWriteOutcome.applied,
        serverRevision: 1,
      );

      await expectLater(
        committer.commitApplied(
          userId: 'user_1',
          entry: entry,
          result: applied,
        ),
        throwsA(isA<_InjectedFailure>()),
      );
      expect((await pending()).single.id, entry.id);
      expect(await conflicts(), hasLength(1));

      faults.failing = null;
      await committer.commitApplied(
        userId: 'user_1',
        entry: entry,
        result: applied,
      );

      expect(await pending(), isEmpty);
      expect(await conflicts(), isEmpty);
    });
  });
}

enum _FailingStep {
  acknowledgingEntry('acknowledging the entry'),
  clearingConflict('clearing the conflict');

  const _FailingStep(this.description);

  final String description;
}

class _InjectedFailure implements Exception {
  const _InjectedFailure();
}

/// Runs real transactions, optionally making one acknowledgement step fail
/// after its write has executed, so only a rollback can undo it.
class _FaultInjectingRunner implements SyncMutationRunner {
  _FaultInjectingRunner(this._inner);

  final SyncMutationRunner _inner;
  _FailingStep? failing;
  bool failedAfterWriting = false;

  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    return _inner.run((context) {
      final step = failing;

      if (step == null) {
        return action(context);
      }

      void failed() => failedAfterWriting = true;

      return action(
        SyncMutationContext(
          artistRepository: context.artistRepository,
          artistIdentityRepairRepository:
              context.artistIdentityRepairRepository,
          albumRepository: context.albumRepository,
          albumEditionRepository: context.albumEditionRepository,
          albumEditionTrackRepository: context.albumEditionTrackRepository,
          songRepository: context.songRepository,
          songArtistCreditRepository: context.songArtistCreditRepository,
          metadataFieldStateRepository: context.metadataFieldStateRepository,
          artworkAssetRepository: context.artworkAssetRepository,
          localSyncRepository: step == _FailingStep.acknowledgingEntry
              ? _FailAfterMarkProcessed(context.localSyncRepository, failed)
              : context.localSyncRepository,
          cloudRevisionBaselineRepository:
              context.cloudRevisionBaselineRepository,
          artistWriteJournalRepository: context.artistWriteJournalRepository,
          artistDependencyJournalRepository:
              context.artistDependencyJournalRepository,
          inboundDeferredRecordRepository:
              context.inboundDeferredRecordRepository,
          outboundConflictRepository: step == _FailingStep.clearingConflict
              ? _FailAfterClearResolved(
                  context.outboundConflictRepository!,
                  failed,
                )
              : context.outboundConflictRepository,
          playlistRepository: context.playlistRepository,
        ),
      );
    });
  }
}

class _FailAfterMarkProcessed implements LocalSyncRepository {
  _FailAfterMarkProcessed(this._inner, this._onFailure);

  final LocalSyncRepository _inner;
  final void Function() _onFailure;

  @override
  Future<void> markProcessed({
    required String userId,
    required String outboxEntryId,
    required int expectedRevision,
    required SyncOutboxOperation expectedOperation,
  }) async {
    await _inner.markProcessed(
      userId: userId,
      outboxEntryId: outboxEntryId,
      expectedRevision: expectedRevision,
      expectedOperation: expectedOperation,
    );
    _onFailure();
    throw const _InjectedFailure();
  }

  @override
  Future<SyncCursor?> getCursor(String userId, CloudDataEntity entityType) =>
      _inner.getCursor(userId, entityType);

  @override
  Future<void> saveCursor(SyncCursor cursor) => _inner.saveCursor(cursor);

  @override
  Future<List<SyncOutboxEntry>> getPending(String userId) =>
      _inner.getPending(userId);

  @override
  Future<void> recordUpsert({
    required String? userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) => _inner.recordUpsert(
    userId: userId,
    entityType: entityType,
    entityId: entityId,
  );

  @override
  Future<void> recordDelete({
    required String? userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) => _inner.recordDelete(
    userId: userId,
    entityType: entityType,
    entityId: entityId,
  );
}

class _FailAfterClearResolved implements OutboundConflictRepository {
  _FailAfterClearResolved(this._inner, this._onFailure);

  final OutboundConflictRepository _inner;
  final void Function() _onFailure;

  @override
  Future<void> clearResolved({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required String outboxId,
    required int mutationRevision,
  }) async {
    await _inner.clearResolved(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
      outboxId: outboxId,
      mutationRevision: mutationRevision,
    );
    _onFailure();
    throw const _InjectedFailure();
  }

  @override
  Future<void> record(OutboundSyncConflict conflict) => _inner.record(conflict);

  @override
  Future<OutboundSyncConflict?> get({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) => _inner.get(userId: userId, entityType: entityType, entityId: entityId);

  @override
  Future<List<OutboundSyncConflict>> getAll(String userId) =>
      _inner.getAll(userId);

  @override
  Future<void> clear({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) =>
      _inner.clear(userId: userId, entityType: entityType, entityId: entityId);
}
