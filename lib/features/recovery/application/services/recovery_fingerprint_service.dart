import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../../../core/database/schema/sync_schema.dart';
import '../models/recovery_sync_hold.dart';

/// Computes content digests of the local database and artwork files.
///
/// Digests cover every column of every row, in primary-key order, so two
/// equal digests mean equal content, not merely equal identities.
class RecoveryFingerprintService {
  const RecoveryFingerprintService();

  /// Suffix for digests that exclude device-local columns.
  static const portableSuffix = '#portable';

  static const _deviceLocalColumns = {
    DatabaseTables.artworkAssets: {'file_path', 'normalized_path'},
  };

  /// Tables whose content is represented in cloud records. Credits,
  /// edition tracks, and metadata states travel inside their parents.
  static const cloudRepresentedTables = [
    DatabaseTables.artworkAssets,
    DatabaseTables.artists,
    DatabaseTables.albums,
    DatabaseTables.albumEditions,
    DatabaseTables.songs,
    DatabaseTables.songArtistCredits,
    DatabaseTables.albumEditionTracks,
    DatabaseTables.metadataFieldStates,
  ];

  /// Tables holding account binding and synchronization progress.
  static const syncStateTables = [
    DatabaseTables.localAccountBinding,
    DatabaseTables.syncState,
    DatabaseTables.syncOutbox,
    SyncSchema.cloudRevisionBaselinesTable,
    SyncSchema.artistWriteJournalTable,
    SyncSchema.artistDependencyJournalTable,
    SyncSchema.inboundDeferredRecordsTable,
    SyncSchema.outboundConflictsTable,
    DatabaseTables.cloudArchiveState,
  ];

  /// Digest of a table with no rows.
  static final String emptyTableDigest = sha256.convert(const []).toString();

  /// Portable digest key for [table] used when comparing cloud content.
  static String cloudDigestKey(String table) =>
      _deviceLocalColumns.containsKey(table) ? '$table$portableSuffix' : table;

  Future<RecoveryFingerprint> capture(DatabaseExecutor executor) async {
    final tables = await executor.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );

    final digests = <String, String>{};

    for (final row in tables) {
      final table = row['name'] as String;
      final rows = await _orderedRows(executor, table);

      digests[table] = _digestRows(rows, const {});

      final excluded = _deviceLocalColumns[table];

      if (excluded != null) {
        digests['$table$portableSuffix'] = _digestRows(rows, excluded);
      }
    }

    return RecoveryFingerprint(
      tableDigests: digests,
      artworkContentDigest: await _artworkContentDigest(executor),
    );
  }

  Future<List<Map<String, Object?>>> _orderedRows(
    DatabaseExecutor executor,
    String table,
  ) async {
    // Table names come from sqlite_master of this database.
    final columns = await executor.rawQuery('PRAGMA table_info("$table")');
    final keys =
        [
          for (final column in columns)
            if ((column['pk'] as int) > 0) column,
        ]..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));

    final order = keys.isEmpty
        ? 'rowid'
        : keys.map((column) => '"${column['name']}"').join(', ');

    return executor.rawQuery('SELECT * FROM "$table" ORDER BY $order');
  }

  String _digestRows(List<Map<String, Object?>> rows, Set<String> excluded) {
    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);

    for (final row in rows) {
      final keys = row.keys.where((key) => !excluded.contains(key)).toList()
        ..sort();

      input.add(
        utf8.encode(
          '${jsonEncode([for (final key in keys) [key, row[key]]])}\n',
        ),
      );
    }

    input.close();
    return output.events.single.toString();
  }

  Future<String> _artworkContentDigest(DatabaseExecutor executor) async {
    final rows = await executor.query(
      DatabaseTables.artworkAssets,
      columns: ['id', 'file_path'],
      orderBy: 'id',
    );

    final entries = <List<Object>>[];

    for (final row in rows) {
      final file = File(row['file_path'] as String);
      final type = await FileSystemEntity.type(file.path, followLinks: false);

      entries.add([
        row['id'] as String,
        type == FileSystemEntityType.file
            ? (await sha256.bind(file.openRead()).first).toString()
            : 'missing',
      ]);
    }

    return sha256.convert(utf8.encode(jsonEncode(entries))).toString();
  }
}

class _DigestSink implements Sink<Digest> {
  final events = <Digest>[];

  @override
  void add(Digest event) => events.add(event);

  @override
  void close() {}
}
