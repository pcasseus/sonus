import 'dart:math' as math;

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../domain/moments/chart_moment_artist_joint_control.dart';

/// Song credits for telling joint chart control from a collaboration
/// (App Update 1.2, REF-19). Read only.
class SqliteChartSongCreditReader {
  const SqliteChartSongCreditReader(this.database);

  final AppDatabase database;

  /// The credits of each of [songIds] that has any. A song is complete
  /// when every credit names an artist and exactly one is primary.
  Future<Map<String, ChartSongCredits>> creditsFor(Set<String> songIds) async {
    if (songIds.isEmpty) return const {};
    final db = await database.database;
    final ids = songIds.toList()..sort();
    final rows = <Map<String, Object?>>[];
    // SQLite limits bound parameters; a chart week has at most 200 songs.
    for (var start = 0; start < ids.length; start += 500) {
      final chunk = ids.sublist(start, math.min(start + 500, ids.length));
      rows.addAll(
        await db.query(
          DatabaseTables.songArtistCredits,
          columns: ['song_id', 'artist_id', 'role'],
          where: 'song_id IN (${List.filled(chunk.length, '?').join(', ')})',
          whereArgs: chunk,
        ),
      );
    }
    final artists = <String, Set<String>>{};
    final unresolved = <String>{};
    final primaries = <String, int>{};
    for (final row in rows) {
      final songId = row['song_id']! as String;
      artists.putIfAbsent(songId, () => {});
      switch (row['artist_id']) {
        case final String artistId:
          artists[songId]!.add(artistId);
        default:
          unresolved.add(songId);
      }
      if (row['role'] == 'primary' || row['role'] == 'coPrimary') {
        primaries[songId] = (primaries[songId] ?? 0) + 1;
      }
    }
    return {
      for (final MapEntry(key: songId, value: ids) in artists.entries)
        songId: ChartSongCredits(
          artistIds: Set.unmodifiable(ids),
          complete: !unresolved.contains(songId) && primaries[songId] == 1,
        ),
    };
  }
}
