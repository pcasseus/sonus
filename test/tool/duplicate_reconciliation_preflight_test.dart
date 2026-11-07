// App Update 1.2: a read-only preflight for a controlled duplicate
// reconciliation (for example the Zendaya K2 merge) on a COPY of a real
// database. Skipped unless a copy is named:
//
//   flutter test test/tool/duplicate_reconciliation_preflight_test.dart \
//     --dart-define=SONUS_PREFLIGHT_DB=C:/path/to/copy.db
//
// The copy is opened read-only and its SHA-256 is checked before and after,
// so nothing can be written. Prints the exact plan and every precondition.
// Never point it at a live database.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/duplicate_album_reconciliation_service.dart';

const String _copy = String.fromEnvironment('SONUS_PREFLIGHT_DB');

void main() {
  sqfliteFfiInit();

  test(
    'duplicate reconciliation preflight (read-only)',
    skip: _copy.isEmpty ? 'Set SONUS_PREFLIGHT_DB to a database copy.' : null,
    () async {
      final file = File(_copy);
      final before = sha256.convert(await file.readAsBytes()).toString();
      final db = await databaseFactoryFfi.openDatabase(
        _copy,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final out = StringBuffer()
        ..writeln('copy: $_copy')
        ..writeln('sha256: $before')
        ..writeln(
          'user_version: '
          '${(await db.rawQuery('PRAGMA user_version')).single.values.single}',
        )
        ..writeln(
          'integrity: '
          '${(await db.rawQuery('PRAGMA integrity_check')).single.values.single}',
        );

      final plan = await DuplicateAlbumReconciliationService(
        appDatabase: AppDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        ),
      ).plan(executor: db);

      Future<int> count(String sql, List<Object?> args) async =>
          (await db.rawQuery(sql, args)).single.values.single! as int;

      for (final m in plan.merges) {
        out.writeln(
          'MERGE "${m.title}": keep ${m.keptAlbumId} <- ${m.duplicateAlbumId}',
        );
        out.writeln(
          '  songs ${m.songPairs.length}, editions '
          '${m.editionPairs.map((e) => '${e.duplicateEditionId}->'
              '${e.keptEditionId}').join(', ')}',
        );
        out.writeln(
          '  plays moved ${m.movedPlayCount}, playable files moved '
          '${m.movedLiveFileCount}',
        );
        final dupSongs = [for (final p in m.songPairs) p.duplicateSongId];
        final marks = List.filled(dupSongs.length, '?').join(', ');
        out.writeln(
          '  duplicate Moments: ${await count('SELECT COUNT(*) FROM ${DatabaseTables.chartMomentEvents} '
          'WHERE entity_id IN ($marks, ?) OR related_entity_id IN ($marks, ?)', [...dupSongs, m.duplicateAlbumId, ...dupSongs, m.duplicateAlbumId])}, duplicate chart rows: ${await count('SELECT COUNT(*) FROM ${DatabaseTables.chartEntries} '
          'WHERE entity_id IN ($marks, ?)', [...dupSongs, m.duplicateAlbumId])}, pending cloud writes: ${await count('SELECT COUNT(*) FROM ${DatabaseTables.syncOutbox} '
          'WHERE entity_id IN ($marks, ?)', [...dupSongs, m.duplicateAlbumId])}',
        );
        for (final p in m.songPairs) {
          out.writeln('  PAIR ${p.duplicateSongId} -> ${p.keptSongId}');
        }
      }
      for (final r in plan.reviews) {
        out.writeln('REVIEW "${r.title}" ${r.albumIds} ${r.reason.name}');
      }
      await db.close();

      final after = sha256.convert(await file.readAsBytes()).toString();
      out.writeln('unchanged: ${after == before}');
      // ignore: avoid_print
      print(out);
      expect(after, before, reason: 'the copy must not change');
    },
  );
}
