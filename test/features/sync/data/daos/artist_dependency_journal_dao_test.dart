import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/data/daos/artist_dependency_journal_dao.dart';
import 'package:sonus_next/features/sync/domain/models/artist_dependency_journal_entry.dart';

void main() {
  sqfliteFfiInit();

  final now = DateTime.utc(2026, 10, 20, 12);

  ArtistDependencyJournalEntry entry({
    String userId = 'user_1',
    String artistId = 'artist_1',
    String requestId = 'dependency_1',
    int revision = 1,
    DateTime? createdAt,
    String? requestJson,
  }) {
    return ArtistDependencyJournalEntry(
      userId: userId,
      artistId: artistId,
      requestId: requestId,
      mutationRevision: revision,
      createdAt: createdAt ?? now,
      requestJson:
          requestJson ??
          jsonEncode({
            'function_name': 'create_artist_with_receipt',
            'parameters': {
              'p_artist_id': artistId,
              'p_outbox_id': requestId,
              'p_mutation_revision': revision,
              'p_name': 'Example Artist',
              'p_canonical_name': 'example artist',
              'p_header_artwork_id': null,
              'p_top_artists_artwork_id': null,
              'p_metadata_field_states': null,
              'p_created_at': now.toIso8601String(),
              'p_updated_at': now.toIso8601String(),
            },
          }),
    );
  }

  test('valid request round-trips through a database row', () {
    final original = entry();
    final restored = ArtistDependencyJournalEntry.fromRow(original.toRow());

    expect(restored.sameSnapshot(original), isTrue);
    expect(restored.requestId, 'dependency_1');
    expect(restored.mutationRevision, 1);
  });

  test('rejects invalid identity and RPC envelopes', () {
    expect(() => entry(userId: ' '), throwsArgumentError);

    expect(() => entry(revision: 2), throwsArgumentError);

    expect(() => entry(createdAt: now.toLocal()), throwsArgumentError);

    expect(() => entry(requestJson: 'not json'), throwsArgumentError);

    expect(
      () => entry(
        requestJson: jsonEncode({
          'function_name': 'create_artist_if_absent',
          'parameters': {},
        }),
      ),
      throwsArgumentError,
    );

    expect(
      () => entry(
        requestJson: jsonEncode({
          'function_name': 'create_artist_with_receipt',
          'parameters': {'p_artist_id': 'different_artist'},
        }),
      ),
      throwsArgumentError,
    );
  });

  test('identical preparation is idempotent', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final dao = ArtistDependencyJournalDao(await app.database);
      final prepared = entry();

      await dao.prepare(prepared);
      await dao.prepare(prepared);

      final unresolved = await dao.findUnresolved(
        userId: 'user_1',
        artistId: 'artist_1',
      );

      expect(unresolved, isNotNull);
      expect(unresolved!.sameSnapshot(prepared), isTrue);
      expect(await dao.findUnresolvedForUser('user_1'), hasLength(1));
    } finally {
      await app.close();
    }
  });

  test('conflicting preparation cannot replace pending work', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final dao = ArtistDependencyJournalDao(await app.database);
      final original = entry();

      await dao.prepare(original);

      await expectLater(
        dao.prepare(entry(requestId: 'dependency_2')),
        throwsStateError,
      );

      final stored = await dao.findUnresolved(
        userId: 'user_1',
        artistId: 'artist_1',
      );

      expect(stored!.sameSnapshot(original), isTrue);
    } finally {
      await app.close();
    }
  });

  test('different accounts retain independent requests', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final dao = ArtistDependencyJournalDao(await app.database);

      await dao.prepare(entry(userId: 'user_1'));
      await dao.prepare(entry(userId: 'user_2'));

      expect(await dao.findUnresolvedForUser('user_1'), hasLength(1));
      expect(await dao.findUnresolvedForUser('user_2'), hasLength(1));
      expect(await dao.findUnresolvedForUser('user_3'), isEmpty);
    } finally {
      await app.close();
    }
  });

  test('conditional removal requires the exact stored snapshot', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final dao = ArtistDependencyJournalDao(await app.database);
      final original = entry();

      await dao.prepare(original);

      final altered = entry(createdAt: now.add(const Duration(seconds: 1)));

      expect(await dao.removeVerified(altered), 0);
      expect(await dao.findUnresolvedForUser('user_1'), hasLength(1));

      expect(await dao.removeVerified(original), 1);
      expect(await dao.findUnresolvedForUser('user_1'), isEmpty);
    } finally {
      await app.close();
    }
  });

  test('prepared request survives database restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_dependency_dao_',
    );
    final location = '${directory.path}/sonus.db';
    final original = entry();

    final first = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: location,
    );

    try {
      final dao = ArtistDependencyJournalDao(await first.database);
      await dao.prepare(original);
    } finally {
      await first.close();
    }

    final reopened = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: location,
    );

    try {
      final dao = ArtistDependencyJournalDao(await reopened.database);

      final recovered = await dao.findUnresolved(
        userId: 'user_1',
        artistId: 'artist_1',
      );

      expect(recovered, isNotNull);
      expect(recovered!.sameSnapshot(original), isTrue);
    } finally {
      await reopened.close();
      await directory.delete(recursive: true);
    }
  });
}
