import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/sync/application/repositories/local_sync_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_gateway.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/outbound_sync_processor.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

import 'outbound_sync_processor_test.dart' as fx;

/// A cloud table with real compare-and-set semantics, which can fail a
/// write before it applies or after it applies (a lost response).
class _Cloud implements CloudSyncGateway {
  final Map<String, (CloudOwnedRecord, int)> rows = {};
  final List<String> attempts = [];
  final Set<String> failBefore = {};
  final Set<String> loseResponse = {};

  String _key(CloudOwnedRecord record) => '${record.runtimeType}:${record.id}';

  void _maybeFail(String call) {
    if (failBefore.remove(call)) {
      throw TimeoutException('Simulated timeout before the write applied.');
    }
  }

  CloudConditionalWriteResult _applied(String call, int revision) {
    if (loseResponse.remove(call)) {
      throw TimeoutException('Simulated timeout after the write applied.');
    }
    return CloudConditionalWriteResult(
      outcome: CloudConditionalWriteOutcome.applied,
      serverRevision: revision,
    );
  }

  @override
  Future<CloudConditionalWriteResult> insertIfAbsent(
    CloudOwnedRecord record,
  ) async {
    final call = 'insert:${record.id}';
    attempts.add(call);
    _maybeFail(call);

    final existing = rows[_key(record)];
    if (existing != null) {
      return CloudConditionalWriteResult(
        outcome: CloudConditionalWriteOutcome.conflict,
        serverRevision: existing.$2,
      );
    }
    rows[_key(record)] = (record, 1);
    return _applied(call, 1);
  }

  @override
  Future<CloudConditionalWriteResult> updateIfRevision(
    CloudOwnedRecord record, {
    required int expectedServerRevision,
  }) async {
    final call = 'update:${record.id}@$expectedServerRevision';
    attempts.add(call);
    _maybeFail(call);

    final existing = rows[_key(record)];
    if (existing == null) {
      return const CloudConditionalWriteResult(
        outcome: CloudConditionalWriteOutcome.notFound,
        serverRevision: null,
      );
    }
    if (existing.$2 != expectedServerRevision) {
      return CloudConditionalWriteResult(
        outcome: CloudConditionalWriteOutcome.conflict,
        serverRevision: existing.$2,
      );
    }
    rows[_key(record)] = (record, existing.$2 + 1);
    return _applied(call, existing.$2 + 1);
  }

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    for (final (record, revision) in rows.values) {
      if (record.id == entityId && record.userId == userId) {
        return CloudSyncItem(
          record: record,
          serverUpdatedAt: record.updatedAt,
          serverRevision: revision,
        );
      }
    }
    return null;
  }

  @override
  Future<void> upsert(CloudOwnedRecord record) =>
      throw StateError('Unconditional writes are not used here.');

  @override
  Future<CloudConditionalWriteResult> markDeletedIfRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
    required int expectedServerRevision,
  }) => throw UnimplementedError();

  @override
  Future<void> markDeleted({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
  }) => throw UnimplementedError();
}

void main() {
  final timestamp = DateTime.utc(2026, 10, 25, 12);

  late _Cloud cloud;
  late fx.FakeArtistRepository artists;
  late fx.FakeAlbumRepository albums;
  late fx.FakeCloudRevisionBaselineRepository baselines;

  setUp(() {
    cloud = _Cloud();
    artists = fx.FakeArtistRepository()
      ..values['artist_1'] = fx.artist(timestamp);
    albums = fx.FakeAlbumRepository()..values['album_1'] = fx.album(timestamp);
    // The artist is already in the cloud; albums only depend on it.
    baselines = fx.FakeCloudRevisionBaselineRepository()
      ..revisions['user_1:artist:artist_1'] = 1;
  });

  Album secondAlbum() => Album(
    id: 'album_2',
    artistId: 'artist_1',
    title: 'Second',
    canonicalTitle: 'second',
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  OutboundSyncProcessor processor(LocalSyncRepository outbox) =>
      OutboundSyncProcessor(
        localSyncRepository: outbox,
        artistRepository: artists,
        albumRepository: albums,
        albumEditionRepository: fx.FakeAlbumEditionRepository(),
        songRepository: fx.FakeSongRepository(),
        metadataFieldStateRepository: fx.FakeMetadataFieldStateRepository(),
        artworkAssetRepository: fx.FakeArtworkAssetRepository(),
        cloudArtworkStorage: fx.FakeCloudArtworkStorage(),
        cloudSyncGateway: cloud,
        cloudRevisionBaselineRepository: baselines,
        pushArtistMutation:
            ({required userId, required entry, required artist}) async {
              throw StateError('No artist edits in these tests.');
            },
      );

  fx.FakeLocalSyncRepository outboxWith(List<String> albumIds) {
    final outbox = fx.FakeLocalSyncRepository();
    for (final id in albumIds) {
      outbox.pending.add(
        fx.outbox(
          id: 'outbox_$id',
          type: CloudDataEntity.album,
          entityId: id,
          timestamp: timestamp,
        ),
      );
    }
    return outbox;
  }

  int albumRows() =>
      cloud.rows.values.where((row) => row.$1 is CloudAlbumRecord).length;

  test('a failed upload stays pending and the retry sends it once', () async {
    final outbox = outboxWith(['album_1']);
    cloud.failBefore.add('insert:album_1');

    final first = await processor(outbox).pushPendingIsolated('user_1');
    expect(first.isComplete, isFalse);
    expect(outbox.pending, hasLength(1), reason: 'the change is kept');
    expect(albumRows(), 0);

    final retry = await processor(outbox).pushPendingIsolated('user_1');
    expect(retry.isComplete, isTrue);
    expect(outbox.pending, isEmpty);
    expect(albumRows(), 1);
    expect(cloud.rows.values.firstWhere((r) => r.$1.id == 'album_1').$2, 1);
  });

  test('an upload the cloud accepted before the timeout is recognised, '
      'not duplicated or turned into a conflict', () async {
    final outbox = outboxWith(['album_1']);
    cloud.loseResponse.add('insert:album_1');

    final first = await processor(outbox).pushPendingIsolated('user_1');
    expect(first.isComplete, isFalse);
    expect(outbox.pending, hasLength(1));
    expect(albumRows(), 1, reason: 'the write did reach the cloud');

    final retry = await processor(outbox).pushPendingIsolated('user_1');
    expect(retry.isComplete, isTrue);
    expect(outbox.pending, isEmpty);
    expect(albumRows(), 1, reason: 'no duplicate row');

    final revision = await baselines.getRevision(
      userId: 'user_1',
      entityType: CloudDataEntity.album,
      entityId: 'album_1',
    );
    expect(revision, 1, reason: 'the existing row is adopted, not rewritten');
  });

  test('an update accepted before the timeout is adopted on retry', () async {
    final outbox = outboxWith(['album_1']);
    await processor(outbox).pushPendingIsolated('user_1');

    albums.values['album_1'] = fx.album(timestamp).copyWith(title: 'Renamed');
    outbox.pending.add(
      fx.outbox(
        id: 'outbox_rename',
        type: CloudDataEntity.album,
        entityId: 'album_1',
        timestamp: timestamp,
      ),
    );
    cloud.loseResponse.add('update:album_1@1');

    expect(
      (await processor(outbox).pushPendingIsolated('user_1')).isComplete,
      isFalse,
    );
    expect(
      (await processor(outbox).pushPendingIsolated('user_1')).isComplete,
      isTrue,
    );

    final row = cloud.rows.values.firstWhere((r) => r.$1.id == 'album_1');
    expect((row.$1 as CloudAlbumRecord).title, 'Renamed');
    expect(row.$2, 2, reason: 'applied exactly once');
    expect(outbox.pending, isEmpty);
  });

  test('a partly failed batch keeps only the failed change pending', () async {
    albums.values['album_2'] = secondAlbum();
    final outbox = outboxWith(['album_1', 'album_2']);
    cloud.failBefore.add('insert:album_2');

    final report = await processor(outbox).pushPendingIsolated('user_1');
    expect(report.isComplete, isFalse);
    expect(outbox.pending.map((e) => e.entityId), ['album_2']);

    cloud.attempts.clear();
    await processor(outbox).pushPendingIsolated('user_1');

    expect(cloud.attempts.where((a) => a.contains('album_1')), isEmpty);
    expect(outbox.pending, isEmpty);
    expect(albumRows(), 2);
  });

  group('after an app restart', () {
    late Directory root;

    setUp(() async {
      sqfliteFfiInit();
      root = await Directory.systemTemp.createTemp('sonus_outbox_restart_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    SqliteLocalSyncRepository outboxOn(AppDatabase database, Database db) {
      var next = 0;
      return SqliteLocalSyncRepository(
        dao: LocalSyncDao(db),
        generateId: () => 'outbox_${next++}',
        now: () => timestamp,
      );
    }

    test('pending changes survive and are sent once', () async {
      final file = path.join(root.path, 'sonus.db');

      // First launch: a change is recorded, then the upload times out.
      var database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: file,
      );
      var outbox = outboxOn(database, await database.database);
      await outbox.recordUpsert(
        userId: 'user_1',
        entityType: CloudDataEntity.album,
        entityId: 'album_1',
      );
      cloud.failBefore.add('insert:album_1');
      await processor(outbox).pushPendingIsolated('user_1');
      expect(await outbox.getPending('user_1'), hasLength(1));
      await database.close();

      // Next launch: the change is still there and syncs.
      database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: file,
      );
      addTearDown(database.close);
      outbox = outboxOn(database, await database.database);
      expect(await outbox.getPending('user_1'), hasLength(1));

      final report = await processor(outbox).pushPendingIsolated('user_1');

      expect(report.isComplete, isTrue);
      expect(await outbox.getPending('user_1'), isEmpty);
      expect(albumRows(), 1);
    });
  });
}
