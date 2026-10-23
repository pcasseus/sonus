import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/artwork/domain/repositories/artwork_asset_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/repositories/metadata_field_state_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/album_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';
import 'package:sonus_next/features/sync/application/repositories/local_sync_repository.dart';
import 'package:sonus_next/features/sync/application/repositories/cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_artwork_storage.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_gateway.dart';
import 'package:sonus_next/features/sync/application/services/outbound_sync_processor.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  group('OutboundSyncProcessor', () {
    late FakeLocalSyncRepository localSyncRepository;
    late FakeArtistRepository artistRepository;
    late FakeAlbumRepository albumRepository;
    late FakeAlbumEditionRepository albumEditionRepository;
    late FakeSongRepository songRepository;
    late FakeMetadataFieldStateRepository metadataFieldStateRepository;
    late FakeArtworkAssetRepository artworkAssetRepository;
    late FakeCloudArtworkStorage cloudArtworkStorage;
    late FakeCloudSyncGateway cloudSyncGateway;
    late OutboundSyncProcessor processor;

    final timestamp = DateTime.utc(2026, 9, 13, 12);

    setUp(() {
      localSyncRepository = FakeLocalSyncRepository();
      artistRepository = FakeArtistRepository();
      albumRepository = FakeAlbumRepository();
      albumEditionRepository = FakeAlbumEditionRepository();
      songRepository = FakeSongRepository();
      metadataFieldStateRepository = FakeMetadataFieldStateRepository();
      artworkAssetRepository = FakeArtworkAssetRepository();
      cloudArtworkStorage = FakeCloudArtworkStorage();
      cloudSyncGateway = FakeCloudSyncGateway();

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
      );
    });

    test('new edit during cloud upload remains pending', () async {
      artistRepository.values['artist_1'] = artist(timestamp);

      final originalEntry = outbox(
        id: 'outbox_in_flight',
        type: CloudDataEntity.artist,
        entityId: 'artist_1',
        timestamp: timestamp,
      );

      localSyncRepository.pending.add(originalEntry);

      final uploadStarted = Completer<void>();
      final releaseUpload = Completer<void>();

      cloudSyncGateway.beforeUpsertCompletes = (record) async {
        if (record is CloudArtistRecord) {
          uploadStarted.complete();
          await releaseUpload.future;
        }
      };

      final push = processor.pushPending('user_1');

      await uploadStarted.future;

      try {
        expect(cloudSyncGateway.calls, ['upsert:artist:artist_1']);
        expect(localSyncRepository.processedIds, isEmpty);

        localSyncRepository.pending[0] = SyncOutboxEntry(
          id: originalEntry.id,
          userId: originalEntry.userId,
          entityType: originalEntry.entityType,
          entityId: originalEntry.entityId,
          operation: SyncOutboxOperation.upsert,
          createdAt: originalEntry.createdAt,
          updatedAt: timestamp.add(const Duration(minutes: 1)),
          mutationRevision: 2,
        );
      } finally {
        releaseUpload.complete();
      }

      await push;

      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending, hasLength(1));
      expect(localSyncRepository.pending.single.id, originalEntry.id);
      expect(localSyncRepository.pending.single.mutationRevision, 2);
      expect(
        localSyncRepository.pending.single.operation,
        SyncOutboxOperation.upsert,
      );

      cloudSyncGateway.beforeUpsertCompletes = null;

      await processor.pushPending('user_1');

      expect(localSyncRepository.pending, isEmpty);
      expect(localSyncRepository.processedIds, [originalEntry.id]);
      expect(cloudSyncGateway.calls, [
        'upsert:artist:artist_1',
        'upsert:artist:artist_1',
      ]);
    });

    test('safe dependency callback runs before album upload', () async {
      artistRepository.values['artist_1'] = artist(timestamp);
      albumRepository.values['album_1'] = album(timestamp);

      localSyncRepository.pending.add(
        outbox(
          id: 'dependent_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
      );

      final ensured = <String>[];

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: FakeCloudRevisionBaselineRepository(),
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('No explicit artist mutation expected.');
            },
        ensureArtistDependency: ({required userId, required artist}) async {
          expect(userId, 'user_1');
          expect(artist.id, 'artist_1');
          expect(cloudSyncGateway.calls, isEmpty);
          ensured.add(artist.id);
        },
      );

      await processor.pushPending('user_1');

      expect(ensured, ['artist_1']);
      expect(cloudSyncGateway.calls, ['insert:album:album_1']);
      expect(localSyncRepository.processedIds, ['dependent_album']);
      expect(localSyncRepository.pending, isEmpty);
    });

    test(
      'dependency conflict stops album and preserves its outbox entry',
      () async {
        artistRepository.values['artist_1'] = artist(timestamp);
        albumRepository.values['album_1'] = album(timestamp);

        localSyncRepository.pending.add(
          outbox(
            id: 'conflicting_album',
            type: CloudDataEntity.album,
            entityId: 'album_1',
            timestamp: timestamp,
          ),
        );

        var attempts = 0;

        processor = OutboundSyncProcessor(
          localSyncRepository: localSyncRepository,
          artistRepository: artistRepository,
          albumRepository: albumRepository,
          albumEditionRepository: albumEditionRepository,
          songRepository: songRepository,
          metadataFieldStateRepository: metadataFieldStateRepository,
          artworkAssetRepository: artworkAssetRepository,
          cloudArtworkStorage: cloudArtworkStorage,
          cloudSyncGateway: cloudSyncGateway,
          cloudRevisionBaselineRepository:
              FakeCloudRevisionBaselineRepository(),
          pushArtistMutation:
              ({required userId, required entry, required artist}) async {
                throw StateError('No explicit artist mutation expected.');
              },
          ensureArtistDependency: ({required userId, required artist}) async {
            attempts++;
            throw StateError('Cloud artist already exists; reconcile first.');
          },
        );

        await expectLater(processor.pushPending('user_1'), throwsStateError);

        expect(attempts, 1);
        expect(cloudSyncGateway.calls, isEmpty);
        expect(localSyncRepository.processedIds, isEmpty);
        expect(localSyncRepository.pending, hasLength(1));
        expect(localSyncRepository.pending.single.id, 'conflicting_album');
      },
    );

    test(
      'explicit artist mutation and dependent album remain separate',
      () async {
        artistRepository.values['artist_1'] = artist(timestamp);
        albumRepository.values['album_1'] = album(timestamp);

        localSyncRepository.pending.addAll([
          outbox(
            id: 'explicit_artist',
            type: CloudDataEntity.artist,
            entityId: 'artist_1',
            timestamp: timestamp,
          ),
          outbox(
            id: 'dependent_album_after_artist',
            type: CloudDataEntity.album,
            entityId: 'album_1',
            timestamp: timestamp,
          ),
        ]);

        var artistWrites = 0;
        var dependencyChecks = 0;

        processor = OutboundSyncProcessor(
          localSyncRepository: localSyncRepository,
          artistRepository: artistRepository,
          albumRepository: albumRepository,
          albumEditionRepository: albumEditionRepository,
          songRepository: songRepository,
          metadataFieldStateRepository: metadataFieldStateRepository,
          artworkAssetRepository: artworkAssetRepository,
          cloudArtworkStorage: cloudArtworkStorage,
          cloudSyncGateway: cloudSyncGateway,
          cloudRevisionBaselineRepository:
              FakeCloudRevisionBaselineRepository(),
          pushArtistMutation:
              ({required userId, required entry, required artist}) async {
                artistWrites++;

                expect(entry.id, 'explicit_artist');
                expect(cloudSyncGateway.calls, isEmpty);

                await localSyncRepository.markProcessed(
                  userId: userId,
                  outboxEntryId: entry.id,
                  expectedRevision: entry.mutationRevision,
                  expectedOperation: entry.operation,
                );
              },
          ensureArtistDependency: ({required userId, required artist}) async {
            dependencyChecks++;
          },
        );

        await processor.pushPending('user_1');

        expect(artistWrites, 1);
        expect(dependencyChecks, 0);
        expect(cloudSyncGateway.calls, ['insert:album:album_1']);
        expect(localSyncRepository.processedIds, [
          'explicit_artist',
          'dependent_album_after_artist',
        ]);
        expect(localSyncRepository.pending, isEmpty);
      },
    );
    test('guarded artist delegates and acknowledges exactly once', () async {
      artistRepository.values['artist_1'] = artist(timestamp);

      localSyncRepository.pending.add(
        outbox(
          id: 'guarded_artist',
          type: CloudDataEntity.artist,
          entityId: 'artist_1',
          timestamp: timestamp,
        ),
      );

      final baselines = FakeCloudRevisionBaselineRepository();
      var coordinatorCalls = 0;

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: baselines,
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              coordinatorCalls++;

              expect(userId, 'user_1');
              expect(entry.id, 'guarded_artist');
              expect(artist.id, 'artist_1');

              await localSyncRepository.markProcessed(
                userId: userId,
                outboxEntryId: entry.id,
                expectedRevision: entry.mutationRevision,
                expectedOperation: entry.operation,
              );
            },
      );

      await processor.pushPending('user_1');

      expect(coordinatorCalls, 1);
      expect(localSyncRepository.processedIds, ['guarded_artist']);
      expect(localSyncRepository.pending, isEmpty);
      expect(cloudSyncGateway.calls, isEmpty);
    });

    test('guarded artist failure preserves its pending mutation', () async {
      artistRepository.values['artist_1'] = artist(timestamp);

      localSyncRepository.pending.add(
        outbox(
          id: 'guarded_conflict',
          type: CloudDataEntity.artist,
          entityId: 'artist_1',
          timestamp: timestamp,
        ),
      );

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: FakeCloudRevisionBaselineRepository(),
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('Simulated conditional write conflict.');
            },
      );

      await expectLater(processor.pushPending('user_1'), throwsStateError);

      expect(localSyncRepository.pending, hasLength(1));
      expect(localSyncRepository.processedIds, isEmpty);
      expect(cloudSyncGateway.calls, isEmpty);
    });

    test('guarded album dependency does not overwrite artist', () async {
      artistRepository.values['artist_1'] = artist(timestamp);
      albumRepository.values['album_1'] = album(timestamp);

      localSyncRepository.pending.add(
        outbox(
          id: 'guarded_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
      );

      final baselines = FakeCloudRevisionBaselineRepository();
      baselines.revisions['user_1:artist:artist_1'] = 4;

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: baselines,
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('Unexpected explicit artist upload.');
            },
      );

      await processor.pushPending('user_1');

      expect(cloudSyncGateway.calls, ['insert:album:album_1']);
      expect(localSyncRepository.processedIds, ['guarded_album']);
    });

    test('missing artist baseline defers dependent album', () async {
      artistRepository.values['artist_1'] = artist(timestamp);
      albumRepository.values['album_1'] = album(timestamp);

      localSyncRepository.pending.add(
        outbox(
          id: 'unknown_dependency',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
      );

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: FakeCloudRevisionBaselineRepository(),
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('Unexpected explicit artist upload.');
            },
      );

      await expectLater(processor.pushPending('user_1'), throwsStateError);

      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending, hasLength(1));
    });
    OutboundSyncProcessor deletionProcessor({
      PushArtistDeletion? deletion,
      bool guardedUpsert = true,
    }) {
      return OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: guardedUpsert
            ? FakeCloudRevisionBaselineRepository()
            : null,
        pushArtistMutation: guardedUpsert
            ? ({required userId, required entry, required artist}) async {
                throw StateError('Unexpected artist upsert.');
              }
            : null,
        pushArtistDeletion: deletion,
      );
    }

    test('guarded artist deletion owns acknowledgement', () async {
      final entry = outbox(
        id: 'guarded_delete',
        type: CloudDataEntity.artist,
        entityId: 'artist_1',
        timestamp: timestamp,
        operation: SyncOutboxOperation.delete,
      );

      localSyncRepository.pending.add(entry);
      var calls = 0;

      processor = deletionProcessor(
        deletion: ({required userId, required entry}) async {
          calls++;
          expect(userId, 'user_1');
          expect(entry.id, 'guarded_delete');
          expect(entry.operation, SyncOutboxOperation.delete);

          await localSyncRepository.markProcessed(
            userId: userId,
            outboxEntryId: entry.id,
            expectedRevision: entry.mutationRevision,
            expectedOperation: entry.operation,
          );
        },
      );

      await processor.pushPending('user_1');

      expect(calls, 1);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, ['guarded_delete']);
      expect(localSyncRepository.pending, isEmpty);
    });

    test('guarded artist deletion failure leaves work pending', () async {
      final entry = outbox(
        id: 'failed_delete',
        type: CloudDataEntity.artist,
        entityId: 'artist_1',
        timestamp: timestamp,
        operation: SyncOutboxOperation.delete,
      );

      localSyncRepository.pending.add(entry);
      var calls = 0;

      processor = deletionProcessor(
        deletion: ({required userId, required entry}) async {
          calls++;
          throw StateError('Simulated guarded deletion conflict.');
        },
      );

      await expectLater(processor.pushPending('user_1'), throwsStateError);

      expect(calls, 1);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending.single.id, entry.id);
    });

    test('newer upsert survives guarded deletion acknowledgement', () async {
      final entry = outbox(
        id: 'delete_then_upsert',
        type: CloudDataEntity.artist,
        entityId: 'artist_1',
        timestamp: timestamp,
        operation: SyncOutboxOperation.delete,
      );

      localSyncRepository.pending.add(entry);

      processor = deletionProcessor(
        deletion: ({required userId, required entry}) async {
          localSyncRepository.pending[0] = SyncOutboxEntry(
            id: entry.id,
            userId: entry.userId,
            entityType: entry.entityType,
            entityId: entry.entityId,
            operation: SyncOutboxOperation.upsert,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt.add(const Duration(minutes: 1)),
            mutationRevision: entry.mutationRevision + 1,
          );

          await localSyncRepository.markProcessed(
            userId: userId,
            outboxEntryId: entry.id,
            expectedRevision: entry.mutationRevision,
            expectedOperation: entry.operation,
          );
        },
      );

      await processor.pushPending('user_1');

      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending, hasLength(1));
      expect(localSyncRepository.pending.single.id, entry.id);
      expect(localSyncRepository.pending.single.mutationRevision, 2);
      expect(
        localSyncRepository.pending.single.operation,
        SyncOutboxOperation.upsert,
      );
    });

    test('song deletion stays on generic route', () async {
      final entry = outbox(
        id: 'ordinary_song_delete',
        type: CloudDataEntity.song,
        entityId: 'song_1',
        timestamp: timestamp,
        operation: SyncOutboxOperation.delete,
      );

      localSyncRepository.pending.add(entry);
      var guardedCalls = 0;

      processor = deletionProcessor(
        deletion: ({required userId, required entry}) async {
          guardedCalls++;
          throw StateError('Song must not use artist deletion.');
        },
      );

      await processor.pushPending('user_1');

      expect(guardedCalls, 0);
      expect(cloudSyncGateway.calls, [
        'delete:song:song_1:${timestamp.toIso8601String()}',
      ]);
      expect(localSyncRepository.processedIds, ['ordinary_song_delete']);
      expect(localSyncRepository.pending, isEmpty);
    });

    test('guarded deletion rejects missing upsert configuration', () async {
      processor = deletionProcessor(
        guardedUpsert: false,
        deletion: ({required userId, required entry}) async {
          throw StateError('Deletion callback must not run.');
        },
      );

      await expectLater(processor.pushPending('user_1'), throwsStateError);

      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
    });
    test('recovery runs even when ordinary outbox is empty', () async {
      final events = <String>[];

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: FakeCloudRevisionBaselineRepository(),
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('Unexpected artist mutation.');
            },
        pushArtistDeletion: ({required userId, required entry}) async {
          throw StateError('Unexpected artist deletion.');
        },
        recoverArtistWrites: (userId) async {
          events.add('recover:$userId');
        },
      );

      await processor.pushPending('user_1');

      expect(events, ['recover:user_1']);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
    });

    test('failed recovery blocks later ordinary outbound writes', () async {
      localSyncRepository.pending.add(
        outbox(
          id: 'pending_song_delete',
          type: CloudDataEntity.song,
          entityId: 'song_1',
          timestamp: timestamp,
          operation: SyncOutboxOperation.delete,
        ),
      );

      var recoveryCalls = 0;

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: FakeCloudRevisionBaselineRepository(),
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('Unexpected artist mutation.');
            },
        pushArtistDeletion: ({required userId, required entry}) async {
          throw StateError('Unexpected artist deletion.');
        },
        recoverArtistWrites: (userId) async {
          recoveryCalls++;
          throw StateError('Unresolved cloud receipt.');
        },
      );

      await expectLater(processor.pushPending('user_1'), throwsStateError);

      expect(recoveryCalls, 1);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending, hasLength(1));
    });

    test('recovery completes before fetching refreshed outbox', () async {
      final events = <String>[];

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: FakeCloudRevisionBaselineRepository(),
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('Unexpected artist mutation.');
            },
        pushArtistDeletion: ({required userId, required entry}) async {
          throw StateError('Unexpected artist deletion.');
        },
        recoverArtistWrites: (userId) async {
          events.add('recovered');

          localSyncRepository.pending.add(
            outbox(
              id: 'new_song_delete',
              type: CloudDataEntity.song,
              entityId: 'song_1',
              timestamp: timestamp,
              operation: SyncOutboxOperation.delete,
            ),
          );
        },
      );

      await processor.pushPending('user_1');

      expect(events, ['recovered']);
      expect(cloudSyncGateway.calls, [
        'delete:song:song_1:${timestamp.toIso8601String()}',
      ]);
      expect(localSyncRepository.processedIds, ['new_song_delete']);
      expect(localSyncRepository.pending, isEmpty);
    });

    test('recovery configuration requires guarded deletion', () async {
      var calls = 0;

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: FakeCloudRevisionBaselineRepository(),
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('Unexpected artist mutation.');
            },
        recoverArtistWrites: (userId) async {
          calls++;
        },
      );

      await expectLater(processor.pushPending('user_1'), throwsStateError);

      expect(calls, 0);
      expect(cloudSyncGateway.calls, isEmpty);
    });

    test('recovery must finish before ordinary deletion begins', () async {
      final recoveryStarted = Completer<void>();
      final releaseRecovery = Completer<void>();
      final events = <String>[];

      localSyncRepository.pending.add(
        outbox(
          id: 'ordinary_after_recovery',
          type: CloudDataEntity.song,
          entityId: 'song_1',
          timestamp: timestamp,
          operation: SyncOutboxOperation.delete,
        ),
      );

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: FakeCloudRevisionBaselineRepository(),
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('Unexpected artist mutation.');
            },
        pushArtistDeletion: ({required userId, required entry}) async {
          throw StateError('Unexpected artist deletion.');
        },
        recoverArtistWrites: (userId) async {
          events.add('recovery-start');
          recoveryStarted.complete();
          await releaseRecovery.future;
          events.add('recovery-end');
        },
      );

      final push = processor.pushPending('user_1');

      await recoveryStarted.future;

      try {
        expect(events, ['recovery-start']);
        expect(cloudSyncGateway.calls, isEmpty);
        expect(localSyncRepository.processedIds, isEmpty);
        expect(localSyncRepository.pending, hasLength(1));
      } finally {
        releaseRecovery.complete();
      }

      await push;

      expect(events, ['recovery-start', 'recovery-end']);
      expect(cloudSyncGateway.calls, [
        'delete:song:song_1:${timestamp.toIso8601String()}',
      ]);
      expect(localSyncRepository.processedIds, ['ordinary_after_recovery']);
      expect(localSyncRepository.pending, isEmpty);
    });

    test('lost recovery response leaves later deletion pending', () async {
      final recoveryStarted = Completer<void>();
      final releaseRecovery = Completer<void>();

      localSyncRepository.pending.add(
        outbox(
          id: 'pending_after_lost_response',
          type: CloudDataEntity.song,
          entityId: 'song_1',
          timestamp: timestamp,
          operation: SyncOutboxOperation.delete,
        ),
      );

      var recoveryCalls = 0;

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        metadataFieldStateRepository: metadataFieldStateRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
        cloudRevisionBaselineRepository: FakeCloudRevisionBaselineRepository(),
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('Unexpected artist mutation.');
            },
        pushArtistDeletion: ({required userId, required entry}) async {
          throw StateError('Unexpected artist deletion.');
        },
        recoverArtistWrites: (userId) async {
          recoveryCalls++;
          recoveryStarted.complete();
          await releaseRecovery.future;
          throw StateError('Receipt response still unavailable.');
        },
      );

      final push = processor.pushPending('user_1');

      // Attach the error expectation before releasing the failure.
      final expectation = expectLater(push, throwsStateError);

      await recoveryStarted.future;

      try {
        expect(cloudSyncGateway.calls, isEmpty);
        expect(localSyncRepository.pending, hasLength(1));
        expect(localSyncRepository.processedIds, isEmpty);
      } finally {
        releaseRecovery.complete();
      }

      await expectation;

      expect(recoveryCalls, 1);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(
        localSyncRepository.pending.single.id,
        'pending_after_lost_response',
      );
    });
    test('concurrent outbound runs do not duplicate album upload', () async {
      artistRepository.values['artist_1'] = artist(timestamp);
      albumRepository.values['album_1'] = album(timestamp);

      localSyncRepository.pending.add(
        outbox(
          id: 'concurrent_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
      );

      final uploadStarted = Completer<void>();
      final releaseUpload = Completer<void>();
      var albumCalls = 0;

      cloudSyncGateway.beforeUpsertCompletes = (record) async {
        if (record is CloudAlbumRecord) {
          albumCalls++;
          if (!uploadStarted.isCompleted) {
            uploadStarted.complete();
          }
          await releaseUpload.future;
        }
      };

      final first = processor.pushPending('user_1');

      try {
        await uploadStarted.future;

        final second = processor.pushPending('user_1');

        // Give the overlapping run a chance to reach the gateway.
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // A serialized processor must not start a second upload.
        expect(albumCalls, 1);

        releaseUpload.complete();

        await Future.wait([first, second]);

        expect(albumCalls, 1);
        expect(localSyncRepository.processedIds, ['concurrent_album']);
        expect(localSyncRepository.pending, isEmpty);
      } finally {
        if (!releaseUpload.isCompleted) {
          releaseUpload.complete();
        }
      }
    });
    test(
      'failed outbound run allows subsequent retry on same processor',
      () async {
        artistRepository.values['artist_1'] = artist(timestamp);
        albumRepository.values['album_1'] = album(timestamp);

        localSyncRepository.pending.add(
          outbox(
            id: 'retry_album',
            type: CloudDataEntity.album,
            entityId: 'album_1',
            timestamp: timestamp,
          ),
        );

        cloudSyncGateway.failOn = 'upsert:album:album_1';

        // The first run fails without acknowledging the album.
        await expectLater(processor.pushPending('user_1'), throwsStateError);

        expect(localSyncRepository.pending, hasLength(1));
        expect(localSyncRepository.pending.single.id, 'retry_album');
        expect(localSyncRepository.processedIds, isEmpty);

        // The same processor must remain usable after the failure.
        cloudSyncGateway.failOn = null;

        await processor.pushPending('user_1');

        expect(localSyncRepository.pending, isEmpty);
        expect(localSyncRepository.processedIds, ['retry_album']);

        // The first upload failed; the second succeeded.
        expect(
          cloudSyncGateway.calls
              .where((call) => call == 'upsert:album:album_1')
              .length,
          2,
        );
      },
    );
    test('does nothing when outbox is empty', () async {
      await processor.pushPending('user_1');

      expect(cloudArtworkStorage.calls, isEmpty);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
    });

    test('pushes related upserts in dependency order', () async {
      artworkAssetRepository.values['artwork_1'] = artwork(timestamp);
      artistRepository.values['artist_1'] = artist(timestamp);
      albumRepository.values['album_1'] = album(timestamp);
      albumEditionRepository.values['edition_1'] = edition(timestamp);
      songRepository.values['song_1'] = song(timestamp);

      localSyncRepository.pending.addAll([
        outbox(
          id: 'a_song',
          type: CloudDataEntity.song,
          entityId: 'song_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'b_edition',
          type: CloudDataEntity.albumEdition,
          entityId: 'edition_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'c_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'd_artwork',
          type: CloudDataEntity.artworkAsset,
          entityId: 'artwork_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'z_artist',
          type: CloudDataEntity.artist,
          entityId: 'artist_1',
          timestamp: timestamp,
        ),
      ]);

      await processor.pushPending('user_1');

      expect(cloudArtworkStorage.calls, ['upload:user_1:artwork_1']);

      expect(cloudSyncGateway.calls, [
        'upsert:artworkAsset:artwork_1',
        'upsert:artist:artist_1',
        'upsert:album:album_1',
        'upsert:albumEdition:edition_1',
        'upsert:song:song_1',
      ]);

      expect(localSyncRepository.processedIds, [
        'd_artwork',
        'z_artist',
        'c_album',
        'b_edition',
        'a_song',
      ]);
    });

    test(
      'embeds metadata field provenance in outbound artist record',
      () async {
        artistRepository.values['artist_1'] = artist(timestamp);

        metadataFieldStateRepository.values.add(
          MetadataFieldState(
            entityType: MetadataEntityType.artist,
            entityId: 'artist_1',
            fieldName: 'name',
            authority: MetadataAuthority.external,
            source: MetadataProvenanceSource.musicBrainz,
            sourceReference: 'musicbrainz:artist:artist-mbid',
            updatedAt: timestamp,
          ),
        );

        localSyncRepository.pending.add(
          outbox(
            id: 'outbox_artist_metadata',
            type: CloudDataEntity.artist,
            entityId: 'artist_1',
            timestamp: timestamp,
          ),
        );

        await processor.pushPending('user_1');

        final artistRecord = cloudSyncGateway.upsertedRecords
            .whereType<CloudArtistRecord>()
            .single;

        expect(artistRecord.metadataFieldStates, hasLength(1));

        final state = artistRecord.metadataFieldStates!.single;

        expect(state.fieldName, 'name');
        expect(state.authority, 'external');
        expect(state.source, 'musicBrainz');
        expect(state.sourceReference, 'musicbrainz:artist:artist-mbid');
        expect(state.updatedAt, timestamp);
      },
    );

    test('successful artwork upload writes returned storage key', () async {
      artworkAssetRepository.values['artwork_1'] = artwork(timestamp);
      cloudArtworkStorage.returnedObjectKey = 'user_1/artwork_1.png';

      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_artwork',
          type: CloudDataEntity.artworkAsset,
          entityId: 'artwork_1',
          timestamp: timestamp,
        ),
      );

      await processor.pushPending('user_1');

      expect(cloudArtworkStorage.calls, ['upload:user_1:artwork_1']);

      expect(cloudSyncGateway.calls, ['upsert:artworkAsset:artwork_1']);

      final record = cloudSyncGateway.upsertedRecords.single;
      expect(record, isA<CloudArtworkAssetRecord>());

      final artworkRecord = record as CloudArtworkAssetRecord;
      expect(artworkRecord.storageObjectKey, 'user_1/artwork_1.png');

      expect(localSyncRepository.processedIds, ['outbox_artwork']);
    });

    test('artwork storage failure leaves entry pending', () async {
      artworkAssetRepository.values['artwork_1'] = artwork(timestamp);
      cloudArtworkStorage.shouldFail = true;

      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_artwork',
          type: CloudDataEntity.artworkAsset,
          entityId: 'artwork_1',
          timestamp: timestamp,
        ),
      );

      await expectLater(
        processor.pushPending('user_1'),
        throwsA(isA<StateError>()),
      );

      expect(cloudArtworkStorage.calls, ['upload:user_1:artwork_1']);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending, hasLength(1));
    });

    test(
      'artwork database failure leaves entry pending after upload',
      () async {
        artworkAssetRepository.values['artwork_1'] = artwork(timestamp);

        localSyncRepository.pending.add(
          outbox(
            id: 'outbox_artwork',
            type: CloudDataEntity.artworkAsset,
            entityId: 'artwork_1',
            timestamp: timestamp,
          ),
        );

        cloudSyncGateway.failOn = 'upsert:artworkAsset:artwork_1';

        await expectLater(
          processor.pushPending('user_1'),
          throwsA(isA<StateError>()),
        );

        expect(cloudArtworkStorage.calls, ['upload:user_1:artwork_1']);
        expect(cloudSyncGateway.calls, ['upsert:artworkAsset:artwork_1']);
        expect(localSyncRepository.processedIds, isEmpty);
        expect(localSyncRepository.pending, hasLength(1));
      },
    );

    test('missing local artwork leaves upsert pending', () async {
      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_artwork',
          type: CloudDataEntity.artworkAsset,
          entityId: 'missing_artwork',
          timestamp: timestamp,
        ),
      );

      await expectLater(
        processor.pushPending('user_1'),
        throwsA(isA<StateError>()),
      );

      expect(cloudArtworkStorage.calls, isEmpty);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending, hasLength(1));
    });

    test('acknowledges an entry only after cloud success', () async {
      artistRepository.values['artist_1'] = artist(timestamp);

      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_artist',
          type: CloudDataEntity.artist,
          entityId: 'artist_1',
          timestamp: timestamp,
        ),
      );

      await processor.pushPending('user_1');

      expect(cloudSyncGateway.calls, ['upsert:artist:artist_1']);
      expect(localSyncRepository.processedIds, ['outbox_artist']);
    });

    test('cloud failure leaves failed and dependent entries pending', () async {
      artistRepository.values['artist_1'] = artist(timestamp);
      albumRepository.values['album_1'] = album(timestamp);
      songRepository.values['song_1'] = song(timestamp);

      localSyncRepository.pending.addAll([
        outbox(
          id: 'outbox_song',
          type: CloudDataEntity.song,
          entityId: 'song_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'outbox_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'outbox_artist',
          type: CloudDataEntity.artist,
          entityId: 'artist_1',
          timestamp: timestamp,
        ),
      ]);

      cloudSyncGateway.failOn = 'upsert:album:album_1';

      await expectLater(
        processor.pushPending('user_1'),
        throwsA(isA<StateError>()),
      );

      // The song re-attempts its album dependency and never uploads.
      expect(cloudSyncGateway.calls, [
        'upsert:artist:artist_1',
        'upsert:album:album_1',
        'upsert:album:album_1',
      ]);

      expect(localSyncRepository.processedIds, ['outbox_artist']);
      expect(
        localSyncRepository.pending.map((entry) => entry.id),
        containsAll(['outbox_album', 'outbox_song']),
      );
    });

    test('missing local entity leaves upsert pending', () async {
      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_song',
          type: CloudDataEntity.song,
          entityId: 'missing_song',
          timestamp: timestamp,
        ),
      );

      await expectLater(
        processor.pushPending('user_1'),
        throwsA(isA<StateError>()),
      );

      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending, hasLength(1));
    });

    test('delete does not require local entity and is acknowledged', () async {
      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_delete',
          type: CloudDataEntity.song,
          entityId: 'deleted_song',
          timestamp: timestamp,
          operation: SyncOutboxOperation.delete,
        ),
      );

      await processor.pushPending('user_1');

      expect(cloudSyncGateway.calls, [
        'delete:song:deleted_song:${timestamp.toIso8601String()}',
      ]);
      expect(localSyncRepository.processedIds, ['outbox_delete']);
    });

    test('rejects blank user id', () async {
      await expectLater(
        processor.pushPending('   '),
        throwsA(isA<ArgumentError>()),
      );

      expect(cloudSyncGateway.calls, isEmpty);
    });

    test('rejects an outbox entry belonging to another user', () async {
      artistRepository.values['artist_1'] = artist(timestamp);

      localSyncRepository.pending.add(
        SyncOutboxEntry(
          id: 'wrong_user_entry',
          userId: 'user_2',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
          operation: SyncOutboxOperation.upsert,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );

      await expectLater(
        processor.pushPending('user_1'),
        throwsA(isA<StateError>()),
      );

      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
    });
  });
}

SyncOutboxEntry outbox({
  required String id,
  required CloudDataEntity type,
  required String entityId,
  required DateTime timestamp,
  SyncOutboxOperation operation = SyncOutboxOperation.upsert,
}) {
  return SyncOutboxEntry(
    id: id,
    userId: 'user_1',
    entityType: type,
    entityId: entityId,
    operation: operation,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

ArtworkAsset artwork(DateTime timestamp) {
  return ArtworkAsset(
    id: 'artwork_1',
    filePath: r'C:\artwork\artwork_1.png',
    normalizedPath: r'c:\artwork\artwork_1.png',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Artist artist(DateTime timestamp) {
  return Artist(
    id: 'artist_1',
    name: 'Artist',
    canonicalName: 'artist',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Album album(DateTime timestamp) {
  return Album(
    id: 'album_1',
    artistId: 'artist_1',
    title: 'Album',
    canonicalTitle: 'album',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

AlbumEdition edition(DateTime timestamp) {
  return AlbumEdition(
    id: 'edition_1',
    albumId: 'album_1',
    title: 'Standard',
    type: AlbumEditionType.standard,
    isPrimary: true,
    artworkId: 'artwork_1',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Song song(DateTime timestamp) {
  return Song(
    id: 'song_1',
    artistId: 'artist_1',
    albumId: 'album_1',
    albumEditionId: 'edition_1',
    title: 'Song',
    canonicalTitle: 'song',
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    artworkId: 'artwork_1',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

class FakeCloudRevisionBaselineRepository
    implements CloudRevisionBaselineRepository {
  final Map<String, int> revisions = {};

  String _key(String userId, CloudDataEntity entityType, String entityId) {
    return '$userId:${entityType.name}:$entityId';
  }

  @override
  Future<int?> getRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    return revisions[_key(userId, entityType, entityId)];
  }

  @override
  Future<void> saveObservedRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
  }) async {
    final key = _key(userId, entityType, entityId);
    final current = revisions[key];

    if (current == null || serverRevision > current) {
      revisions[key] = serverRevision;
    }
  }
}

class FakeLocalSyncRepository implements LocalSyncRepository {
  final List<SyncOutboxEntry> pending = [];
  final List<String> processedIds = [];

  @override
  Future<List<SyncOutboxEntry>> getPending(String userId) async {
    return List.unmodifiable(pending);
  }

  @override
  Future<void> markProcessed({
    required String userId,
    required String outboxEntryId,
    required int expectedRevision,
    required SyncOutboxOperation expectedOperation,
  }) async {
    final matchingEntries = pending
        .where(
          (entry) =>
              entry.userId == userId &&
              entry.id == outboxEntryId &&
              entry.mutationRevision == expectedRevision &&
              entry.operation == expectedOperation,
        )
        .toList();

    if (matchingEntries.isEmpty) {
      return;
    }

    processedIds.add(outboxEntryId);
    pending.removeWhere(
      (entry) =>
          entry.userId == userId &&
          entry.id == outboxEntryId &&
          entry.mutationRevision == expectedRevision &&
          entry.operation == expectedOperation,
    );
  }

  @override
  Future<SyncCursor?> getCursor(
    String userId,
    CloudDataEntity entityType,
  ) async {
    return null;
  }

  @override
  Future<void> saveCursor(SyncCursor cursor) async {}

  @override
  Future<void> recordUpsert({
    required String? userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {}

  @override
  Future<void> recordDelete({
    required String? userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {}
}

class FakeCloudArtworkStorage implements CloudArtworkStorage {
  final List<String> calls = [];
  bool shouldFail = false;
  String returnedObjectKey = 'user_1/artwork_1.png';

  @override
  Future<String> upload({
    required String userId,
    required ArtworkAsset artworkAsset,
  }) async {
    final call = 'upload:$userId:${artworkAsset.id}';
    calls.add(call);

    if (shouldFail) {
      throw StateError('Simulated artwork storage failure.');
    }

    return returnedObjectKey;
  }
}

class FakeCloudSyncGateway implements CloudSyncGateway {
  final List<String> calls = [];
  final List<CloudOwnedRecord> upsertedRecords = [];
  String? failOn;
  Future<void> Function(CloudOwnedRecord)? beforeUpsertCompletes;

  @override
  Future<void> upsert(CloudOwnedRecord record) async {
    await _write('upsert:${_type(record)}:${record.id}', record);
  }

  @override
  Future<CloudConditionalWriteResult> insertIfAbsent(
    CloudOwnedRecord record,
  ) async {
    await _write('insert:${_type(record)}:${record.id}', record);

    return const CloudConditionalWriteResult(
      outcome: CloudConditionalWriteOutcome.applied,
      serverRevision: 1,
    );
  }

  @override
  Future<CloudConditionalWriteResult> updateIfRevision(
    CloudOwnedRecord record, {
    required int expectedServerRevision,
  }) async {
    await _write(
      'update:${_type(record)}:${record.id}@$expectedServerRevision',
      record,
    );

    return CloudConditionalWriteResult(
      outcome: CloudConditionalWriteOutcome.applied,
      serverRevision: expectedServerRevision + 1,
    );
  }

  String _type(CloudOwnedRecord record) {
    return switch (record) {
      CloudArtistRecord() => 'artist',
      CloudAlbumRecord() => 'album',
      CloudAlbumEditionRecord() => 'albumEdition',
      CloudSongRecord() => 'song',
      CloudArtworkAssetRecord() => 'artworkAsset',
      _ => 'unknown',
    };
  }

  Future<void> _write(String call, CloudOwnedRecord record) async {
    calls.add(call);
    upsertedRecords.add(record);

    if (call == failOn) {
      throw StateError('Simulated cloud failure.');
    }

    final callback = beforeUpsertCompletes;
    if (callback != null) {
      await callback(record);
    }
  }

  @override
  Future<void> markDeleted({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
  }) async {
    final call =
        'delete:${entityType.name}:$entityId:${deletedAt.toIso8601String()}';
    calls.add(call);

    if (call == failOn) {
      throw StateError('Simulated cloud failure.');
    }
  }
}

class FakeArtistRepository implements ArtistRepository {
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
  Future<void> delete(String id) async {}

  @override
  Future<List<Artist>> getAll() async => values.values.toList();
}

class FakeAlbumRepository implements AlbumRepository {
  final Map<String, Album> values = {};

  @override
  Future<Album?> getById(String id) async => values[id];

  @override
  Future<void> create(Album album) async {
    values[album.id] = album;
  }

  @override
  Future<void> save(Album album) async {
    values[album.id] = album;
  }

  @override
  Future<List<Album>> getAll() async => values.values.toList();

  @override
  Future<List<Album>> getByArtistId(String artistId) async {
    return values.values.where((album) => album.artistId == artistId).toList();
  }

  @override
  Future<List<Album>> getRecentlyAdded(int limit) async {
    return values.values.take(limit).toList();
  }
}

class FakeAlbumEditionRepository implements AlbumEditionRepository {
  final Map<String, AlbumEdition> values = {};

  @override
  Future<AlbumEdition?> getById(String id) async => values[id];

  @override
  Future<void> create(AlbumEdition edition) async {
    values[edition.id] = edition;
  }

  @override
  Future<void> save(AlbumEdition edition) async {
    values[edition.id] = edition;
  }

  @override
  Future<List<AlbumEdition>> getAll() async => values.values.toList();

  @override
  Future<List<AlbumEdition>> getByAlbumId(String albumId) async {
    return values.values
        .where((edition) => edition.albumId == albumId)
        .toList();
  }
}

class FakeSongRepository implements SongRepository {
  final Map<String, Song> values = {};

  @override
  Future<Song?> getById(String id) async => values[id];

  @override
  Future<void> create(Song song) async {
    values[song.id] = song;
  }

  @override
  Future<void> save(Song song) async {
    values[song.id] = song;
  }

  @override
  Future<List<Song>> getAll() async => values.values.toList();

  @override
  Future<List<Song>> getByArtistId(String artistId) async {
    return values.values.where((song) => song.artistId == artistId).toList();
  }

  @override
  Future<List<Song>> getByAlbumId(String albumId) async {
    return values.values.where((song) => song.albumId == albumId).toList();
  }

  @override
  Future<List<Song>> getByEditionId(String editionId) async {
    return values.values
        .where((song) => song.albumEditionId == editionId)
        .toList();
  }

  @override
  Future<List<Song>> getRecentlyAdded(int limit) async {
    return values.values.take(limit).toList();
  }
}

class FakeMetadataFieldStateRepository implements MetadataFieldStateRepository {
  final List<MetadataFieldState> values = [];

  @override
  Future<MetadataFieldState?> get({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
  }) async {
    for (final value in values) {
      if (value.entityType == entityType &&
          value.entityId == entityId &&
          value.fieldName == fieldName) {
        return value;
      }
    }

    return null;
  }

  @override
  Future<List<MetadataFieldState>> getByEntity({
    required MetadataEntityType entityType,
    required String entityId,
  }) async {
    return values
        .where(
          (value) =>
              value.entityType == entityType && value.entityId == entityId,
        )
        .toList(growable: false);
  }

  @override
  Future<void> save(MetadataFieldState state) async {
    values.removeWhere(
      (value) =>
          value.entityType == state.entityType &&
          value.entityId == state.entityId &&
          value.fieldName == state.fieldName,
    );

    values.add(state);
  }

  @override
  Future<void> delete({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
  }) async {
    values.removeWhere(
      (value) =>
          value.entityType == entityType &&
          value.entityId == entityId &&
          value.fieldName == fieldName,
    );
  }

  @override
  Future<void> deleteByEntity({
    required MetadataEntityType entityType,
    required String entityId,
  }) async {
    values.removeWhere(
      (value) => value.entityType == entityType && value.entityId == entityId,
    );
  }
}

class FakeArtworkAssetRepository implements ArtworkAssetRepository {
  final Map<String, ArtworkAsset> values = {};

  @override
  Future<ArtworkAsset?> getById(String id) async => values[id];

  @override
  Future<ArtworkAsset?> getByNormalizedPath(String normalizedPath) async {
    for (final value in values.values) {
      if (value.normalizedPath == normalizedPath) {
        return value;
      }
    }

    return null;
  }

  @override
  Future<void> create(ArtworkAsset artworkAsset) async {
    values[artworkAsset.id] = artworkAsset;
  }

  @override
  Future<void> save(ArtworkAsset artworkAsset) async {
    values[artworkAsset.id] = artworkAsset;
  }

  @override
  Future<List<ArtworkAsset>> getAll() async => values.values.toList();
}
