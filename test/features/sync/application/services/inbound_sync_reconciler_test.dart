import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/domain/repositories/artwork_asset_repository.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_track_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/repositories/album_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_artist_credit_repository.dart';
import 'package:sonus_next/features/sync/application/repositories/local_sync_repository.dart';
import 'package:sonus_next/features/sync/application/repositories/cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/application/repositories/inbound_deferred_record_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_reconciler.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_context.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/inbound_deferred_record.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  final now = DateTime.utc(2026, 9, 13, 15);

  group('InboundSyncReconciler', () {
    test('new cloud revision is applied and recorded', () async {
      final bundle = _Bundle(now);

      bundle.reader.page = CloudSyncPage(
        items: [
          _artistItem(
            id: 'artist-a',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            serverRevision: 8,
          ),
        ],
        hasMore: false,
      );

      await bundle.reconciler.reconcilePage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        limit: 10,
      );

      expect(bundle.artist.values['artist-a']?.name, 'Artist artist-a');
      expect(bundle.baselines.values['user-1|artist|artist-a'], 8);
      expect(bundle.transactionSync.savedCursors, hasLength(1));
    });

    test('higher cloud revision advances an existing baseline', () async {
      final bundle = _Bundle(now);
      bundle.baselines.values['user-1|artist|artist-a'] = 7;

      bundle.reader.page = CloudSyncPage(
        items: [
          _artistItem(
            id: 'artist-a',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            serverRevision: 8,
          ),
        ],
        hasMore: false,
      );

      await bundle.reconciler.reconcilePage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        limit: 10,
      );

      expect(bundle.baselines.values['user-1|artist|artist-a'], 8);
      expect(bundle.artist.values['artist-a']?.name, 'Artist artist-a');
    });

    for (final revision in [7, 8]) {
      test('revision $revision does not overwrite baseline 8', () async {
        final bundle = _Bundle(now);

        bundle.baselines.values['user-1|artist|artist-a'] = 8;

        bundle.artist.values['artist-a'] = Artist(
          id: 'artist-a',
          name: 'Protected Local Name',
          canonicalName: 'protected local name',
          createdAt: DateTime.utc(2026, 9, 10),
          updatedAt: DateTime.utc(2026, 9, 12),
        );

        bundle.reader.page = CloudSyncPage(
          items: [
            _artistItem(
              id: 'artist-a',
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
              serverRevision: revision,
            ),
          ],
          hasMore: false,
        );

        await bundle.reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        );

        expect(bundle.artist.values['artist-a']?.name, 'Protected Local Name');
        expect(bundle.baselines.values['user-1|artist|artist-a'], 8);
        expect(bundle.transactionSync.savedCursors, hasLength(1));
      });
    }

    test('missing cloud revision cannot advance cursor', () async {
      final bundle = _Bundle(now);

      bundle.reader.page = CloudSyncPage(
        items: [
          _artistItem(
            id: 'artist-a',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            serverRevision: null,
          ),
        ],
        hasMore: false,
      );

      await expectLater(
        bundle.reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        ),
        throwsStateError,
      );

      expect(bundle.artist.values, isEmpty);
      expect(bundle.baselines.values, isEmpty);
      expect(bundle.transactionSync.savedCursors, isEmpty);
    });

    test('failed cursor save does not advance reconciliation', () async {
      final bundle = _Bundle(now);

      bundle.transactionSync.failCursorSave = true;

      bundle.reader.page = CloudSyncPage(
        items: [
          _artistItem(
            id: 'artist-a',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            serverRevision: 8,
          ),
        ],
        hasMore: false,
      );

      await expectLater(
        bundle.reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Simulated cursor persistence failure'),
          ),
        ),
      );

      expect(bundle.transactionSync.savedCursors, isEmpty);
      expect(bundle.transactionSync.cursor, isNull);
    });
    test('missing baseline repository blocks inbound application', () async {
      final bundle = _Bundle(now);

      final contextWithoutBaselines = SyncMutationContext(
        artistRepository: bundle.artist,
        albumRepository: bundle.album,
        albumEditionRepository: bundle.edition,
        albumEditionTrackRepository: bundle.membership,
        songRepository: bundle.song,
        songArtistCreditRepository: bundle.credit,
        artworkAssetRepository: bundle.artwork,
        localSyncRepository: bundle.transactionSync,
      );

      final reconciler = InboundSyncReconciler(
        reader: bundle.reader,
        localSyncRepository: bundle.outerSync,
        mutationRunner: _FakeSyncMutationRunner(contextWithoutBaselines),
        now: () => now,
      );

      bundle.reader.page = CloudSyncPage(
        items: [
          _artistItem(
            id: 'artist-a',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            serverRevision: 8,
          ),
        ],
        hasMore: false,
      );

      await expectLater(
        reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        ),
        throwsStateError,
      );

      expect(bundle.artist.values, isEmpty);
      expect(bundle.transactionSync.savedCursors, isEmpty);
      expect(bundle.baselines.values, isEmpty);
    });
    test('replay start is null when no stored cursor exists', () async {
      final bundle = _Bundle(now);

      final start = await bundle.reconciler.replayStart(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        replayWindow: const Duration(minutes: 2),
      );

      expect(start, isNull);
    });

    test('replay start rewinds stored cursor by replay window', () async {
      final bundle = _Bundle(now);

      bundle.outerSync.cursor = SyncCursor(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 11),
        lastServerId: 'artist-z',
        updatedAt: DateTime.utc(2026, 9, 13, 11, 30),
      );

      final start = await bundle.reconciler.replayStart(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        replayWindow: const Duration(minutes: 2),
      );

      expect(start, DateTime.utc(2026, 9, 13, 10, 58));
    });

    test('zero replay window starts at stored cursor timestamp', () async {
      final bundle = _Bundle(now);

      bundle.outerSync.cursor = SyncCursor(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 11),
        lastServerId: 'artist-z',
        updatedAt: DateTime.utc(2026, 9, 13, 11, 30),
      );

      final start = await bundle.reconciler.replayStart(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        replayWindow: Duration.zero,
      );

      expect(start, DateTime.utc(2026, 9, 13, 11));
    });

    test('replay start rejects negative replay window', () async {
      final bundle = _Bundle(now);

      await expectLater(
        bundle.reconciler.replayStart(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          replayWindow: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('forwards inclusive replay start to cloud reader', () async {
      final bundle = _Bundle(now);

      bundle.outerSync.cursor = SyncCursor(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 11),
        lastServerId: 'artist-z',
        updatedAt: DateTime.utc(2026, 9, 13, 11, 30),
      );

      final replayStart = DateTime.utc(2026, 9, 13, 10, 58);

      bundle.reader.page = const CloudSyncPage(items: [], hasMore: false);

      await bundle.reconciler.reconcilePage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        limit: 10,
        fromServerUpdatedAtInclusive: replayStart,
      );

      expect(bundle.reader.lastAfter, isNull);
      expect(bundle.reader.lastFromServerUpdatedAtInclusive, replayStart);
    });

    test('reads from stored cursor and applies returned record', () async {
      final bundle = _Bundle(now);

      bundle.outerSync.cursor = SyncCursor(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 10),
        lastServerId: 'artist-a',
        updatedAt: DateTime.utc(2026, 9, 13, 10, 30),
      );

      bundle.reader.page = CloudSyncPage(
        items: [
          _artistItem(
            id: 'artist-b',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 11),
          ),
        ],
        hasMore: false,
      );

      final result = await bundle.reconciler.reconcilePage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        limit: 25,
      );

      expect(bundle.reader.lastUserId, 'user-1');
      expect(bundle.reader.lastEntityType, CloudDataEntity.artist);
      expect(bundle.reader.lastLimit, 25);
      expect(
        bundle.reader.lastAfter?.serverUpdatedAt,
        DateTime.utc(2026, 9, 13, 10),
      );
      expect(bundle.reader.lastAfter?.id, 'artist-a');

      expect(bundle.artist.values['artist-b']?.name, 'Artist artist-b');
      expect(bundle.runner.runCount, 1);

      final saved = bundle.transactionSync.savedCursors.single;
      expect(saved.userId, 'user-1');
      expect(saved.entityType, CloudDataEntity.artist);
      expect(saved.lastServerUpdatedAt, DateTime.utc(2026, 9, 13, 11));
      expect(saved.lastServerId, 'artist-b');
      expect(saved.updatedAt, now);

      expect(result.processedCount, 1);
      expect(result.hasMore, isFalse);
    });

    test('reads initial page when no cursor exists', () async {
      final bundle = _Bundle(now);

      bundle.reader.page = const CloudSyncPage(items: [], hasMore: false);

      final result = await bundle.reconciler.reconcilePage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        limit: 10,
      );

      expect(bundle.reader.lastAfter, isNull);
      expect(bundle.runner.runCount, 0);
      expect(bundle.transactionSync.savedCursors, isEmpty);
      expect(result.processedCount, 0);
      expect(result.hasMore, isFalse);
    });

    test(
      'replays older record without moving stored cursor backward',
      () async {
        final bundle = _Bundle(now);

        bundle.outerSync.cursor = SyncCursor(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 11),
          lastServerId: 'artist-z',
          updatedAt: DateTime.utc(2026, 9, 13, 11, 30),
        );

        bundle.artist.values['artist-a'] = Artist(
          id: 'artist-a',
          name: 'Old Local Artist',
          canonicalName: 'old local artist',
          createdAt: DateTime.utc(2026, 9, 10),
          updatedAt: DateTime.utc(2026, 9, 13, 8),
        );

        final replayPosition = CloudSyncPosition(
          serverUpdatedAt: DateTime.utc(2026, 9, 13, 9),
          id: 'artist-0',
        );

        bundle.reader.page = CloudSyncPage(
          items: [
            _artistItem(
              id: 'artist-a',
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            ),
          ],
          hasMore: false,
        );

        final result = await bundle.reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
          after: replayPosition,
        );

        expect(bundle.reader.lastAfter, same(replayPosition));
        expect(bundle.artist.values['artist-a']?.name, 'Artist artist-a');
        expect(bundle.runner.runCount, 1);

        expect(bundle.transactionSync.savedCursors, isEmpty);
        expect(
          bundle.outerSync.cursor?.lastServerUpdatedAt,
          DateTime.utc(2026, 9, 13, 11),
        );
        expect(bundle.outerSync.cursor?.lastServerId, 'artist-z');

        expect(result.processedCount, 1);
        expect(result.hasMore, isFalse);
        expect(
          result.lastReadPosition?.serverUpdatedAt,
          DateTime.utc(2026, 9, 13, 10),
        );
        expect(result.lastReadPosition?.id, 'artist-a');
      },
    );

    test('treats cursor with both position fields null as initial', () async {
      final bundle = _Bundle(now);

      bundle.outerSync.cursor = SyncCursor(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        updatedAt: DateTime.utc(2026, 9, 13, 9),
      );

      bundle.reader.page = const CloudSyncPage(items: [], hasMore: false);

      await bundle.reconciler.reconcilePage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        limit: 10,
      );

      expect(bundle.reader.lastAfter, isNull);
    });

    test('rejects cursor with timestamp but no id', () async {
      final bundle = _Bundle(now);

      bundle.outerSync.cursor = SyncCursor(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 10),
        updatedAt: DateTime.utc(2026, 9, 13, 10),
      );

      await expectLater(
        bundle.reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        ),
        throwsStateError,
      );

      expect(bundle.reader.readCount, 0);
      expect(bundle.runner.runCount, 0);
    });

    test('rejects cursor with id but no timestamp', () async {
      final bundle = _Bundle(now);

      bundle.outerSync.cursor = SyncCursor(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        lastServerId: 'artist-a',
        updatedAt: DateTime.utc(2026, 9, 13, 10),
      );

      await expectLater(
        bundle.reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        ),
        throwsStateError,
      );

      expect(bundle.reader.readCount, 0);
      expect(bundle.runner.runCount, 0);
    });

    test('processes multiple records and advances cursor per record', () async {
      final bundle = _Bundle(now);

      bundle.reader.page = CloudSyncPage(
        items: [
          _artistItem(
            id: 'artist-a',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
          ),
          _artistItem(
            id: 'artist-b',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
          ),
          _artistItem(
            id: 'artist-c',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 11),
          ),
        ],
        hasMore: true,
      );

      final result = await bundle.reconciler.reconcilePage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        limit: 3,
      );

      expect(bundle.runner.runCount, 3);
      expect(bundle.artist.values.keys.toList(), [
        'artist-a',
        'artist-b',
        'artist-c',
      ]);

      expect(
        bundle.transactionSync.savedCursors
            .map((cursor) => cursor.lastServerId)
            .toList(),
        ['artist-a', 'artist-b', 'artist-c'],
      );

      expect(
        bundle.transactionSync.savedCursors.last.lastServerUpdatedAt,
        DateTime.utc(2026, 9, 13, 11),
      );

      expect(result.processedCount, 3);
      expect(result.hasMore, isTrue);
    });

    test(
      'stops on apply failure and does not acknowledge failed record',
      () async {
        final bundle = _Bundle(now);

        bundle.reader.page = CloudSyncPage(
          items: [
            _artistItem(
              id: 'artist-a',
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            ),
            _artistItem(
              id: 'artist-b',
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 11),
            ),
            _artistItem(
              id: 'artist-c',
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 12),
            ),
          ],
          hasMore: false,
        );

        bundle.transactionSync.pending.add(
          SyncOutboxEntry(
            id: 'outbox-artist-b',
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist-b',
            operation: SyncOutboxOperation.upsert,
            createdAt: now,
            updatedAt: now,
          ),
        );

        await expectLater(
          bundle.reconciler.reconcilePage(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            limit: 3,
          ),
          throwsStateError,
        );

        expect(bundle.runner.runCount, 2);
        expect(bundle.artist.values.containsKey('artist-a'), isTrue);
        expect(bundle.artist.values.containsKey('artist-b'), isFalse);
        expect(bundle.artist.values.containsKey('artist-c'), isFalse);

        expect(
          bundle.transactionSync.savedCursors
              .map((cursor) => cursor.lastServerId)
              .toList(),
          ['artist-a'],
        );
      },
    );

    test('does not save cursor when entity application fails', () async {
      final bundle = _Bundle(now);

      bundle.reader.page = CloudSyncPage(
        items: [
          CloudSyncItem(
            record: CloudArtworkAssetRecord(
              id: 'artwork-1',
              userId: 'user-1',
              storageObjectKey: 'user-1/artwork-1.jpg',
              createdAt: DateTime.utc(2026, 9, 10),
              updatedAt: DateTime.utc(2026, 9, 12),
            ),
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
          ),
        ],
        hasMore: false,
      );

      await expectLater(
        bundle.reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artworkAsset,
          limit: 10,
        ),
        throwsStateError,
      );

      expect(bundle.runner.runCount, 1);
      expect(bundle.transactionSync.savedCursors, isEmpty);
    });

    test(
      'rejects record belonging to another user before transaction',
      () async {
        final bundle = _Bundle(now);

        bundle.reader.page = CloudSyncPage(
          items: [
            _artistItem(
              id: 'artist-a',
              userId: 'user-2',
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            ),
          ],
          hasMore: false,
        );

        await expectLater(
          bundle.reconciler.reconcilePage(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            limit: 10,
          ),
          throwsStateError,
        );

        expect(bundle.runner.runCount, 0);
        expect(bundle.artist.values, isEmpty);
        expect(bundle.transactionSync.savedCursors, isEmpty);
      },
    );

    test(
      'rejects cloud record whose type does not match requested entity type',
      () async {
        final bundle = _Bundle(now);

        bundle.reader.page = CloudSyncPage(
          items: [
            CloudSyncItem(
              record: CloudAlbumRecord(
                id: 'album-1',
                userId: 'user-1',
                artistId: 'artist-1',
                title: 'Album 1',
                canonicalTitle: 'album 1',
                createdAt: DateTime.utc(2026, 9, 10),
                updatedAt: DateTime.utc(2026, 9, 12),
              ),
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            ),
          ],
          hasMore: false,
        );

        await expectLater(
          bundle.reconciler.reconcilePage(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            limit: 10,
          ),
          throwsStateError,
        );

        expect(bundle.runner.runCount, 0);
        expect(bundle.artist.values, isEmpty);
        expect(bundle.transactionSync.savedCursors, isEmpty);
      },
    );

    test(
      'pending local mutation blocks inbound overwrite and cursor advance',
      () async {
        final bundle = _Bundle(now);

        bundle.artist.values['artist-a'] = Artist(
          id: 'artist-a',
          name: 'Local Artist',
          canonicalName: 'local artist',
          createdAt: DateTime.utc(2026, 9, 10),
          updatedAt: DateTime.utc(2026, 9, 13, 9),
        );

        bundle.transactionSync.pending.add(
          SyncOutboxEntry(
            id: 'outbox-1',
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist-a',
            operation: SyncOutboxOperation.upsert,
            createdAt: DateTime.utc(2026, 9, 13, 9),
            updatedAt: DateTime.utc(2026, 9, 13, 9),
          ),
        );

        bundle.reader.page = CloudSyncPage(
          items: [
            _artistItem(
              id: 'artist-a',
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            ),
          ],
          hasMore: false,
        );

        await expectLater(
          bundle.reconciler.reconcilePage(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            limit: 10,
          ),
          throwsStateError,
        );

        expect(bundle.artist.values['artist-a']?.name, 'Local Artist');
        expect(bundle.transactionSync.savedCursors, isEmpty);
        expect(bundle.runner.runCount, 1);
      },
    );

    test(
      'unappliable record advances cursor only with durable replay',
      () async {
        final bundle = _Bundle(now);
        bundle.artist.values['artist-a'] = Artist(
          id: 'artist-a',
          name: 'Local Artist',
          canonicalName: 'local artist',
          createdAt: DateTime.utc(2026, 9, 10),
          updatedAt: DateTime.utc(2026, 9, 12),
        );
        bundle.baselines.values['user-1|artist|artist-a'] = 3;

        bundle.reader.page = CloudSyncPage(
          items: [
            _artistItem(
              id: 'artist-a',
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
              serverRevision: 4,
              deletedAt: DateTime.utc(2026, 9, 13, 10),
            ),
            _artistItem(
              id: 'artist-b',
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 11),
              serverRevision: 1,
            ),
          ],
          hasMore: false,
        );

        final result = await bundle.reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        );

        expect(result.processedCount, 2);
        expect(result.deferredCount, 1);
        expect(bundle.artist.values['artist-a']?.name, 'Local Artist');
        expect(bundle.baselines.values['user-1|artist|artist-a'], 3);
        expect(bundle.baselines.values['user-1|artist|artist-b'], 1);
        expect(bundle.transactionSync.savedCursors.map((c) => c.lastServerId), [
          'artist-a',
          'artist-b',
        ]);

        final deferred = bundle.deferred.values.values.single;
        expect(deferred.entityId, 'artist-a');
        expect(deferred.serverRevision, 4);
        expect(
          deferred.reason,
          InboundDeferralReason.tombstoneRequiresLocalDeletion,
        );
        expect(deferred.serverUpdatedAt, DateTime.utc(2026, 9, 13, 10));
      },
    );

    test('unappliable record without a deferral ledger fails closed', () async {
      final bundle = _Bundle(now);
      bundle.artist.values['artist-a'] = Artist(
        id: 'artist-a',
        name: 'Local Artist',
        canonicalName: 'local artist',
        createdAt: DateTime.utc(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 9, 12),
      );

      final reconciler = InboundSyncReconciler(
        reader: bundle.reader,
        localSyncRepository: bundle.outerSync,
        mutationRunner: _FakeSyncMutationRunner(
          SyncMutationContext(
            artistRepository: bundle.artist,
            albumRepository: bundle.album,
            albumEditionRepository: bundle.edition,
            albumEditionTrackRepository: bundle.membership,
            songRepository: bundle.song,
            songArtistCreditRepository: bundle.credit,
            artworkAssetRepository: bundle.artwork,
            localSyncRepository: bundle.transactionSync,
            cloudRevisionBaselineRepository: bundle.baselines,
          ),
        ),
        now: () => now,
      );

      bundle.reader.page = CloudSyncPage(
        items: [
          _artistItem(
            id: 'artist-a',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            serverRevision: 4,
            deletedAt: DateTime.utc(2026, 9, 13, 10),
          ),
        ],
        hasMore: false,
      );

      await expectLater(
        reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        ),
        throwsStateError,
      );

      expect(bundle.transactionSync.savedCursors, isEmpty);
      expect(bundle.baselines.values, isEmpty);
    });

    test('applied revision clears an older deferral', () async {
      final bundle = _Bundle(now);
      bundle.deferred.values['user-1|artist|artist-a'] = InboundDeferredRecord(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-a',
        serverRevision: 2,
        serverUpdatedAt: DateTime.utc(2026, 9, 13, 9),
        reason: InboundDeferralReason.missingLocalArtwork,
        deferredAt: DateTime.utc(2026, 9, 13, 9),
      );

      bundle.reader.page = CloudSyncPage(
        items: [
          _artistItem(
            id: 'artist-a',
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            serverRevision: 3,
          ),
        ],
        hasMore: false,
      );

      final result = await bundle.reconciler.reconcilePage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        limit: 10,
      );

      expect(result.deferredCount, 0);
      expect(bundle.deferred.values, isEmpty);
      expect(bundle.baselines.values['user-1|artist|artist-a'], 3);
    });

    test('trims user id before cursor lookup and cloud read', () async {
      final bundle = _Bundle(now);

      bundle.reader.page = const CloudSyncPage(items: [], hasMore: false);

      await bundle.reconciler.reconcilePage(
        userId: '  user-1  ',
        entityType: CloudDataEntity.artist,
        limit: 10,
      );

      expect(bundle.outerSync.lastCursorUserId, 'user-1');
      expect(bundle.reader.lastUserId, 'user-1');
    });

    test('rejects blank user id before reading cursor', () async {
      final bundle = _Bundle(now);

      await expectLater(
        bundle.reconciler.reconcilePage(
          userId: '   ',
          entityType: CloudDataEntity.artist,
          limit: 10,
        ),
        throwsArgumentError,
      );

      expect(bundle.outerSync.cursorReadCount, 0);
      expect(bundle.reader.readCount, 0);
    });

    test('rejects nonpositive limit before reading cursor', () async {
      final bundle = _Bundle(now);

      await expectLater(
        bundle.reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 0,
        ),
        throwsArgumentError,
      );

      expect(bundle.outerSync.cursorReadCount, 0);
      expect(bundle.reader.readCount, 0);
    });
  });
}

CloudSyncItem _artistItem({
  required String id,
  required DateTime serverUpdatedAt,
  String userId = 'user-1',
  int? serverRevision = 1,
  DateTime? deletedAt,
}) {
  return CloudSyncItem(
    record: CloudArtistRecord(
      id: id,
      userId: userId,
      name: 'Artist $id',
      canonicalName: 'artist $id',
      createdAt: DateTime.utc(2026, 9, 10),
      updatedAt: DateTime.utc(2026, 9, 12),
      deletedAt: deletedAt,
    ),
    serverUpdatedAt: serverUpdatedAt,
    serverRevision: serverRevision,
  );
}

class _Bundle {
  _Bundle(DateTime now)
    : reader = _FakeCloudSyncReader(),
      outerSync = _FakeLocalSyncRepository(),
      transactionSync = _FakeLocalSyncRepository(),
      baselines = _FakeCloudRevisionBaselineRepository(),
      deferred = _FakeInboundDeferredRecordRepository(),
      artist = _FakeArtistRepository(),
      album = _FakeAlbumRepository(),
      edition = _FakeAlbumEditionRepository(),
      membership = _FakeAlbumEditionTrackRepository(),
      song = _FakeSongRepository(),
      credit = _FakeSongArtistCreditRepository(),
      artwork = _FakeArtworkRepository() {
    final context = SyncMutationContext(
      artistRepository: artist,
      albumRepository: album,
      albumEditionRepository: edition,
      albumEditionTrackRepository: membership,
      songRepository: song,
      songArtistCreditRepository: credit,
      artworkAssetRepository: artwork,
      localSyncRepository: transactionSync,
      cloudRevisionBaselineRepository: baselines,
      inboundDeferredRecordRepository: deferred,
    );

    runner = _FakeSyncMutationRunner(context);

    reconciler = InboundSyncReconciler(
      reader: reader,
      localSyncRepository: outerSync,
      mutationRunner: runner,
      now: () => now,
    );
  }

  final _FakeCloudSyncReader reader;
  final _FakeLocalSyncRepository outerSync;
  final _FakeLocalSyncRepository transactionSync;
  final _FakeCloudRevisionBaselineRepository baselines;
  final _FakeInboundDeferredRecordRepository deferred;
  final _FakeArtistRepository artist;
  final _FakeAlbumRepository album;
  final _FakeAlbumEditionRepository edition;
  final _FakeAlbumEditionTrackRepository membership;
  final _FakeSongRepository song;
  final _FakeSongArtistCreditRepository credit;
  final _FakeArtworkRepository artwork;

  late final _FakeSyncMutationRunner runner;
  late final InboundSyncReconciler reconciler;
}

class _FakeCloudRevisionBaselineRepository
    implements CloudRevisionBaselineRepository {
  final Map<String, int> values = {};

  String _key(String userId, CloudDataEntity entityType, String entityId) =>
      '$userId|${entityType.name}|$entityId';

  @override
  Future<int?> getRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    return values[_key(userId, entityType, entityId)];
  }

  @override
  Future<void> saveObservedRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
  }) async {
    final key = _key(userId, entityType, entityId);
    final previous = values[key];

    if (previous == null || serverRevision > previous) {
      values[key] = serverRevision;
    }
  }
}

class _FakeInboundDeferredRecordRepository
    implements InboundDeferredRecordRepository {
  final Map<String, InboundDeferredRecord> values = {};

  String _key(String userId, CloudDataEntity entityType, String entityId) =>
      '$userId|${entityType.name}|$entityId';

  @override
  Future<void> saveDeferred(InboundDeferredRecord record) async {
    final key = _key(record.userId, record.entityType, record.entityId);
    final previous = values[key];

    if (previous == null || record.serverRevision >= previous.serverRevision) {
      values[key] = record;
    }
  }

  @override
  Future<List<InboundDeferredRecord>> getDeferred(String userId) async {
    return values.values.where((record) => record.userId == userId).toList();
  }

  @override
  Future<void> clearThroughRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
  }) async {
    final key = _key(userId, entityType, entityId);
    final previous = values[key];

    if (previous != null && previous.serverRevision <= serverRevision) {
      values.remove(key);
    }
  }
}

class _FakeCloudSyncReader implements CloudSyncReader {
  CloudSyncPage page = const CloudSyncPage(items: [], hasMore: false);

  int readCount = 0;
  String? lastUserId;
  CloudDataEntity? lastEntityType;
  CloudSyncPosition? lastAfter;
  DateTime? lastFromServerUpdatedAtInclusive;
  int? lastLimit;

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    readCount += 1;
    lastUserId = userId;
    lastEntityType = entityType;
    lastAfter = after;
    lastFromServerUpdatedAtInclusive = fromServerUpdatedAtInclusive;
    lastLimit = limit;
    return page;
  }
}

class _FakeSyncMutationRunner implements SyncMutationRunner {
  _FakeSyncMutationRunner(this.context);

  final SyncMutationContext context;
  int runCount = 0;

  @override
  Future<T> run<T>(SyncMutationAction<T> action) async {
    runCount += 1;
    return action(context);
  }
}

class _FakeLocalSyncRepository implements LocalSyncRepository {
  SyncCursor? cursor;
  final List<SyncCursor> savedCursors = [];
  bool failCursorSave = false;
  final List<SyncOutboxEntry> pending = [];

  int cursorReadCount = 0;
  String? lastCursorUserId;
  CloudDataEntity? lastCursorEntityType;

  @override
  Future<List<SyncOutboxEntry>> getPending(String userId) async {
    return List.unmodifiable(pending.where((entry) => entry.userId == userId));
  }

  @override
  Future<SyncCursor?> getCursor(
    String userId,
    CloudDataEntity entityType,
  ) async {
    cursorReadCount += 1;
    lastCursorUserId = userId;
    lastCursorEntityType = entityType;
    return cursor;
  }

  @override
  Future<void> saveCursor(SyncCursor cursor) async {
    if (failCursorSave) {
      throw StateError('Simulated cursor persistence failure.');
    }
    savedCursors.add(cursor);
    this.cursor = cursor;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeArtistRepository implements ArtistRepository {
  final Map<String, Artist> values = {};

  @override
  Future<Artist?> getById(String id) async => values[id];

  @override
  Future<void> create(Artist artist) async {
    values[artist.id] = artist;
  }

  @override
  Future<void> save(Artist artist) async {
    values[artist.id] = artist;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAlbumRepository implements AlbumRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAlbumEditionRepository implements AlbumEditionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAlbumEditionTrackRepository implements AlbumEditionTrackRepository {
  final List<AlbumEditionTrack> memberships = <AlbumEditionTrack>[];

  @override
  Future<void> create(AlbumEditionTrack membership) async {
    memberships.add(membership);
  }

  @override
  Future<void> save(AlbumEditionTrack membership) async {
    final index = memberships.indexWhere((existing) => existing == membership);

    if (index < 0) {
      throw StateError('Membership not found.');
    }

    memberships[index] = membership;
  }

  @override
  Future<List<AlbumEditionTrack>> getByEditionId(String editionId) async {
    return [
      for (final membership in memberships)
        if (membership.albumEditionId == editionId) membership,
    ];
  }

  @override
  Future<List<AlbumEditionTrack>> getBySongId(String songId) async {
    return [
      for (final membership in memberships)
        if (membership.songId == songId) membership,
    ];
  }

  @override
  Future<void> delete({
    required String editionId,
    required String songId,
  }) async {
    memberships.removeWhere(
      (membership) =>
          membership.albumEditionId == editionId && membership.songId == songId,
    );
  }
}

class _FakeSongRepository implements SongRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSongArtistCreditRepository implements SongArtistCreditRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeArtworkRepository implements ArtworkAssetRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
