import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/data/daos/artist_write_journal_dao.dart';
import 'package:sonus_next/features/sync/domain/models/artist_write_journal_entry.dart';

void main() {
  sqfliteFfiInit();

  final timestamp = DateTime.utc(2026, 10, 18);

  ArtistWriteJournalEntry entry({
    String userId = 'user_1',
    String artistId = 'artist_1',
    String outboxId = 'outbox_1',
    int mutationRevision = 1,
    String requestJson = '{"p_artist_id":"artist_1"}',
  }) {
    return ArtistWriteJournalEntry(
      userId: userId,
      artistId: artistId,
      outboxId: outboxId,
      mutationRevision: mutationRevision,
      operation: ArtistWriteJournalOperation.update,
      expectedServerRevision: 7,
      requestJson: requestJson,
      createdAt: timestamp,
    );
  }

  test('identical request can be prepared repeatedly', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final dao = ArtistWriteJournalDao(await app.database);
      final original = entry();

      await dao.prepare(original);
      await dao.prepare(original);

      final pending = await dao.findUnresolvedForUser('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.sameSnapshot(original), isTrue);
    } finally {
      await app.close();
    }
  });

  test('different request cannot replace unresolved artist write', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final dao = ArtistWriteJournalDao(await app.database);
      final original = entry();

      await dao.prepare(original);

      await expectLater(
        dao.prepare(
          entry(
            mutationRevision: 2,
            requestJson: '{"p_artist_id":"artist_1","p_name":"New"}',
          ),
        ),
        throwsStateError,
      );

      final saved = await dao.findUnresolved(
        userId: 'user_1',
        artistId: 'artist_1',
      );

      expect(saved, isNotNull);
      expect(saved!.sameSnapshot(original), isTrue);
    } finally {
      await app.close();
    }
  });

  test('journal records remain isolated by user', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final dao = ArtistWriteJournalDao(await app.database);

      await dao.prepare(entry(userId: 'user_1'));
      await dao.prepare(entry(userId: 'user_2'));

      expect(await dao.findUnresolvedForUser('user_1'), hasLength(1));
      expect(await dao.findUnresolvedForUser('user_2'), hasLength(1));
      expect(await dao.findUnresolvedForUser('user_3'), isEmpty);
    } finally {
      await app.close();
    }
  });

  test('incorrect receipt cannot remove unresolved journal entry', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final dao = ArtistWriteJournalDao(await app.database);
      final original = entry();

      await dao.prepare(original);

      final wrongReceipt = entry(outboxId: 'different_outbox');

      expect(await dao.removeVerified(wrongReceipt), 0);

      expect(await dao.findUnresolvedForUser('user_1'), hasLength(1));

      expect(await dao.removeVerified(original), 1);
      expect(await dao.findUnresolvedForUser('user_1'), isEmpty);
    } finally {
      await app.close();
    }
  });

  test('different expected revision cannot remove journal entry', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final dao = ArtistWriteJournalDao(await app.database);
      final original = entry();

      await dao.prepare(original);

      final incorrect = ArtistWriteJournalEntry(
        userId: original.userId,
        artistId: original.artistId,
        outboxId: original.outboxId,
        mutationRevision: original.mutationRevision,
        operation: original.operation,
        expectedServerRevision: 8,
        requestJson: original.requestJson,
        createdAt: original.createdAt,
      );

      expect(await dao.removeVerified(incorrect), 0);
      expect(await dao.findUnresolvedForUser('user_1'), hasLength(1));

      expect(await dao.removeVerified(original), 1);
      expect(await dao.findUnresolvedForUser('user_1'), isEmpty);
    } finally {
      await app.close();
    }
  });

  test('different creation timestamp cannot remove journal entry', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final dao = ArtistWriteJournalDao(await app.database);
      final original = entry();

      await dao.prepare(original);

      final incorrect = ArtistWriteJournalEntry(
        userId: original.userId,
        artistId: original.artistId,
        outboxId: original.outboxId,
        mutationRevision: original.mutationRevision,
        operation: original.operation,
        expectedServerRevision: original.expectedServerRevision,
        requestJson: original.requestJson,
        createdAt: original.createdAt.add(const Duration(seconds: 1)),
      );

      expect(await dao.removeVerified(incorrect), 0);
      expect(await dao.findUnresolvedForUser('user_1'), hasLength(1));

      expect(await dao.removeVerified(original), 1);
      expect(await dao.findUnresolvedForUser('user_1'), isEmpty);
    } finally {
      await app.close();
    }
  });
  test('unresolved request survives database restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_artist_journal_dao_',
    );

    final path = '${directory.path}/sonus.db';
    final original = entry(
      requestJson: '{"p_artist_id":"artist_1","p_name":"Original"}',
    );

    final first = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
    );

    try {
      final dao = ArtistWriteJournalDao(await first.database);
      await dao.prepare(original);
    } finally {
      await first.close();
    }

    final second = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
    );

    try {
      final dao = ArtistWriteJournalDao(await second.database);

      final restored = await dao.findUnresolved(
        userId: original.userId,
        artistId: original.artistId,
      );

      expect(restored, isNotNull);
      expect(restored!.sameSnapshot(original), isTrue);

      await dao.prepare(original);

      expect(await dao.findUnresolvedForUser('user_1'), hasLength(1));
    } finally {
      await second.close();
      await directory.delete(recursive: true);
    }
  });
}
