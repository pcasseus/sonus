import 'dart:math' as math;

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../domain/moments/new_release_eligibility.dart';

/// Reads what proves new-release debuts (App Update 1.3, user rules
/// 2026-11-16), read-only: when this database's chart history began, the
/// deletion journal's Moments cutoff, and each candidate song's first
/// qualified play. Nothing new is stored.
class SqliteNewReleaseEvidenceReader {
  const SqliteNewReleaseEvidenceReader(
    this.database, {
    required this.historyOriginUtc,
    required this.momentsCutoffUtc,
  });

  final AppDatabase database;

  /// SqliteChartRepository.chartHistoryOriginUtc.
  final Future<DateTime?> Function() historyOriginUtc;

  /// SqliteDeletionJournalReader.momentsCutoff.
  final Future<DateTime?> Function() momentsCutoffUtc;

  Future<NewReleaseEvidence> read(Set<String> songIds) async =>
      NewReleaseEvidence(
        historyOriginUtc: await historyOriginUtc(),
        momentsCutoffUtc: await momentsCutoffUtc(),
        firstPlayAt: await firstPlays(songIds),
      );

  /// Each song's earliest stored qualified play, by song id; songs without
  /// one are left out. Parameterized, in chunks, on the (song_id,
  /// qualified_at) index. Plays are stored as UTC ISO-8601 text, so the
  /// text minimum is the earliest play.
  Future<Map<String, DateTime>> firstPlays(Set<String> songIds) async {
    final ids = songIds.toList()..sort();
    if (ids.isEmpty) return const {};
    final db = await database.database;
    final first = <String, DateTime>{};
    const chunk = 400;
    for (var offset = 0; offset < ids.length; offset += chunk) {
      final part = ids.sublist(offset, math.min(offset + chunk, ids.length));
      final rows = await db.rawQuery(
        'SELECT song_id, MIN(qualified_at) AS first_at '
        'FROM ${DatabaseTables.qualifiedPlays} '
        'WHERE song_id IN (${List.filled(part.length, '?').join(', ')}) '
        'GROUP BY song_id',
        part,
      );
      for (final row in rows) {
        final at = DateTime.tryParse(row['first_at']! as String);
        if (at != null) first[row['song_id']! as String] = at.toUtc();
      }
    }
    return Map.unmodifiable(first);
  }
}
