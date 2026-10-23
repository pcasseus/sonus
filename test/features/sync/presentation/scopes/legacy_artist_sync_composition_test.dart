import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_write_coordinator.dart';
import 'package:sonus_next/features/sync/data/contracts/supabase_sync_contract.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_artist_create_gateway.dart';
import 'package:sonus_next/features/sync/data/mappers/supabase_cloud_record_mapper.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';
import 'package:sonus_next/features/sync/presentation/scopes/legacy_artist_sync_composition.dart';

// SN-47B1: the exact artist composition SyncScope uses, driven through
// the real Supabase gateways against a local loopback server. Proves the
// production route verifies a fetched cloud artist before adopting a
// rejected creation. No real Supabase project is contacted.
void main() {
  sqfliteFfiInit();

  final now = DateTime.utc(2026, 10, 22, 9, 30, 15, 123, 456);

  late HttpServer server;
  late List<_Captured> requests;
  late Object? createResponse;
  late List<Object?> artistRows;
  late SupabaseClient client;
  late AppDatabase database;
  late SyncMutationTransactionRunner runner;
  late SqliteCloudRevisionBaselineRepository baselines;
  late LegacyArtistSyncComposition composition;

  setUp(() async {
    requests = [];
    createResponse = null;
    artistRows = [];

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      requests.add(_Captured(method: request.method, uri: request.uri));

      final Object? response = switch (request.uri.path) {
        '/rest/v1/rpc/${SupabaseArtistCreateGateway.rpcName}' => createResponse,
        '/rest/v1/artists' when request.method == 'GET' => artistRows,
        _ => throw StateError('Unexpected request ${request.uri} $body'),
      };

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(response));
      await request.response.close();
    });

    client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    runner = SyncMutationTransactionRunner(
      appDatabase: database,
      generateId: () => 'artist-mutation-1',
      now: () => now,
    );
    baselines = SqliteCloudRevisionBaselineRepository(
      dao: CloudRevisionBaselineDao(await database.database),
    );

    composition = LegacyArtistSyncComposition(
      client: client,
      baselineRepository: baselines,
      mutationRunner: runner,
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
    await database.close();
  });

  // Includes provenance and sub-second timestamps so equivalence is
  // proven across the real wire encoding.
  CloudArtistRecord localArtist({String name = 'Wire Artist'}) {
    return CloudArtistRecord(
      id: 'artist-1',
      userId: 'user-1',
      name: name,
      canonicalName: 'wire artist',
      createdAt: now,
      updatedAt: now,
      headerArtworkId: 'artwork-1',
      metadataFieldStates: [
        CloudMetadataFieldState(
          fieldName: 'name',
          authority: 'manual',
          source: 'user',
          updatedAt: now,
          sourceReference: 'edit-1',
        ),
      ],
    );
  }

  Map<String, dynamic> cloudRow(CloudArtistRecord record, int revision) {
    return {
      ...SupabaseCloudRecordMapper.toRow(record),
      SupabaseSyncContract.serverUpdatedAtColumn: now.toIso8601String(),
      SupabaseSyncContract.serverRevisionColumn: revision,
    };
  }

  void rejectCreationAt(int revision) {
    createResponse = [
      {'outcome': 'conflict', 'server_revision': revision},
    ];
  }

  Future<List<SyncOutboxEntry>> pending() async {
    return LocalSyncDao(await database.database).findPending('user-1');
  }

  Future<SyncOutboxEntry> enqueue() async {
    await runner.run<void>((context) async {
      await context.localSyncRepository.recordUpsert(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );
    });

    return (await pending()).single;
  }

  Future<int?> revision() {
    return baselines.getRevision(
      userId: 'user-1',
      entityType: CloudDataEntity.artist,
      entityId: 'artist-1',
    );
  }

  void expectOwnerScopedArtistFetch() {
    final fetch = requests.singleWhere(
      (request) =>
          request.method == 'GET' && request.uri.path == '/rest/v1/artists',
    );

    expect(fetch.uri.queryParameters['user_id'], 'eq.user-1');
    expect(fetch.uri.queryParameters['id'], 'eq.artist-1');
  }

  group('write coordinator', () {
    test('adopts a verified lost creation and acknowledges it', () async {
      final entry = await enqueue();
      rejectCreationAt(1);
      artistRows = [cloudRow(localArtist(), 1)];

      await composition.writeCoordinator.push(
        userId: 'user-1',
        entry: entry,
        artist: localArtist(),
      );

      expect(
        requests.first.uri.path,
        endsWith(SupabaseArtistCreateGateway.rpcName),
      );
      expectOwnerScopedArtistFetch();
      expect(await revision(), 1);
      expect(await pending(), isEmpty);
    });

    test('rejects a non-equivalent cloud artist', () async {
      final entry = await enqueue();
      rejectCreationAt(2);
      artistRows = [cloudRow(localArtist(name: 'Renamed Elsewhere'), 2)];

      await expectLater(
        composition.writeCoordinator.push(
          userId: 'user-1',
          entry: entry,
          artist: localArtist(),
        ),
        throwsA(isA<OutboundArtistWriteConflict>()),
      );

      expectOwnerScopedArtistFetch();
      expect(await revision(), isNull);
      expect(await pending(), hasLength(1));
    });

    test('rejects a tombstoned cloud artist', () async {
      final entry = await enqueue();
      rejectCreationAt(2);
      artistRows = [
        {
          ...cloudRow(localArtist(), 2),
          SupabaseSyncContract.deletedAtColumn: now.toIso8601String(),
        },
      ];

      await expectLater(
        composition.writeCoordinator.push(
          userId: 'user-1',
          entry: entry,
          artist: localArtist(),
        ),
        throwsA(isA<OutboundArtistWriteConflict>()),
      );

      expect(await revision(), isNull);
      expect(await pending(), hasLength(1));
    });
  });

  group('dependency ensurer', () {
    test('adopts a verified lost creation without acknowledging', () async {
      await enqueue();
      rejectCreationAt(1);
      artistRows = [cloudRow(localArtist(), 1)];

      await composition.dependencyEnsurer.ensure(
        userId: 'user-1',
        artist: localArtist(),
      );

      expectOwnerScopedArtistFetch();
      expect(await revision(), 1);
      expect(await pending(), hasLength(1));
    });

    test('rejects when no owned cloud artist is found', () async {
      rejectCreationAt(1);
      artistRows = [];

      await expectLater(
        composition.dependencyEnsurer.ensure(
          userId: 'user-1',
          artist: localArtist(),
        ),
        throwsA(isA<OutboundArtistWriteConflict>()),
      );

      expectOwnerScopedArtistFetch();
      expect(await revision(), isNull);
    });
  });
}

class _Captured {
  const _Captured({required this.method, required this.uri});

  final String method;
  final Uri uri;
}
