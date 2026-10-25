// Data-1: screens held their own copies of library and listening data and
// only reloaded on pull-to-refresh. Committed changes now announce
// themselves; screens reload once per burst.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  group('LibraryChangeRefresher', () {
    const settle = Duration(milliseconds: 40);
    Future<void> wait(int ms) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    test('a burst of changes reloads once, after it settles', () async {
      final signal = LibraryChangeSignal();
      var reloads = 0;
      final refresher = LibraryChangeRefresher(
        signal: signal,
        kinds: {LibraryChangeKind.libraryEdited},
        onChange: () => reloads++,
        settle: settle,
      );
      addTearDown(refresher.dispose);

      for (var i = 0; i < 5; i++) {
        signal.notify(LibraryChangeKind.libraryEdited);
        await wait(5);
      }
      expect(reloads, 0);

      await wait(120);
      expect(reloads, 1);
    });

    test('ignores kinds it was not asked about', () async {
      final signal = LibraryChangeSignal();
      var reloads = 0;
      final refresher = LibraryChangeRefresher(
        signal: signal,
        kinds: {LibraryChangeKind.listeningRecorded},
        onChange: () => reloads++,
        settle: settle,
      );
      addTearDown(refresher.dispose);

      signal.notify(LibraryChangeKind.importCompleted);
      await wait(120);

      expect(reloads, 0);
    });

    test('nothing runs after dispose', () async {
      final signal = LibraryChangeSignal();
      var reloads = 0;
      final refresher = LibraryChangeRefresher(
        signal: signal,
        kinds: {LibraryChangeKind.libraryEdited},
        onChange: () => reloads++,
        settle: settle,
      );

      signal.notify(LibraryChangeKind.libraryEdited);
      refresher.dispose();
      await wait(120);
      signal.notify(LibraryChangeKind.libraryEdited);
      await wait(120);

      expect(reloads, 0);
    });
  });

  group('library mutations', () {
    sqfliteFfiInit();

    late AppDatabase appDatabase;

    setUp(() {
      appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
    });

    tearDown(() => appDatabase.close());

    test('announce themselves once committed', () async {
      final signal = LibraryChangeSignal();
      final seen = <LibraryChangeKind>[];
      final subscription = signal.changes.listen(seen.add);
      addTearDown(subscription.cancel);

      await SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        changes: signal,
      ).run((context) async => null);

      expect(seen, [LibraryChangeKind.libraryEdited]);
    });

    test('a failed mutation announces nothing', () async {
      final signal = LibraryChangeSignal();
      final seen = <LibraryChangeKind>[];
      final subscription = signal.changes.listen(seen.add);
      addTearDown(subscription.cancel);

      await expectLater(
        SyncMutationTransactionRunner(
          appDatabase: appDatabase,
          changes: signal,
        ).run((context) async => throw StateError('rolled back')),
        throwsStateError,
      );

      expect(seen, isEmpty);
    });
  });
}
