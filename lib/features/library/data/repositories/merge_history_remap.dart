import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

/// App Update 1.2: listening that belonged to a merged duplicate follows the
/// record that stayed, wherever it comes from: this device's history when a
/// merge arrives from another device, or a listening session downloaded
/// from the cloud archive after the merge.
class MergeHistoryRemap {
  MergeHistoryRemap._(this._songs, this._editions, this._albums);

  final Map<String, String> _songs;
  final Map<String, String> _editions;
  final Map<String, String> _albums;

  /// Every merge this device knows (its own and other devices').
  static Future<MergeHistoryRemap> load(DatabaseExecutor db) async {
    final songs = <String, String>{};
    final editions = <String, String>{};
    final albums = <String, String>{};
    for (final row in await db.query(
      DatabaseTables.libraryDeletionJournal,
      columns: ['summary'],
      where: 'operation = ?',
      whereArgs: ['duplicateMerge'],
    )) {
      final summary = jsonDecode(row['summary']! as String) as Map;
      for (final (key, into) in [
        ('songs', songs),
        ('editions', editions),
        ('albums', albums),
      ]) {
        into.addAll((summary[key] as Map? ?? const {}).cast<String, String>());
      }
    }
    return MergeHistoryRemap._(songs, editions, albums);
  }

  bool get isEmpty => _songs.isEmpty && _editions.isEmpty && _albums.isEmpty;

  /// A merged id's kept id, following a chain of merges.
  static String? _follow(Map<String, String> map, Object? id) {
    if (id is! String) return null;
    var current = id;
    for (var i = 0; i < 8; i++) {
      final next = map[current];
      if (next == null || next == current) return current;
      current = next;
    }
    return current;
  }

  /// [row] (a playback session or qualified play) with its song, release and
  /// edition following any merge.
  Map<String, Object?> follow(Map<String, Object?> row) {
    if (isEmpty) return row;
    return {
      ...row,
      if (row.containsKey('song_id'))
        'song_id': _follow(_songs, row['song_id']),
      if (row.containsKey('album_id'))
        'album_id': _follow(_albums, row['album_id']),
      if (row.containsKey('album_edition_id'))
        'album_edition_id': _follow(_editions, row['album_edition_id']),
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
