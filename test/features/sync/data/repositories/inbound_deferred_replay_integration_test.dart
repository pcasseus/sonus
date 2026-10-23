import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_processor.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_reconciler.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/inbound_deferred_record.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

// SN-47B2: deferred records passed by the cursor are replayed from the
// durable ledger. Exercised against real SQLite. The controlled cloud
// separates what cursor pages return from current cloud state, so each
// recovery below can only come from replay.
void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner runner;
  late _ControlledCloud cloud;
  late DateTime clock;
  late List<String> replayLog;
  late _FaultInjectingRunner faults;

  Future<InboundSyncProcessor> processorFor(
    AppDatabase database, {
    int replayLimit = 50,
  }) async {
    faults = _FaultInjectingRunner(
      SyncMutationTransactionRunner(
        appDatabase: database,
        generateId: () => 'outbox-1',
        now: () => clock,
      ),
    );

    return InboundSyncProcessor(
      reconciler: InboundSyncReconciler(
        reader: cloud,
        localSyncRepository: SqliteLocalSyncRepository(
          dao: LocalSyncDao(await database.database),
          generateId: () => 'outbox-1',
          now: () => clock,
        ),
        mutationRunner: faults,
        now: () => clock,
        replayLogger: replayLog.add,
      ),
      replayWindow: Duration.zero,
      deferredReplayFetchLimit: replayLimit,
    );
  }

  setUp(() async {
    clock = _at(12);
    replayLog = [];
    cloud = _ControlledCloud();
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await appDatabase.database;
    runner = SyncMutationTransactionRunner(
      appDatabase: appDatabase,
      generateId: () => 'outbox-1',
      now: () => clock,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<Map<CloudDataEntity, (int, InboundDeferralReason)>> ledger([
    SyncMutationTransactionRunner? using,
  ]) async {
    final records = await (using ?? runner).run(
      (context) => context.inboundDeferredRecordRepository!.getDeferred('u1'),
    );

    return {
      for (final record in records)
        record.entityType: (record.serverRevision, record.reason),
    };
  }

  Future<List<Object?>> localChain([SyncMutationTransactionRunner? using]) {
    return (using ?? runner).run(
      (context) async => [
        await context.artistRepository.getById('artist-1'),
        await context.albumRepository.getById('album-1'),
        await context.albumEditionRepository.getById('edition-1'),
        await context.songRepository.getById('song-1'),
      ],
    );
  }

  Future<int?> baseline(CloudDataEntity type, String id) {
    return runner.run(
      (context) => context.cloudRevisionBaselineRepository!.getRevision(
        userId: 'u1',
        entityType: type,
        entityId: id,
      ),
    );
  }

  Future<SyncCursor?> cursor(CloudDataEntity type) {
    return runner.run(
      (context) => context.localSyncRepository.getCursor('u1', type),
    );
  }

  Future<void> createLocalArtist() {
    return runner.run<void>((context) async {
      await context.artistRepository.create(
        Artist(
          id: 'artist-1',
          name: 'Local Artist',
          canonicalName: 'local artist',
          createdAt: _at(1),
          updatedAt: _at(1),
        ),
      );
    });
  }

  /// Children arrive before their artist: all three are deferred and the
  /// cursor passes them.
  Future<void> deferOrphanedChain(InboundSyncProcessor processor) async {
    cloud
      ..publish(_album(), hour: 4, revision: 1)
      ..publish(_edition(), hour: 5, revision: 1)
      ..publish(_song(), hour: 6, revision: 1);

    await processor.pullAll(userId: 'u1');
    cloud.passCursor();
  }

  group('dependency recovery', () {
    test(
      'a later parent unblocks the whole passed chain in one pass',
      () async {
        final processor = await processorFor(appDatabase);
        await deferOrphanedChain(processor);

        expect(await ledger(), {
          CloudDataEntity.album: (1, InboundDeferralReason.missingLocalParent),
          CloudDataEntity.albumEdition: (
            1,
            InboundDeferralReason.missingLocalParent,
          ),
          CloudDataEntity.song: (1, InboundDeferralReason.missingLocalParent),
        });

        final albumCursor = await cursor(CloudDataEntity.album);
        final songCursor = await cursor(CloudDataEntity.song);

        // Only the parent reaches the cursor; the children come from replay.
        cloud.publish(_artist(), hour: 8, revision: 1);
        clock = _at(13);

        final processed = await processor.pullAll(userId: 'u1');

        expect(processed, 4);
        expect((await localChain()).every((e) => e != null), isTrue);
        expect(await ledger(), isEmpty);
        expect(await baseline(CloudDataEntity.album, 'album-1'), 1);
        expect(await baseline(CloudDataEntity.albumEdition, 'edition-1'), 1);
        expect(await baseline(CloudDataEntity.song, 'song-1'), 1);

        // Replay never moves a cursor.
        expect(
          (await cursor(CloudDataEntity.album))?.lastServerUpdatedAt,
          albumCursor?.lastServerUpdatedAt,
        );
        expect(
          (await cursor(CloudDataEntity.song))?.lastServerUpdatedAt,
          songCursor?.lastServerUpdatedAt,
        );
      },
    );

    test('replays the current revision when the cloud moved on', () async {
      final processor = await processorFor(appDatabase);
      await deferOrphanedChain(processor);

      cloud
        ..publish(_artist(), hour: 8, revision: 1)
        ..publish(
          _album(title: 'Renamed Album'),
          hour: 9,
          revision: 3,
          onPage: false,
        );

      await processor.pullAll(userId: 'u1');

      final album = (await localChain())[1] as Album?;
      expect(album?.title, 'Renamed Album');
      expect(await baseline(CloudDataEntity.album, 'album-1'), 3);
      expect(await ledger(), isEmpty);
    });

    test(
      'a newly blocked revision is re-deferred with its new reason',
      () async {
        final processor = await processorFor(appDatabase);
        await deferOrphanedChain(processor);

        cloud
          ..publish(_artist(), hour: 8, revision: 1)
          ..publish(
            _song(artworkId: 'missing-artwork'),
            hour: 9,
            revision: 2,
            onPage: false,
          );

        await processor.pullAll(userId: 'u1');

        expect(await ledger(), {
          CloudDataEntity.song: (2, InboundDeferralReason.missingLocalArtwork),
        });
        expect((await localChain())[3], isNull);
        expect(await baseline(CloudDataEntity.song, 'song-1'), isNull);
      },
    );
  });

  group('repeated replay', () {
    test('a satisfied ledger causes no further fetches or writes', () async {
      final processor = await processorFor(appDatabase);
      await deferOrphanedChain(processor);
      cloud.publish(_artist(), hour: 8, revision: 1);
      await processor.pullAll(userId: 'u1');
      cloud.passCursor();
      cloud.fetches.clear();

      await processor.pullAll(userId: 'u1');
      await processor.pullAll(userId: 'u1');

      expect(cloud.fetches, isEmpty);
      expect(await ledger(), isEmpty);
      expect(await baseline(CloudDataEntity.song, 'song-1'), 1);
    });

    test(
      'an already reconciled obligation is cleared, not reapplied',
      () async {
        final processor = await processorFor(appDatabase);
        await deferOrphanedChain(processor);
        await createLocalArtist();

        // Another path already reconciled revision 4 of the song.
        await runner.run<void>((context) async {
          await context.cloudRevisionBaselineRepository!.saveObservedRevision(
            userId: 'u1',
            entityType: CloudDataEntity.song,
            entityId: 'song-1',
            serverRevision: 4,
          );
        });
        cloud.publish(_song(), hour: 9, revision: 4, onPage: false);

        await processor.pullAll(userId: 'u1');

        expect((await ledger()).containsKey(CloudDataEntity.song), isFalse);
        expect((await localChain())[3], isNull);
      },
    );
  });

  test('restart: the ledger survives and replays after reopening', () async {
    final directory = await Directory.systemTemp.createTemp('sn47b2_');
    final path = p.join(directory.path, 'sonus.db');

    try {
      var database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      await deferOrphanedChain(await processorFor(database));
      await database.close();

      cloud.publish(_artist(), hour: 8, revision: 1);

      database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );

      try {
        final reopened = SyncMutationTransactionRunner(
          appDatabase: database,
          generateId: () => 'outbox-1',
          now: () => clock,
        );

        expect(await ledger(reopened), hasLength(3));

        await (await processorFor(database)).pullAll(userId: 'u1');

        expect((await localChain(reopened)).every((e) => e != null), isTrue);
        expect(await ledger(reopened), isEmpty);
      } finally {
        await database.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  group('partial failure', () {
    test('a failed fetch keeps its obligation while others apply', () async {
      final processor = await processorFor(appDatabase);
      await deferOrphanedChain(processor);

      cloud
        ..publish(_artist(), hour: 8, revision: 1)
        ..fetchErrors['albumEdition:edition-1'] = StateError('offline');

      await expectLater(
        processor.pullAll(userId: 'u1'),
        throwsA(isA<StateError>().having((e) => e.message, 'm', 'offline')),
      );

      // The album applied; the edition kept its exact obligation; the song
      // waits on the still-deferred edition.
      expect((await localChain())[1], isNotNull);
      expect(await ledger(), {
        CloudDataEntity.albumEdition: (
          1,
          InboundDeferralReason.missingLocalParent,
        ),
        CloudDataEntity.song: (1, InboundDeferralReason.missingLocalParent),
      });

      cloud
        ..passCursor()
        ..fetchErrors.clear();
      clock = _at(14);

      await processor.pullAll(userId: 'u1');

      expect((await localChain()).every((e) => e != null), isTrue);
      expect(await ledger(), isEmpty);
    });

    test('a fetched record with another identity fails closed', () async {
      final processor = await processorFor(appDatabase);
      await deferOrphanedChain(processor);
      await createLocalArtist();

      cloud.rows['album:album-1'] = CloudSyncItem(
        record: _edition(id: 'album-1'),
        serverUpdatedAt: _at(9),
        serverRevision: 2,
      );

      await expectLater(processor.pullAll(userId: 'u1'), throwsStateError);

      expect((await ledger())[CloudDataEntity.album], (
        1,
        InboundDeferralReason.missingLocalParent,
      ));
      expect((await localChain())[1], isNull);
    });
  });

  group('bounded replay', () {
    test('fetches at most the limit and rotates through the ledger', () async {
      final processor = await processorFor(appDatabase, replayLimit: 1);
      await deferOrphanedChain(processor);
      cloud.fetches.clear();

      clock = _at(13);
      await processor.pullAll(userId: 'u1');
      clock = _at(14);
      await processor.pullAll(userId: 'u1');
      clock = _at(15);
      await processor.pullAll(userId: 'u1');

      // One fetch per run, each a different, still-blocked obligation.
      expect(cloud.fetches, hasLength(3));
      expect(cloud.fetches.toSet(), hasLength(3));
      expect(await ledger(), hasLength(3));
    });
  });

  group('replay failures', () {
    Future<InboundDeferredRecord?> deferral(CloudDataEntity type, String id) {
      return runner.run(
        (context) => context.inboundDeferredRecordRepository!.getDeferral(
          userId: 'u1',
          entityType: type,
          entityId: id,
        ),
      );
    }

    Future<void> pullIgnoringReplayFailure(InboundSyncProcessor processor) {
      return processor
          .pullAll(userId: 'u1')
          .then<void>((_) {}, onError: (Object _) {});
    }

    test('a persistently failing record cannot starve later ones', () async {
      final processor = await processorFor(appDatabase, replayLimit: 1);
      await deferOrphanedChain(processor);
      cloud
        ..fetches.clear()
        ..fetchErrors['album:album-1'] = const _IncompatibleRowError();

      for (var hour = 13; hour <= 16; hour++) {
        clock = _at(hour);
        await pullIgnoringReplayFailure(processor);
      }

      // The failing album goes to the back after each attempt.
      expect(cloud.fetches, [
        'album:album-1',
        'albumEdition:edition-1',
        'song:song-1',
        'album:album-1',
      ]);
      expect(await ledger(), hasLength(3));
    });

    test(
      'a requeued failure keeps its revision, reason and identity',
      () async {
        final processor = await processorFor(appDatabase);
        await deferOrphanedChain(processor);
        cloud.fetchErrors['album:album-1'] = const _IncompatibleRowError();

        clock = _at(13);
        await expectLater(
          processor.pullAll(userId: 'u1'),
          throwsA(isA<_IncompatibleRowError>()),
        );

        final album = await deferral(CloudDataEntity.album, 'album-1');
        expect(album?.serverRevision, 1);
        expect(album?.reason, InboundDeferralReason.missingLocalParent);
        expect(album?.serverUpdatedAt, _at(4));
        expect(album?.deferredAt, _at(13));
      },
    );

    test('requeue never downgrades a concurrent newer deferral', () async {
      final processor = await processorFor(appDatabase);
      await deferOrphanedChain(processor);
      cloud
        ..fetchErrors['album:album-1'] = const _IncompatibleRowError()
        ..onFetch = (key) async {
          if (key != 'album:album-1') {
            return;
          }

          // The ledger advances to revision 5 while the replay is in flight.
          await runner.run<void>((context) async {
            await context.inboundDeferredRecordRepository!.saveDeferred(
              InboundDeferredRecord(
                userId: 'u1',
                entityType: CloudDataEntity.album,
                entityId: 'album-1',
                serverRevision: 5,
                serverUpdatedAt: _at(9),
                reason: InboundDeferralReason.parentDeferred,
                deferredAt: _at(9),
              ),
            );
          });
        };

      clock = _at(13);
      await pullIgnoringReplayFailure(processor);

      final album = await deferral(CloudDataEntity.album, 'album-1');
      expect(album?.serverRevision, 5);
      expect(album?.reason, InboundDeferralReason.parentDeferred);
      expect(album?.deferredAt, _at(9));
      expect(
        replayLog.single,
        contains('queue=unchanged(obligation changed concurrently)'),
      );
    });

    test('an unresolved requeue never revives or downgrades', () async {
      final processor = await processorFor(appDatabase);
      await deferOrphanedChain(processor);
      cloud
        ..rows.remove('album:album-1')
        ..rows.remove('albumEdition:edition-1')
        ..onFetch = (key) async {
          await runner.run<void>((context) async {
            final ledger = context.inboundDeferredRecordRepository!;

            if (key == 'album:album-1') {
              // Advanced concurrently.
              await ledger.saveDeferred(
                InboundDeferredRecord(
                  userId: 'u1',
                  entityType: CloudDataEntity.album,
                  entityId: 'album-1',
                  serverRevision: 5,
                  serverUpdatedAt: _at(9),
                  reason: InboundDeferralReason.parentDeferred,
                  deferredAt: _at(9),
                ),
              );
            } else if (key == 'albumEdition:edition-1') {
              // Satisfied concurrently.
              await ledger.clearThroughRevision(
                userId: 'u1',
                entityType: CloudDataEntity.albumEdition,
                entityId: 'edition-1',
                serverRevision: 1,
              );
            }
          });
        };

      clock = _at(13);
      await processor.pullAll(userId: 'u1');

      expect(
        (await deferral(CloudDataEntity.album, 'album-1'))?.serverRevision,
        5,
      );
      expect(await deferral(CloudDataEntity.albumEdition, 'edition-1'), isNull);
    });

    test('each failure is logged with identifiers only', () async {
      final processor = await processorFor(appDatabase);
      cloud
        ..publish(_album(), hour: 4, revision: 1)
        ..publish(_album(id: 'album-2'), hour: 5, revision: 3);
      await processor.pullAll(userId: 'u1');
      cloud.passCursor();
      await createLocalArtist();

      const first = _IncompatibleRowError();
      cloud
        ..fetchErrors['album:album-1'] = first
        ..fetchErrors['album:album-2'] = StateError('Secret Album Title');

      clock = _at(13);
      await expectLater(processor.pullAll(userId: 'u1'), throwsA(same(first)));

      expect(replayLog, hasLength(2));
      expect(replayLog[0], contains('entityType=album'));
      expect(replayLog[0], contains('entityId=album-1'));
      expect(replayLog[0], contains('deferredRevision=1'));
      expect(replayLog[0], contains('reason=missingLocalParent'));
      expect(replayLog[0], contains('error=_IncompatibleRowError'));
      expect(replayLog[0], contains('attempt=1/2'));
      expect(replayLog[0], contains('queue=requeued'));
      expect(replayLog[1], contains('entityId=album-2'));
      expect(replayLog[1], contains('deferredRevision=3'));
      expect(replayLog[1], contains('error=StateError'));
      expect(replayLog[1], contains('attempt=2/2'));

      for (final line in replayLog) {
        expect(line, isNot(contains('Secret')));
        expect(line, isNot(contains('u1')));
      }

      // Every failure is also returned, not only the first.
      final result = await processor.reconciler.replayDeferred(
        userId: 'u1',
        maxFetches: 50,
      );
      expect(result.failures.map((f) => f.record.entityId), [
        'album-1',
        'album-2',
      ]);
      expect(result.failures.every((f) => f.requeued), isTrue);
    });

    test('a failed requeue is reported beside the original error', () async {
      final processor = await processorFor(appDatabase);
      await deferOrphanedChain(processor);

      const original = _IncompatibleRowError();
      cloud
        ..fetchErrors['album:album-1'] = original
        ..onFetch = (key) async {
          if (key == 'album:album-1') {
            faults.failNextRun = true;
          }
        };

      clock = _at(13);
      await expectLater(
        processor.pullAll(userId: 'u1'),
        throwsA(same(original)),
      );

      expect(replayLog.single, contains('error=_IncompatibleRowError'));
      expect(replayLog.single, contains('queue=requeueFailed(StateError)'));

      final album = await deferral(CloudDataEntity.album, 'album-1');
      expect(album?.serverRevision, 1);
      expect(album?.reason, InboundDeferralReason.missingLocalParent);
      expect(album?.deferredAt, _at(12));

      final result = await processor.reconciler.replayDeferred(
        userId: 'u1',
        maxFetches: 50,
      );
      final failure = result.failures.single;
      expect(failure.error, same(original));
      expect(failure.requeued, isFalse);
      expect(failure.requeueError, isA<StateError>());
    });

    test(
      'earlier and later commits survive a failure, cursors stay put',
      () async {
        final processor = await processorFor(appDatabase);
        cloud
          ..publish(_album(), hour: 4, revision: 1)
          ..publish(_album(id: 'album-2'), hour: 5, revision: 1)
          ..publish(_album(id: 'album-3'), hour: 6, revision: 1);
        await processor.pullAll(userId: 'u1');
        cloud.passCursor();
        await createLocalArtist();

        final cursorBefore = await cursor(CloudDataEntity.album);
        cloud.fetchErrors['album:album-2'] = const _IncompatibleRowError();

        clock = _at(13);
        await expectLater(
          processor.pullAll(userId: 'u1'),
          throwsA(isA<_IncompatibleRowError>()),
        );

        expect(await baseline(CloudDataEntity.album, 'album-1'), 1);
        expect(await baseline(CloudDataEntity.album, 'album-3'), 1);
        expect(await baseline(CloudDataEntity.album, 'album-2'), isNull);
        expect(await ledger(), {
          CloudDataEntity.album: (1, InboundDeferralReason.missingLocalParent),
        });

        final cursorAfter = await cursor(CloudDataEntity.album);
        expect(
          cursorAfter?.lastServerUpdatedAt,
          cursorBefore?.lastServerUpdatedAt,
        );
        expect(cursorAfter?.lastServerId, cursorBefore?.lastServerId);

        // The retry fetches only the failed record; commits are not redone.
        cloud
          ..fetchErrors.clear()
          ..fetches.clear();
        await processor.pullAll(userId: 'u1');

        expect(cloud.fetches, ['album:album-2']);
        expect(await ledger(), isEmpty);
      },
    );

    test('a failing tombstone replay stays protected', () async {
      final processor = await processorFor(appDatabase);
      await createLocalArtist();
      cloud.publish(_artist(deletedAt: _at(7)), hour: 7, revision: 2);
      await processor.pullAll(userId: 'u1');
      cloud
        ..passCursor()
        ..fetchErrors['artist:artist-1'] = const _IncompatibleRowError();

      // Still held locally: never fetched, so it cannot fail or apply.
      await processor.pullAll(userId: 'u1');
      expect(cloud.fetches, isEmpty);

      // Deleted locally by the user: fetched, fails, and stays deferred.
      await runner.run<void>(
        (context) => context.artistRepository.delete('artist-1'),
      );
      clock = _at(13);
      await pullIgnoringReplayFailure(processor);

      expect(cloud.fetches, ['artist:artist-1']);
      final artist = await deferral(CloudDataEntity.artist, 'artist-1');
      expect(artist?.serverRevision, 2);
      expect(
        artist?.reason,
        InboundDeferralReason.tombstoneRequiresLocalDeletion,
      );
      expect(artist?.deferredAt, _at(13));
      expect(await baseline(CloudDataEntity.artist, 'artist-1'), isNull);
    });
  });

  group('incompatible and deleted records', () {
    test('a tombstone for a held entity is preserved, never applied', () async {
      final processor = await processorFor(appDatabase);
      await createLocalArtist();
      cloud.publish(_artist(deletedAt: _at(7)), hour: 7, revision: 2);

      await processor.pullAll(userId: 'u1');
      cloud
        ..passCursor()
        ..fetches.clear();

      for (var hour = 13; hour < 16; hour++) {
        clock = _at(hour);
        await processor.pullAll(userId: 'u1');
      }

      expect(cloud.fetches, isEmpty);
      expect((await localChain())[0], isNotNull);
      expect(await ledger(), {
        CloudDataEntity.artist: (
          2,
          InboundDeferralReason.tombstoneRequiresLocalDeletion,
        ),
      });
      expect(await baseline(CloudDataEntity.artist, 'artist-1'), isNull);
    });

    test('a tombstone is reconciled once the entity is gone locally', () async {
      final processor = await processorFor(appDatabase);
      await createLocalArtist();
      cloud.publish(_artist(deletedAt: _at(7)), hour: 7, revision: 2);
      await processor.pullAll(userId: 'u1');
      cloud.passCursor();

      // Removed locally by the user, never by sync.
      await runner.run<void>(
        (context) => context.artistRepository.delete('artist-1'),
      );

      await processor.pullAll(userId: 'u1');

      expect(await ledger(), isEmpty);
      expect(await baseline(CloudDataEntity.artist, 'artist-1'), 2);
    });

    test('a missing cloud row keeps the obligation unchanged', () async {
      final processor = await processorFor(appDatabase);
      await deferOrphanedChain(processor);
      await createLocalArtist();
      cloud.rows.remove('album:album-1');

      clock = _at(13);
      await processor.pullAll(userId: 'u1');

      final album = await runner.run(
        (context) => context.inboundDeferredRecordRepository!.getDeferral(
          userId: 'u1',
          entityType: CloudDataEntity.album,
          entityId: 'album-1',
        ),
      );

      expect(album?.serverRevision, 1);
      expect(album?.reason, InboundDeferralReason.missingLocalParent);
      expect(album?.deferredAt, _at(13));
      expect((await localChain())[1], isNull);
    });

    test('an older cloud revision never satisfies the obligation', () async {
      final processor = await processorFor(appDatabase);
      cloud.publish(_album(), hour: 4, revision: 5);
      await processor.pullAll(userId: 'u1');
      cloud.passCursor();
      await createLocalArtist();

      cloud.publish(_album(), hour: 9, revision: 3, onPage: false);
      await processor.pullAll(userId: 'u1');

      expect((await ledger())[CloudDataEntity.album], (
        5,
        InboundDeferralReason.missingLocalParent,
      ));
      expect((await localChain())[1], isNull);
    });

    test('artwork awaiting download is never fetched', () async {
      final processor = await processorFor(appDatabase);
      cloud.publish(
        CloudArtworkAssetRecord(
          id: 'artwork-1',
          userId: 'u1',
          storageObjectKey: 'u1/artwork-1',
          createdAt: _at(1),
          updatedAt: _at(1),
        ),
        hour: 3,
        revision: 1,
      );

      await processor.pullAll(userId: 'u1');
      cloud
        ..passCursor()
        ..fetches.clear();
      await processor.pullAll(userId: 'u1');

      expect(cloud.fetches, isEmpty);
      expect((await ledger())[CloudDataEntity.artworkAsset], (
        1,
        InboundDeferralReason.artworkDownloadRequired,
      ));
    });

    test('a pending local mutation holds replay until it clears', () async {
      final processor = await processorFor(appDatabase);
      await deferOrphanedChain(processor);
      await createLocalArtist();

      await runner.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'u1',
          entityType: CloudDataEntity.album,
          entityId: 'album-1',
        );
      });
      cloud.fetches.clear();

      await processor.pullAll(userId: 'u1');

      expect(cloud.fetches, isNot(contains('album:album-1')));
      expect((await localChain())[1], isNull);
      expect((await ledger())[CloudDataEntity.album], (
        1,
        InboundDeferralReason.missingLocalParent,
      ));

      final entry = (await LocalSyncDao(
        await appDatabase.database,
      ).findPending('u1')).single;
      await runner.run<void>((context) async {
        await context.localSyncRepository.markProcessed(
          userId: 'u1',
          outboxEntryId: entry.id,
          expectedRevision: entry.mutationRevision,
          expectedOperation: SyncOutboxOperation.upsert,
        );
      });

      await processor.pullAll(userId: 'u1');

      expect((await localChain()).sublist(1).every((e) => e != null), isTrue);
      expect(await ledger(), isEmpty);
    });
  });
}

DateTime _at(int hour) => DateTime.utc(2026, 10, 23, hour);

CloudArtistRecord _artist({DateTime? deletedAt}) {
  return CloudArtistRecord(
    id: 'artist-1',
    userId: 'u1',
    name: 'Cloud Artist',
    canonicalName: 'cloud artist',
    createdAt: _at(1),
    updatedAt: _at(2),
    deletedAt: deletedAt,
  );
}

CloudAlbumRecord _album({String id = 'album-1', String title = 'Album'}) {
  return CloudAlbumRecord(
    id: id,
    userId: 'u1',
    artistId: 'artist-1',
    title: title,
    canonicalTitle: title.toLowerCase(),
    createdAt: _at(1),
    updatedAt: _at(2),
  );
}

CloudAlbumEditionRecord _edition({String id = 'edition-1'}) {
  return CloudAlbumEditionRecord(
    id: id,
    userId: 'u1',
    albumId: 'album-1',
    title: 'Standard',
    type: 'standard',
    isPrimary: true,
    createdAt: _at(1),
    updatedAt: _at(2),
  );
}

CloudSongRecord _song({String? artworkId}) {
  return CloudSongRecord(
    id: 'song-1',
    userId: 'u1',
    artistId: 'artist-1',
    albumId: 'album-1',
    albumEditionId: 'edition-1',
    title: 'Song',
    canonicalTitle: 'song',
    trackNumber: 1,
    durationSeconds: 200,
    isSingle: false,
    featuredArtists: const [],
    artworkId: artworkId,
    createdAt: _at(1),
    updatedAt: _at(2),
  );
}

/// Fails the next transaction on request, otherwise delegates.
class _FaultInjectingRunner implements SyncMutationRunner {
  _FaultInjectingRunner(this._inner);

  final SyncMutationRunner _inner;
  bool failNextRun = false;

  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    if (failNextRun) {
      failNextRun = false;
      return Future.error(StateError('Ledger unavailable.'));
    }

    return _inner.run(action);
  }
}

/// A replay failure whose message carries library content, which must
/// never reach the diagnostic log.
class _IncompatibleRowError implements Exception {
  const _IncompatibleRowError();

  @override
  String toString() => 'Unsupported value in "Secret Album Title"';
}

/// Cloud whose cursor pages and current rows are controlled separately.
class _ControlledCloud implements CloudSyncReader {
  final Map<CloudDataEntity, List<CloudSyncItem>> pages = {};
  final Map<String, CloudSyncItem> rows = {};
  final Map<String, Object> fetchErrors = {};
  final List<String> fetches = [];

  /// Runs during a fetch, before its result or error, to simulate work
  /// that happens concurrently with a replay.
  Future<void> Function(String key)? onFetch;

  void publish(
    CloudOwnedRecord record, {
    required int hour,
    required int revision,
    bool onPage = true,
  }) {
    final item = CloudSyncItem(
      record: record,
      serverUpdatedAt: _at(hour),
      serverRevision: revision,
    );
    final type = _typeOf(record);

    rows['${type.name}:${record.id}'] = item;

    if (onPage) {
      pages.putIfAbsent(type, () => []).add(item);
    }
  }

  /// Cursor pages stop returning anything already read.
  void passCursor() => pages.clear();

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    final items = (pages[entityType] ?? const <CloudSyncItem>[])
        .where((item) => item.record.userId == userId)
        .take(limit)
        .toList();

    return CloudSyncPage(items: items, hasMore: false);
  }

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    final key = '${entityType.name}:$entityId';
    fetches.add(key);

    await onFetch?.call(key);

    final error = fetchErrors[key];

    if (error != null) {
      throw error;
    }

    final item = rows[key];

    return item != null && item.record.userId == userId ? item : null;
  }

  static CloudDataEntity _typeOf(CloudOwnedRecord record) {
    return switch (record) {
      CloudArtworkAssetRecord() => CloudDataEntity.artworkAsset,
      CloudArtistRecord() => CloudDataEntity.artist,
      CloudAlbumRecord() => CloudDataEntity.album,
      CloudAlbumEditionRecord() => CloudDataEntity.albumEdition,
      CloudSongRecord() => CloudDataEntity.song,
      _ => throw ArgumentError.value(record, 'record'),
    };
  }
}
