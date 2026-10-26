import '../../domain/models/cloud_archive_record.dart';

/// Result of a write that only applies when the cloud is as expected.
enum CloudArchiveWriteOutcome {
  /// Written; [CloudArchiveWriteResult.serverRevision] is the new revision.
  applied,

  /// Not written: the record already exists, or changed since it was read.
  conflict,
}

class CloudArchiveWriteResult {
  const CloudArchiveWriteResult(this.outcome, [this.serverRevision]);

  final CloudArchiveWriteOutcome outcome;
  final int? serverRevision;
}

/// The cloud side of the archive. Every write is keyed by a permanent
/// identity and is either insert-if-absent or compare-and-set, so a retry
/// after a lost response can never duplicate or overwrite.
abstract interface class CloudArchiveGateway {
  /// False when the server does not have the archive yet. The app then
  /// skips the archive and behaves as before.
  Future<bool> isAvailable();

  /// Records changed after [after], oldest first.
  Future<List<CloudArchiveRecord>> readPage({
    required String userId,
    CloudArchiveCursor? after,
    required int limit,
  });

  /// The current cloud copies of [keys] of one kind.
  Future<List<CloudArchiveRecord>> fetch({
    required String userId,
    required CloudArchiveKind kind,
    required List<String> keys,
  });

  Future<CloudArchiveWriteResult> insertIfAbsent({
    required String userId,
    required CloudArchiveRecord record,
  });

  Future<CloudArchiveWriteResult> updateIfRevision({
    required String userId,
    required CloudArchiveRecord record,
    required int expectedServerRevision,
  });
}
