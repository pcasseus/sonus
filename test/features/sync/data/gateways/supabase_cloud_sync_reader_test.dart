import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_cloud_sync_row_source.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  group('SupabaseCloudSyncReader', () {
    test('reads initial page in server timestamp and id order', () async {
      final source = _FakeRowSource([
        _artistRow(id: 'b', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'a', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'c', serverUpdatedAt: '2026-09-13T11:00:00.000Z'),
      ]);

      final reader = SupabaseCloudSyncReader.withRowSource(source);

      final page = await reader.readPage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        limit: 2,
      );

      expect(page.items.map((item) => item.record.id).toList(), ['a', 'b']);
      expect(page.hasMore, isTrue);
      expect(page.lastPosition?.id, 'b');
      expect(
        page.lastPosition?.serverUpdatedAt,
        DateTime.parse('2026-09-13T10:00:00.000Z').toUtc(),
      );
    });

    test('continues after id when many rows share cursor timestamp', () async {
      final source = _FakeRowSource([
        _artistRow(id: 'a', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'b', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'c', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'd', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'e', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'f', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
      ]);

      final reader = SupabaseCloudSyncReader.withRowSource(source);

      final page = await reader.readPage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        after: CloudSyncPosition(
          serverUpdatedAt: DateTime.parse('2026-09-13T10:00:00.000Z'),
          id: 'c',
        ),
        limit: 2,
      );

      expect(page.items.map((item) => item.record.id).toList(), ['d', 'e']);
      expect(page.hasMore, isTrue);
      expect(page.lastPosition?.id, 'e');
    });

    test('fills remaining page space with later timestamps', () async {
      final source = _FakeRowSource([
        _artistRow(id: 'a', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'b', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'c', serverUpdatedAt: '2026-09-13T11:00:00.000Z'),
        _artistRow(id: 'd', serverUpdatedAt: '2026-09-13T12:00:00.000Z'),
      ]);

      final reader = SupabaseCloudSyncReader.withRowSource(source);

      final page = await reader.readPage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        after: CloudSyncPosition(
          serverUpdatedAt: DateTime.parse('2026-09-13T10:00:00.000Z'),
          id: 'a',
        ),
        limit: 3,
      );

      expect(page.items.map((item) => item.record.id).toList(), [
        'b',
        'c',
        'd',
      ]);
      expect(page.hasMore, isFalse);
    });

    test('reports hasMore when later timestamp rows exceed page', () async {
      final source = _FakeRowSource([
        _artistRow(id: 'a', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'b', serverUpdatedAt: '2026-09-13T11:00:00.000Z'),
        _artistRow(id: 'c', serverUpdatedAt: '2026-09-13T12:00:00.000Z'),
        _artistRow(id: 'd', serverUpdatedAt: '2026-09-13T13:00:00.000Z'),
      ]);

      final reader = SupabaseCloudSyncReader.withRowSource(source);

      final page = await reader.readPage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        after: CloudSyncPosition(
          serverUpdatedAt: DateTime.parse('2026-09-13T10:00:00.000Z'),
          id: 'a',
        ),
        limit: 2,
      );

      expect(page.items.map((item) => item.record.id).toList(), ['b', 'c']);
      expect(page.hasMore, isTrue);
      expect(page.lastPosition?.id, 'c');
    });

    test('reads replay page inclusively from server timestamp', () async {
      final source = _FakeRowSource([
        _artistRow(id: 'a', serverUpdatedAt: '2026-09-13T09:59:59.000Z'),
        _artistRow(id: 'b', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'c', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'd', serverUpdatedAt: '2026-09-13T11:00:00.000Z'),
      ]);

      final reader = SupabaseCloudSyncReader.withRowSource(source);

      final page = await reader.readPage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        fromServerUpdatedAtInclusive: DateTime.parse(
          '2026-09-13T10:00:00.000Z',
        ),
        limit: 10,
      );

      expect(page.items.map((item) => item.record.id).toList(), [
        'b',
        'c',
        'd',
      ]);
      expect(page.hasMore, isFalse);
      expect(page.lastPosition?.id, 'd');
    });

    test('reports hasMore for inclusive replay page', () async {
      final source = _FakeRowSource([
        _artistRow(id: 'a', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'b', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
        _artistRow(id: 'c', serverUpdatedAt: '2026-09-13T11:00:00.000Z'),
      ]);

      final reader = SupabaseCloudSyncReader.withRowSource(source);

      final page = await reader.readPage(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        fromServerUpdatedAtInclusive: DateTime.parse(
          '2026-09-13T10:00:00.000Z',
        ),
        limit: 2,
      );

      expect(page.items.map((item) => item.record.id).toList(), ['a', 'b']);
      expect(page.hasMore, isTrue);
      expect(page.lastPosition?.id, 'b');
    });

    test('rejects after and inclusive replay start together', () async {
      final reader = SupabaseCloudSyncReader.withRowSource(
        _FakeRowSource(const []),
      );

      await expectLater(
        reader.readPage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          after: CloudSyncPosition(
            serverUpdatedAt: DateTime.utc(2026, 9, 13, 10),
            id: 'artist-a',
          ),
          fromServerUpdatedAtInclusive: DateTime.utc(2026, 9, 13, 9),
          limit: 10,
        ),
        throwsArgumentError,
      );
    });

    test('trims user id before querying row source', () async {
      final source = _FakeRowSource([
        _artistRow(id: 'a', serverUpdatedAt: '2026-09-13T10:00:00.000Z'),
      ]);

      final reader = SupabaseCloudSyncReader.withRowSource(source);

      await reader.readPage(
        userId: '  user-1  ',
        entityType: CloudDataEntity.artist,
        limit: 10,
      );

      expect(source.lastUserId, 'user-1');
    });

    test('rejects blank user id', () async {
      final reader = SupabaseCloudSyncReader.withRowSource(
        _FakeRowSource(const []),
      );

      expect(
        () => reader.readPage(
          userId: '   ',
          entityType: CloudDataEntity.artist,
          limit: 10,
        ),
        throwsArgumentError,
      );
    });

    test('rejects nonpositive limit', () async {
      final reader = SupabaseCloudSyncReader.withRowSource(
        _FakeRowSource(const []),
      );

      expect(
        () => reader.readPage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}

class _FakeRowSource implements SupabaseCloudSyncRowSource {
  _FakeRowSource(this.rows);

  final List<Map<String, dynamic>> rows;

  String? lastUserId;

  @override
  Future<List<Map<String, dynamic>>> readInitial({
    required String table,
    required String userId,
    required int limit,
  }) async {
    lastUserId = userId;

    final result =
        rows.where((row) => row['user_id'] == userId).toList(growable: false)
          ..sort(_compareRows);

    return result.take(limit).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> readFromServerTimestampInclusive({
    required String table,
    required String userId,
    required DateTime serverUpdatedAt,
    required int limit,
  }) async {
    lastUserId = userId;

    final boundary = serverUpdatedAt.toUtc();

    final result =
        rows
            .where((row) {
              if (row['user_id'] != userId) {
                return false;
              }

              final rowTimestamp = DateTime.parse(
                row['server_updated_at'] as String,
              ).toUtc();

              return !rowTimestamp.isBefore(boundary);
            })
            .toList(growable: false)
          ..sort(_compareRows);

    return result.take(limit).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> readAtCursorTimestamp({
    required String table,
    required String userId,
    required DateTime serverUpdatedAt,
    required String afterId,
    required int limit,
  }) async {
    lastUserId = userId;

    final result =
        rows
            .where((row) {
              if (row['user_id'] != userId) {
                return false;
              }

              final rowTimestamp = DateTime.parse(
                row['server_updated_at'] as String,
              ).toUtc();

              final rowId = row['id'] as String;

              return rowTimestamp == serverUpdatedAt.toUtc() &&
                  rowId.compareTo(afterId) > 0;
            })
            .toList(growable: false)
          ..sort((left, right) {
            return (left['id'] as String).compareTo(right['id'] as String);
          });

    return result.take(limit).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> readAfterCursorTimestamp({
    required String table,
    required String userId,
    required DateTime serverUpdatedAt,
    required int limit,
  }) async {
    lastUserId = userId;

    final result =
        rows
            .where((row) {
              if (row['user_id'] != userId) {
                return false;
              }

              final rowTimestamp = DateTime.parse(
                row['server_updated_at'] as String,
              ).toUtc();

              return rowTimestamp.isAfter(serverUpdatedAt.toUtc());
            })
            .toList(growable: false)
          ..sort(_compareRows);

    return result.take(limit).toList(growable: false);
  }

  int _compareRows(Map<String, dynamic> left, Map<String, dynamic> right) {
    final leftTimestamp = DateTime.parse(
      left['server_updated_at'] as String,
    ).toUtc();

    final rightTimestamp = DateTime.parse(
      right['server_updated_at'] as String,
    ).toUtc();

    final timestampComparison = leftTimestamp.compareTo(rightTimestamp);

    if (timestampComparison != 0) {
      return timestampComparison;
    }

    return (left['id'] as String).compareTo(right['id'] as String);
  }
}

Map<String, dynamic> _artistRow({
  required String id,
  required String serverUpdatedAt,
}) {
  return {
    'id': id,
    'user_id': 'user-1',
    'name': 'Artist $id',
    'canonical_name': 'artist $id',
    'header_artwork_id': null,
    'top_artists_artwork_id': null,
    'created_at': '2026-09-10T10:00:00.000Z',
    'updated_at': '2026-09-11T11:00:00.000Z',
    'server_updated_at': serverUpdatedAt,
    'deleted_at': null,
  };
}
