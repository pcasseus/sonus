import 'dart:convert';
import 'dart:io';

import 'package:sonus_next/features/sync/application/services/cloud_archive_gateway.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_archive_record.dart';

/// An in-memory archive with the server's rules: rows owned per account,
/// permanent keys, insert-if-absent, compare-and-set on the revision and
/// ordered reads.
class InMemoryCloudArchive implements CloudArchiveGateway {
  final _accounts = <String, Map<String, CloudArchiveRecord>>{};
  bool available = true;
  int writes = 0;

  /// Applies the next write but loses its response.
  bool loseNextResponse = false;

  var _clock = DateTime.utc(2026, 10, 1);

  /// The rows one account owns, by `kind:key`.
  Map<String, CloudArchiveRecord> rowsFor(String userId) =>
      _accounts.putIfAbsent(userId, () => {});

  CloudArchiveWriteResult _store(
    String userId,
    CloudArchiveRecord record,
    int revision,
  ) {
    _clock = _clock.add(const Duration(seconds: 1));
    rowsFor(userId)[record.recordId] = CloudArchiveRecord(
      kind: record.kind,
      key: record.key,
      payload: Map<String, Object?>.from(
        jsonDecode(jsonEncode(record.payload)) as Map,
      ),
      clientUpdatedAt: record.clientUpdatedAt,
      isDeleted: record.isDeleted,
      serverRevision: revision,
      serverUpdatedAt: _clock,
    );
    writes++;
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const SocketException('response lost');
    }
    return CloudArchiveWriteResult(CloudArchiveWriteOutcome.applied, revision);
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<CloudArchiveRecord>> readPage({
    required String userId,
    CloudArchiveCursor? after,
    required int limit,
  }) async {
    final ordered = rowsFor(userId).values.toList()
      ..sort((a, b) {
        final at = a.serverUpdatedAt!.compareTo(b.serverUpdatedAt!);
        return at != 0 ? at : a.recordId.compareTo(b.recordId);
      });
    return ordered
        .where(
          (r) =>
              after == null ||
              r.serverUpdatedAt!.isAfter(after.serverUpdatedAt) ||
              (r.serverUpdatedAt == after.serverUpdatedAt &&
                  r.recordId.compareTo(after.recordId) > 0),
        )
        .take(limit)
        .toList();
  }

  @override
  Future<List<CloudArchiveRecord>> fetch({
    required String userId,
    required CloudArchiveKind kind,
    required List<String> keys,
  }) async => [
    for (final key in keys) ?rowsFor(userId)['${kind.wireName}:$key'],
  ];

  @override
  Future<CloudArchiveWriteResult> insertIfAbsent({
    required String userId,
    required CloudArchiveRecord record,
  }) async {
    if (rowsFor(userId).containsKey(record.recordId)) {
      return const CloudArchiveWriteResult(CloudArchiveWriteOutcome.conflict);
    }
    return _store(userId, record, 1);
  }

  @override
  Future<CloudArchiveWriteResult> updateIfRevision({
    required String userId,
    required CloudArchiveRecord record,
    required int expectedServerRevision,
  }) async {
    final current = rowsFor(userId)[record.recordId];
    if (current == null || current.serverRevision != expectedServerRevision) {
      return const CloudArchiveWriteResult(CloudArchiveWriteOutcome.conflict);
    }
    return _store(userId, record, expectedServerRevision + 1);
  }
}
