import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/artist_dependency_journal_entry.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  final timestamp = DateTime.utc(2026, 10, 20, 12);

  ArtistDependencyJournalEntry request({
    String userId = 'user-1',
    String artistId = 'artist-1',
    String requestId = 'dependency-1',
  }) {
    return ArtistDependencyJournalEntry(
      userId: userId,
      artistId: artistId,
      requestId: requestId,
      createdAt: timestamp,
      requestJson: jsonEncode({
        'function_name': 'create_artist_with_receipt',
        'parameters': {
          'p_artist_id': artistId,
          'p_outbox_id': requestId,
          'p_mutation_revision': 1,
          'p_name': 'Example Artist',
          'p_canonical_name': 'example artist',
          'p_header_artwork_id': null,
          'p_top_artists_artwork_id': null,
          'p_metadata_field_states': null,
          'p_created_at': timestamp.toIso8601String(),
          'p_updated_at': timestamp.toIso8601String(),
        },
      }),
    );
  }

  Future<void> withRunner(
    Future<void> Function(SyncMutationTransactionRunner runner) action,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_dependency_tx_',
    );

    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/sonus.db',
    );

    try {
      await app.database;

      await action(SyncMutationTransactionRunner(appDatabase: app));
    } finally {
      await app.close();
      await directory.delete(recursive: true);
    }
  }

  test('prepared dependency commits through mutation runner', () async {
    await withRunner((runner) async {
      final original = request();

      await runner.run<void>((context) async {
        await context.artistDependencyJournalRepository!.prepare(original);
      });

      final recovered = await runner.run((context) {
        return context.artistDependencyJournalRepository!.findUnresolved(
          userId: 'user-1',
          artistId: 'artist-1',
        );
      });

      expect(recovered, isNotNull);
      expect(recovered!.sameSnapshot(original), isTrue);
    });
  });

  test('failed preparation transaction leaves no request', () async {
    await withRunner((runner) async {
      await expectLater(
        runner.run<void>((context) async {
          await context.artistDependencyJournalRepository!.prepare(request());
          throw StateError('Simulated local preparation failure.');
        }),
        throwsStateError,
      );

      final entries = await runner.run((context) {
        return context.artistDependencyJournalRepository!.findUnresolvedForUser(
          'user-1',
        );
      });

      expect(entries, isEmpty);
    });
  });

  test('verified receipt finalization is atomic', () async {
    await withRunner((runner) async {
      final original = request();

      await runner.run<void>((context) {
        return context.artistDependencyJournalRepository!.prepare(original);
      });

      // Simulate failure after attempting both local completion actions.
      await expectLater(
        runner.run<void>((context) async {
          await context.cloudRevisionBaselineRepository!.saveObservedRevision(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist-1',
            serverRevision: 1,
          );

          final removed = await context.artistDependencyJournalRepository!
              .removeVerified(original);

          expect(removed, 1);

          throw StateError('Simulated finalization interruption.');
        }),
        throwsStateError,
      );

      await runner.run<void>((context) async {
        final revision = await context.cloudRevisionBaselineRepository!
            .getRevision(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist-1',
            );

        final pending = await context.artistDependencyJournalRepository!
            .findUnresolved(userId: 'user-1', artistId: 'artist-1');

        expect(revision, isNull);
        expect(pending, isNotNull);
        expect(pending!.sameSnapshot(original), isTrue);
      });

      // A verified server receipt permits finalization on retry.
      await runner.run<void>((context) async {
        await context.cloudRevisionBaselineRepository!.saveObservedRevision(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
          serverRevision: 1,
        );

        final removed = await context.artistDependencyJournalRepository!
            .removeVerified(original);

        if (removed != 1) {
          throw StateError('Verified request changed during finalization.');
        }
      });

      await runner.run<void>((context) async {
        final revision = await context.cloudRevisionBaselineRepository!
            .getRevision(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist-1',
            );

        final pending = await context.artistDependencyJournalRepository!
            .findUnresolved(userId: 'user-1', artistId: 'artist-1');

        expect(revision, 1);
        expect(pending, isNull);
      });
    });
  });

  test('finalizing one account preserves another account request', () async {
    await withRunner((runner) async {
      final first = request(userId: 'user-1', requestId: 'dependency-1');

      final second = request(userId: 'user-2', requestId: 'dependency-2');

      await runner.run<void>((context) async {
        final repository = context.artistDependencyJournalRepository!;
        await repository.prepare(first);
        await repository.prepare(second);
      });

      await runner.run<void>((context) async {
        await context.cloudRevisionBaselineRepository!.saveObservedRevision(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
          serverRevision: 1,
        );

        expect(
          await context.artistDependencyJournalRepository!.removeVerified(
            first,
          ),
          1,
        );
      });

      await runner.run<void>((context) async {
        final repository = context.artistDependencyJournalRepository!;

        expect(await repository.findUnresolvedForUser('user-1'), isEmpty);

        final other = await repository.findUnresolved(
          userId: 'user-2',
          artistId: 'artist-1',
        );

        expect(other, isNotNull);
        expect(other!.sameSnapshot(second), isTrue);

        expect(
          await context.cloudRevisionBaselineRepository!.getRevision(
            userId: 'user-2',
            entityType: CloudDataEntity.artist,
            entityId: 'artist-1',
          ),
          isNull,
        );
      });
    });
  });
}
