import '../../domain/models/sync_data_contract.dart';
import 'cloud_sync_reader.dart';
import 'inbound_sync_reconciler.dart';

class InboundSyncProcessor {
  const InboundSyncProcessor({
    required this.reconciler,
    required this.replayWindow,
  });

  final InboundSyncPageReconciler reconciler;
  final Duration replayWindow;

  Future<int> pullAll({required String userId, int pageSize = 100}) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    if (pageSize <= 0) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Page size must be greater than zero.',
      );
    }

    if (replayWindow.isNegative) {
      throw ArgumentError.value(
        replayWindow,
        'replayWindow',
        'Replay window must not be negative.',
      );
    }

    var totalProcessed = 0;

    for (final entityType in _dependencyOrder) {
      final replayStart = await reconciler.replayStart(
        userId: normalizedUserId,
        entityType: entityType,
        replayWindow: replayWindow,
      );

      CloudSyncPosition? cyclePosition;
      var isFirstPage = true;

      while (true) {
        final result = await reconciler.reconcilePage(
          userId: normalizedUserId,
          entityType: entityType,
          limit: pageSize,
          after: isFirstPage ? null : cyclePosition,
          fromServerUpdatedAtInclusive: isFirstPage ? replayStart : null,
        );

        isFirstPage = false;
        totalProcessed += result.processedCount;

        if (!result.hasMore) {
          break;
        }

        if (result.processedCount == 0 || result.lastReadPosition == null) {
          throw StateError(
            'Inbound sync reported more data for ${entityType.name} '
            'without advancing its read position.',
          );
        }

        cyclePosition = result.lastReadPosition;
      }
    }

    return totalProcessed;
  }

  static const List<CloudDataEntity> _dependencyOrder = [
    CloudDataEntity.artworkAsset,
    CloudDataEntity.artist,
    CloudDataEntity.album,
    CloudDataEntity.albumEdition,
    CloudDataEntity.song,
  ];
}
