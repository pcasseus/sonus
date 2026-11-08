import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/deletion/merge_chain.dart';

export '../../domain/deletion/merge_chain.dart'
    show MergeChainException, MergeChains;

/// App Update 1.2: listening that belonged to a merged duplicate follows the
/// record that stayed, wherever it comes from: this device's history when a
/// merge arrives from another device, or a listening session downloaded
/// from the cloud archive after the merge.
class MergeHistoryRemap {
  MergeHistoryRemap._(this.chains);

  /// Every merge this device knows, each resolved to the end of its chain
  /// (A merged into B, later B into C, resolves A to C).
  final MergeChains chains;

  /// Every merge this device knows (its own and other devices'), oldest
  /// first, so a later merge of the same id wins deterministically.
  static Future<MergeHistoryRemap> load(DatabaseExecutor db) async {
    final maps = {
      for (final kind in MergeChains.kinds) kind: <String, String>{},
    };
    for (final row in await db.query(
      DatabaseTables.libraryDeletionJournal,
      columns: ['summary'],
      where: 'operation = ?',
      whereArgs: ['duplicateMerge'],
      orderBy: 'committed_at, id',
    )) {
      final summary = jsonDecode(row['summary']! as String) as Map;
      for (final kind in MergeChains.kinds) {
        maps[kind]!.addAll(
          (summary[kind] as Map? ?? const {}).cast<String, String>(),
        );
      }
    }
    return MergeHistoryRemap._(
      MergeChains(
        songs: maps['songs']!,
        editions: maps['editions']!,
        albums: maps['albums']!,
      ),
    );
  }

  bool get isEmpty => chains.isEmpty;

  /// [row] (a playback session or qualified play) with its song, release and
  /// edition following every merge to the record that stayed.
  ///
  /// Throws [MergeChainException] when a chain loops.
  Map<String, Object?> follow(Map<String, Object?> row) {
    if (isEmpty) return row;
    return {
      ...row,
      if (row.containsKey('song_id'))
        'song_id': chains.resolveValue('songs', row['song_id']),
      if (row.containsKey('album_id'))
        'album_id': chains.resolveValue('albums', row['album_id']),
      if (row.containsKey('album_edition_id'))
        'album_edition_id': chains.resolveValue(
          'editions',
          row['album_edition_id'],
        ),
    };
  }

  /// Moves this device's listening from the merged ids to the kept ones.
  static Future<void> repointHistory(
    DatabaseExecutor db, {
    required Map<String, String> songs,
    required Map<String, String> editions,
    required Map<String, String> albums,
  }) async {
    for (final table in [
      DatabaseTables.playbackSessions,
      DatabaseTables.qualifiedPlays,
    ]) {
      for (final (column, map) in [
        ('song_id', songs),
        ('album_edition_id', editions),
        ('album_id', albums),
      ]) {
        for (final MapEntry(key: merged, value: kept) in map.entries) {
          await db.update(
            table,
            {column: kept},
            where: '$column = ?',
            whereArgs: [merged],
          );
        }
      }
    }
  }
}
