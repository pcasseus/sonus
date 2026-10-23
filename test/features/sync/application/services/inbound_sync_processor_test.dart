import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_processor.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_reconciler.dart';
import 'package:sonus_next/features/sync/domain/models/inbound_deferred_record.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  const replayWindow = Duration(minutes: 2);

  group('InboundSyncProcessor', () {
    test('pulls entities in dependency order', () async {
      final reconciler = _FakeInboundSyncPageReconciler();

      final processor = InboundSyncProcessor(
        reconciler: reconciler,
        replayWindow: replayWindow,
      );

      final processed = await processor.pullAll(userId: 'user-1', pageSize: 25);

      expect(processed, 0);

      expect(reconciler.replayCalls.map((call) => call.entityType).toList(), [
        CloudDataEntity.artworkAsset,
        CloudDataEntity.artist,
        CloudDataEntity.album,
        CloudDataEntity.albumEdition,
        CloudDataEntity.song,
      ]);

      expect(reconciler.calls.map((call) => call.entityType).toList(), [
        CloudDataEntity.artworkAsset,
        CloudDataEntity.artist,
        CloudDataEntity.album,
        CloudDataEntity.albumEdition,
        CloudDataEntity.song,
      ]);

      expect(
        reconciler.replayCalls.every(
          (call) => call.replayWindow == replayWindow,
        ),
        isTrue,
      );

      expect(reconciler.calls.every((call) => call.limit == 25), isTrue);
    });

    group('deferred replay', () {
      test(
        'runs once after every cursor page, with the bounded limit',
        () async {
          final reconciler = _FakeInboundSyncPageReconciler();

          final processor = InboundSyncProcessor(
            reconciler: reconciler,
            replayWindow: replayWindow,
            deferredReplayFetchLimit: 7,
          );

          await processor.pullAll(userId: ' user-1 ');

          expect(reconciler.deferredReplays, [('user-1', 7, 5)]);
        },
      );

      test('rejects a nonpositive limit before reconciliation', () async {
        final reconciler = _FakeInboundSyncPageReconciler();

        await expectLater(
          InboundSyncProcessor(
            reconciler: reconciler,
            replayWindow: replayWindow,
            deferredReplayFetchLimit: 0,
          ).pullAll(userId: 'user-1'),
          throwsArgumentError,
        );

        expect(reconciler.calls, isEmpty);
        expect(reconciler.deferredReplays, isEmpty);
      });

      test('defaults to a bounded fetch limit', () async {
        final reconciler = _FakeInboundSyncPageReconciler();

        await InboundSyncProcessor(
          reconciler: reconciler,
          replayWindow: replayWindow,
        ).pullAll(userId: 'user-1');

        expect(reconciler.deferredReplays.single.$2, 50);
      });

      test('counts applied replays as processed records', () async {
        final reconciler = _FakeInboundSyncPageReconciler()
          ..responses[CloudDataEntity.song] = [
            const InboundSyncBatchResult(
              processedCount: 2,
              hasMore: false,
              lastReadPosition: null,
            ),
          ]
          ..deferredReplayResult = const InboundReplayResult(
            appliedCount: 3,
            stillDeferredCount: 4,
            skippedCount: 5,
            unresolvedCount: 1,
          );

        final processed = await InboundSyncProcessor(
          reconciler: reconciler,
          replayWindow: replayWindow,
        ).pullAll(userId: 'user-1');

        expect(processed, 5);
      });

      test('reports the first failure after the whole pass', () async {
        final first = StateError('first replay failure');
        final record = InboundDeferredRecord(
          userId: 'user-1',
          entityType: CloudDataEntity.album,
          entityId: 'album-1',
          serverRevision: 2,
          serverUpdatedAt: DateTime.utc(2026, 10, 22),
          reason: InboundDeferralReason.missingLocalParent,
          deferredAt: DateTime.utc(2026, 10, 22),
        );

        final reconciler = _FakeInboundSyncPageReconciler()
          ..deferredReplayResult = InboundReplayResult(
            appliedCount: 1,
            failures: [
              InboundReplayFailure(
                record: record,
                error: first,
                stackTrace: StackTrace.current,
              ),
              InboundReplayFailure(
                record: record,
                error: StateError('second replay failure'),
                stackTrace: StackTrace.current,
              ),
            ],
          );

        await expectLater(
          InboundSyncProcessor(
            reconciler: reconciler,
            replayWindow: replayWindow,
          ).pullAll(userId: 'user-1'),
          throwsA(same(first)),
        );

        expect(reconciler.deferredReplays, hasLength(1));
      });

      test('does not replay when a cursor page fails', () async {
        final reconciler = _FakeInboundSyncPageReconciler()
          ..responses[CloudDataEntity.artist] = [
            const InboundSyncBatchResult(
              processedCount: 0,
              hasMore: true,
              lastReadPosition: null,
            ),
          ];

        await expectLater(
          InboundSyncProcessor(
            reconciler: reconciler,
            replayWindow: replayWindow,
          ).pullAll(userId: 'user-1'),
          throwsStateError,
        );

        expect(reconciler.deferredReplays, isEmpty);
      });
    });

    test(
      'uses replay start once then continues from last read position',
      () async {
        final reconciler = _FakeInboundSyncPageReconciler();

        final replayStart = DateTime.utc(2026, 9, 13, 9, 58);

        final firstPosition = CloudSyncPosition(
          serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
          id: 'artist-b',
        );

        reconciler.replayStarts[CloudDataEntity.artist] = replayStart;

        reconciler.responses[CloudDataEntity.artist] = [
          InboundSyncBatchResult(
            processedCount: 2,
            hasMore: true,
            lastReadPosition: firstPosition,
          ),
          InboundSyncBatchResult(
            processedCount: 1,
            hasMore: false,
            lastReadPosition: CloudSyncPosition(
              serverUpdatedAt: DateTime.utc(2026, 9, 13, 11),
              id: 'artist-c',
            ),
          ),
        ];

        final processor = InboundSyncProcessor(
          reconciler: reconciler,
          replayWindow: replayWindow,
        );

        final processed = await processor.pullAll(
          userId: 'user-1',
          pageSize: 10,
        );

        expect(processed, 3);

        final artistCalls = reconciler.calls
            .where((call) => call.entityType == CloudDataEntity.artist)
            .toList();

        expect(artistCalls.length, 2);

        expect(artistCalls.first.after, isNull);
        expect(artistCalls.first.fromServerUpdatedAtInclusive, replayStart);

        expect(artistCalls.last.after, same(firstPosition));
        expect(artistCalls.last.fromServerUpdatedAtInclusive, isNull);
      },
    );

    test('exhausts all pages before advancing entity type', () async {
      final reconciler = _FakeInboundSyncPageReconciler();

      reconciler.responses[CloudDataEntity.artist] = [
        InboundSyncBatchResult(
          processedCount: 2,
          hasMore: true,
          lastReadPosition: CloudSyncPosition(
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            id: 'artist-b',
          ),
        ),
        InboundSyncBatchResult(
          processedCount: 1,
          hasMore: false,
          lastReadPosition: CloudSyncPosition(
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 11),
            id: 'artist-c',
          ),
        ),
      ];

      final processor = InboundSyncProcessor(
        reconciler: reconciler,
        replayWindow: replayWindow,
      );

      final processed = await processor.pullAll(userId: 'user-1', pageSize: 10);

      expect(processed, 3);

      expect(reconciler.calls.map((call) => call.entityType).toList(), [
        CloudDataEntity.artworkAsset,
        CloudDataEntity.artist,
        CloudDataEntity.artist,
        CloudDataEntity.album,
        CloudDataEntity.albumEdition,
        CloudDataEntity.song,
      ]);
    });

    test('sums processed records across entity types', () async {
      final reconciler = _FakeInboundSyncPageReconciler();

      reconciler.responses[CloudDataEntity.artworkAsset] = [
        const InboundSyncBatchResult(
          processedCount: 1,
          hasMore: false,
          lastReadPosition: null,
        ),
      ];

      reconciler.responses[CloudDataEntity.artist] = [
        const InboundSyncBatchResult(
          processedCount: 2,
          hasMore: false,
          lastReadPosition: null,
        ),
      ];

      reconciler.responses[CloudDataEntity.album] = [
        const InboundSyncBatchResult(
          processedCount: 3,
          hasMore: false,
          lastReadPosition: null,
        ),
      ];

      reconciler.responses[CloudDataEntity.albumEdition] = [
        const InboundSyncBatchResult(
          processedCount: 4,
          hasMore: false,
          lastReadPosition: null,
        ),
      ];

      reconciler.responses[CloudDataEntity.song] = [
        const InboundSyncBatchResult(
          processedCount: 5,
          hasMore: false,
          lastReadPosition: null,
        ),
      ];

      final processor = InboundSyncProcessor(
        reconciler: reconciler,
        replayWindow: replayWindow,
      );

      final processed = await processor.pullAll(userId: 'user-1');

      expect(processed, 15);
    });

    test('rejects zero progress when reconciler reports more pages', () async {
      final reconciler = _FakeInboundSyncPageReconciler();

      reconciler.responses[CloudDataEntity.artworkAsset] = [
        const InboundSyncBatchResult(
          processedCount: 0,
          hasMore: true,
          lastReadPosition: null,
        ),
      ];

      final processor = InboundSyncProcessor(
        reconciler: reconciler,
        replayWindow: replayWindow,
      );

      await expectLater(processor.pullAll(userId: 'user-1'), throwsStateError);

      expect(reconciler.calls.length, 1);
      expect(reconciler.calls.single.entityType, CloudDataEntity.artworkAsset);
    });

    test('trims user id before replay and reconciliation', () async {
      final reconciler = _FakeInboundSyncPageReconciler();

      final processor = InboundSyncProcessor(
        reconciler: reconciler,
        replayWindow: replayWindow,
      );

      await processor.pullAll(userId: '  user-1  ');

      expect(
        reconciler.replayCalls.every((call) => call.userId == 'user-1'),
        isTrue,
      );

      expect(reconciler.calls.every((call) => call.userId == 'user-1'), isTrue);
    });

    test('rejects blank user id before reconciliation', () async {
      final reconciler = _FakeInboundSyncPageReconciler();

      final processor = InboundSyncProcessor(
        reconciler: reconciler,
        replayWindow: replayWindow,
      );

      await expectLater(processor.pullAll(userId: '   '), throwsArgumentError);

      expect(reconciler.replayCalls, isEmpty);
      expect(reconciler.calls, isEmpty);
    });

    test('rejects nonpositive page size before reconciliation', () async {
      final reconciler = _FakeInboundSyncPageReconciler();

      final processor = InboundSyncProcessor(
        reconciler: reconciler,
        replayWindow: replayWindow,
      );

      await expectLater(
        processor.pullAll(userId: 'user-1', pageSize: 0),
        throwsArgumentError,
      );

      expect(reconciler.replayCalls, isEmpty);
      expect(reconciler.calls, isEmpty);
    });

    test('rejects negative replay window before reconciliation', () async {
      final reconciler = _FakeInboundSyncPageReconciler();

      final processor = InboundSyncProcessor(
        reconciler: reconciler,
        replayWindow: const Duration(seconds: -1),
      );

      await expectLater(
        processor.pullAll(userId: 'user-1'),
        throwsArgumentError,
      );

      expect(reconciler.replayCalls, isEmpty);
      expect(reconciler.calls, isEmpty);
    });
  });
}

class _FakeInboundSyncPageReconciler implements InboundSyncPageReconciler {
  final Map<CloudDataEntity, List<InboundSyncBatchResult>> responses = {};
  final Map<CloudDataEntity, DateTime?> replayStarts = {};

  final List<_ReplayCall> replayCalls = [];
  final List<_ReconcileCall> calls = [];

  /// Each replayDeferred call, recorded as (userId, maxFetches, pages seen).
  final List<(String, int, int)> deferredReplays = [];
  InboundReplayResult deferredReplayResult = const InboundReplayResult();

  @override
  Future<InboundReplayResult> replayDeferred({
    required String userId,
    required int maxFetches,
  }) async {
    deferredReplays.add((userId, maxFetches, calls.length));
    return deferredReplayResult;
  }

  @override
  Future<DateTime?> replayStart({
    required String userId,
    required CloudDataEntity entityType,
    required Duration replayWindow,
  }) async {
    replayCalls.add(
      _ReplayCall(
        userId: userId,
        entityType: entityType,
        replayWindow: replayWindow,
      ),
    );

    return replayStarts[entityType];
  }

  @override
  Future<InboundSyncBatchResult> reconcilePage({
    required String userId,
    required CloudDataEntity entityType,
    required int limit,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
  }) async {
    calls.add(
      _ReconcileCall(
        userId: userId,
        entityType: entityType,
        limit: limit,
        after: after,
        fromServerUpdatedAtInclusive: fromServerUpdatedAtInclusive,
      ),
    );

    final queued = responses[entityType];

    if (queued == null || queued.isEmpty) {
      return const InboundSyncBatchResult(
        processedCount: 0,
        hasMore: false,
        lastReadPosition: null,
      );
    }

    return queued.removeAt(0);
  }
}

class _ReplayCall {
  const _ReplayCall({
    required this.userId,
    required this.entityType,
    required this.replayWindow,
  });

  final String userId;
  final CloudDataEntity entityType;
  final Duration replayWindow;
}

class _ReconcileCall {
  const _ReconcileCall({
    required this.userId,
    required this.entityType,
    required this.limit,
    required this.after,
    required this.fromServerUpdatedAtInclusive,
  });

  final String userId;
  final CloudDataEntity entityType;
  final int limit;
  final CloudSyncPosition? after;
  final DateTime? fromServerUpdatedAtInclusive;
}
