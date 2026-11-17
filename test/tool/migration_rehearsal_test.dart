// Migration rehearsal (App Update 1.3): upgrades a COPY of a real device
// database with the app's own AppDatabase, exactly as the phone would on
// first launch, and proves that no stored content changed.
//
// Runs only with --dart-define=SONUS_REHEARSAL_DB=<a v47 database file>.
// The file given is never opened: it is hashed, copied, hashed again. Every
// check runs on the copy, in a fresh temp folder. A JSON report is written
// next to the copy, and to SONUS_REHEARSAL_OUT when given.
//
// Checks: source unchanged; the copy's version, integrity and foreign keys
// before and after; every table that existed before keeps its row count
// and the exact content of every column it had (hashed row by row in
// rowid order); tables and columns the migration adds are listed, and the
// lyrics provenance columns are all null on migrated rows.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';

const String _source = String.fromEnvironment('SONUS_REHEARSAL_DB');
const String _out = String.fromEnvironment('SONUS_REHEARSAL_OUT');

String _fileHash(File file) =>
    sha256.convert(file.readAsBytesSync()).toString();

/// Blobs as base64 so they hash by content.
Object? _plain(Object? value) =>
    value is List<int> ? base64Encode(value) : value;

typedef _Table = ({List<String> columns, int rows, String hash});

/// Every table's columns, row count and a hash of its rows (the given
/// columns only, rowid order; tables without rowid in primary-key order).
Future<Map<String, _Table>> _snapshot(
  Database db, {
  Map<String, List<String>>? onlyColumns,
}) async {
  final tables = [
    for (final row in await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      (name: row['name']! as String, sql: (row['sql'] as String?) ?? ''),
  ];
  final result = <String, _Table>{};
  for (final table in tables) {
    final info = await db.rawQuery('PRAGMA table_info("${table.name}")');
    final all = [for (final c in info) c['name']! as String];
    final columns = onlyColumns?[table.name] ?? all;
    final withoutRowid = table.sql.toUpperCase().contains('WITHOUT ROWID');
    final keys = [
      for (final c in info)
        if ((c['pk']! as int) > 0) c['name']! as String,
    ];
    final order = withoutRowid
        ? (keys.isEmpty ? columns : keys).map((c) => '"$c"').join(', ')
        : 'rowid';
    final rows = await db.rawQuery(
      'SELECT ${columns.map((c) => '"$c"').join(', ')} '
      'FROM "${table.name}" ORDER BY $order',
    );
    final bytes = BytesBuilder(copy: false);
    for (final row in rows) {
      bytes.add(
        utf8.encode(jsonEncode([for (final c in columns) _plain(row[c])])),
      );
      bytes.addByte(10);
    }
    result[table.name] = (
      columns: columns,
      rows: rows.length,
      hash: sha256.convert(bytes.takeBytes()).toString(),
    );
  }
  return result;
}

Future<Map<String, Object?>> _health(Database db) async => {
  'user_version': (await db.rawQuery(
    'PRAGMA user_version',
  )).single.values.single,
  'integrity_check': (await db.rawQuery(
    'PRAGMA integrity_check',
  )).map((r) => r.values.single).toList(),
  'foreign_key_violations': (await db.rawQuery(
    'PRAGMA foreign_key_check',
  )).length,
};

void main() {
  test(
    'a v47 device database upgrades to the current schema without '
    'changing stored content',
    skip: _source.isEmpty ? 'set --dart-define=SONUS_REHEARSAL_DB' : null,
    () async {
      sqfliteFfiInit();
      final source = File(_source);
      expect(source.existsSync(), isTrue, reason: _source);
      final sourceHashBefore = _fileHash(source);

      final dir = Directory.systemTemp.createTempSync('sonus_rehearsal_');
      final copy = File('${dir.path}${Platform.pathSeparator}sonus_next.db');
      source.copySync(copy.path);
      expect(_fileHash(copy), sourceHashBefore);

      // Before: the copy as the device has it.
      final before = await databaseFactoryFfi.openDatabase(copy.path);
      final healthBefore = await _health(before);
      final snapshotBefore = await _snapshot(before);
      await before.close();

      // Upgrade with the app's own code path.
      final app = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: copy.path,
      );
      await app.database;
      await app.close();

      final after = await databaseFactoryFfi.openDatabase(copy.path);
      final healthAfter = await _health(after);
      final unchanged = await _snapshot(
        after,
        onlyColumns: {
          for (final MapEntry(:key, :value) in snapshotBefore.entries)
            key: value.columns,
        },
      );
      final full = await _snapshot(after);
      final lyricsProvenanceSet = (await after.rawQuery(
        'SELECT COUNT(*) AS n FROM track_lyrics WHERE '
        'plain_source IS NOT NULL OR synced_source IS NOT NULL OR '
        'offset_ms IS NOT NULL OR provider IS NOT NULL',
      )).single['n'];
      await after.close();

      final changedTables = [
        for (final MapEntry(:key, :value) in snapshotBefore.entries)
          if (unchanged[key] == null ||
              unchanged[key]!.rows != value.rows ||
              unchanged[key]!.hash != value.hash)
            key,
      ];
      final addedTables = [
        for (final name in full.keys)
          if (!snapshotBefore.containsKey(name)) name,
      ];
      final addedColumns = {
        for (final MapEntry(:key, :value) in full.entries)
          if (snapshotBefore[key] case final old?)
            if (value.columns.length != old.columns.length)
              key: [
                for (final c in value.columns)
                  if (!old.columns.contains(c)) c,
              ],
      };

      final report = {
        'source': _source,
        'source_sha256': sourceHashBefore,
        'source_unchanged': _fileHash(source) == sourceHashBefore,
        'app_schema_version': AppDatabase.databaseVersion,
        'before': healthBefore,
        'after': healthAfter,
        'tables_before': snapshotBefore.length,
        'rows_before': snapshotBefore.values.fold<int>(0, (n, t) => n + t.rows),
        'changed_tables': changedTables,
        'added_tables': addedTables,
        'added_columns': addedColumns,
        'track_lyrics_rows_with_provenance': lyricsProvenanceSet,
        'row_counts': {
          for (final MapEntry(:key, :value) in snapshotBefore.entries)
            key: [value.rows, unchanged[key]?.rows],
        },
      };
      final json = const JsonEncoder.withIndent('  ').convert(report);
      File(
        '${dir.path}${Platform.pathSeparator}rehearsal.json',
      ).writeAsStringSync(json);
      if (_out.isNotEmpty) File(_out).writeAsStringSync(json);

      expect(report['source_unchanged'], isTrue);
      expect(healthAfter['user_version'], AppDatabase.databaseVersion);
      expect(healthAfter['integrity_check'], ['ok']);
      expect(healthAfter['foreign_key_violations'], 0);
      expect(changedTables, isEmpty, reason: json);
      expect(lyricsProvenanceSet, 0);
    },
  );
}
