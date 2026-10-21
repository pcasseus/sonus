import '../../domain/models/cloud_records.dart';
import '../../domain/models/sync_data_contract.dart';

class CloudSyncPosition {
  const CloudSyncPosition({required this.serverUpdatedAt, required this.id});

  final DateTime serverUpdatedAt;
  final String id;
}

class CloudSyncItem {
  const CloudSyncItem({
    required this.record,
    required this.serverUpdatedAt,
    this.serverRevision,
  });

  final CloudOwnedRecord record;
  final DateTime serverUpdatedAt;

  /// Null means that a verified server revision is not available.
  final int? serverRevision;
}

class CloudSyncPage {
  const CloudSyncPage({required this.items, required this.hasMore});

  final List<CloudSyncItem> items;
  final bool hasMore;

  CloudSyncPosition? get lastPosition {
    if (items.isEmpty) {
      return null;
    }

    final last = items.last;

    return CloudSyncPosition(
      serverUpdatedAt: last.serverUpdatedAt,
      id: last.record.id,
    );
  }
}

abstract interface class CloudSyncReader {
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  });
}
