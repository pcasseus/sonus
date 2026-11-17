import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/database_tables.dart';
import 'lyrics_provenance.dart';

/// One automatically found text to store.
class LyricsCandidate {
  const LyricsCandidate({
    required this.text,
    required this.source,
    this.confidence,
  }) : assert(source != LyricsSource.user, 'Use saveUserEdit.');

  final String text;
  final LyricsSource source;

  /// Generated text only, 0 to 1.
  final double? confidence;
}

/// Who supplied provider text, and on what terms.
class LyricsProviderDetails {
  const LyricsProviderDetails({
    required this.provider,
    required this.licence,
    this.reference,
    this.language,
  });

  final String provider;
  final LyricsLicence licence;
  final String? reference;
  final String? language;
}

/// What an automatic write did with each text.
class LyricsWriteResult {
  const LyricsWriteResult({required this.plain, required this.synced});

  static const nothing = LyricsWriteResult(plain: false, synced: false);

  /// Whether the text was stored (false: none offered, a better or the
  /// listener's own text was kept, or the licence forbids storing it).
  final bool plain;
  final bool synced;
}

/// The writes ingestion needs; the rules live in [LyricsPrecedence].
abstract interface class LyricsProvenanceWriter {
  /// The stored row, as stored (null: the song has no lyrics row).
  Future<Map<String, Object?>?> read(String songId);

  /// Stores each offered text that may replace the stored one. The other
  /// text, every listener edit and the offset stay as they are.
  Future<LyricsWriteResult> saveAutomatic({
    required String songId,
    LyricsCandidate? plain,
    LyricsCandidate? synced,
    LyricsProviderDetails? provider,
  });
}

/// The only production writer of `track_lyrics` text besides restore,
/// duplicate merge and cloud apply, which use [LyricsRows.merge] directly.
class SqliteLyricsProvenanceStore implements LyricsProvenanceWriter {
  SqliteLyricsProvenanceStore({
    required this.appDatabase,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Writes go through its transaction, so they wait for a restore.
  final AppDatabase appDatabase;
  final DateTime Function() _now;

  static Future<Map<String, Object?>?> readIn(
    DatabaseExecutor db,
    String songId,
  ) async {
    final rows = await db.query(
      DatabaseTables.trackLyrics,
      where: 'song_id = ?',
      whereArgs: [songId],
      limit: 1,
    );
    return rows.isEmpty ? null : {...rows.single};
  }

  /// Inserts or replaces the row [LyricsRows.merge] returned.
  static Future<void> writeIn(
    DatabaseExecutor db,
    Map<String, Object?> row, {
    required bool exists,
  }) async {
    if (exists) {
      await db.update(
        DatabaseTables.trackLyrics,
        {...row}..remove('song_id'),
        where: 'song_id = ?',
        whereArgs: [row['song_id']],
      );
    } else {
      await db.insert(DatabaseTables.trackLyrics, row);
    }
  }

  @override
  Future<Map<String, Object?>?> read(String songId) async =>
      readIn(await appDatabase.database, songId);

  @override
  Future<LyricsWriteResult> saveAutomatic({
    required String songId,
    LyricsCandidate? plain,
    LyricsCandidate? synced,
    LyricsProviderDetails? provider,
  }) {
    final stamp = _now().toUtc().toIso8601String();
    Map<String, Object?>? columns(LyricsTextKind kind, LyricsCandidate? c) {
      if (c == null || c.text.trim().isEmpty) return null;
      if (c.source == LyricsSource.provider &&
          (provider == null || provider.licence == LyricsLicence.noStore)) {
        // Live-only provider text is never written.
        return null;
      }
      return LyricsText(
        text: c.text,
        source: c.source,
        updatedAt: stamp,
        confidence: c.source == LyricsSource.generated ? c.confidence : null,
      ).toColumns(kind);
    }

    final offeredPlain = columns(LyricsTextKind.plain, plain);
    final offeredSynced = columns(LyricsTextKind.synced, synced);
    if (offeredPlain == null && offeredSynced == null) {
      return Future.value(LyricsWriteResult.nothing);
    }
    final incoming = <String, Object?>{
      ...?offeredPlain,
      ...?offeredSynced,
      if (provider != null && provider.licence != LyricsLicence.noStore) ...{
        LyricsColumns.provider: provider.provider,
        LyricsColumns.providerRef: provider.reference,
        LyricsColumns.providerLicence: provider.licence.name,
        LyricsColumns.language: provider.language,
      },
    };

    return appDatabase.transaction((txn) async {
      final existing = await readIn(txn, songId);
      final merged = LyricsRows.merge(
        songId: songId,
        existing: existing,
        incoming: incoming,
        stamp: stamp,
      );
      if (merged == null) return LyricsWriteResult.nothing;
      await writeIn(txn, merged, exists: existing != null);
      bool took(LyricsTextKind kind, Map<String, Object?>? offered) =>
          offered != null &&
          merged[kind.textColumn] == offered[kind.textColumn] &&
          merged[kind.sourceColumn] == offered[kind.sourceColumn] &&
          merged[kind.updatedAtColumn] == stamp;
      return LyricsWriteResult(
        plain: took(LyricsTextKind.plain, offeredPlain),
        synced: took(LyricsTextKind.synced, offeredSynced),
      );
    });
  }

  /// The listener's own text for one kind (null clears it). Always wins
  /// over what is stored; stamped now.
  Future<void> saveUserEdit({
    required String songId,
    required LyricsTextKind kind,
    required String? text,
  }) {
    final stamp = _now().toUtc().toIso8601String();
    return appDatabase.transaction((txn) async {
      final existing = await readIn(txn, songId);
      final row = <String, Object?>{
        for (final c in LyricsColumns.all) c: existing?[c],
        'song_id': songId,
        ...LyricsText(
          text: text,
          source: LyricsSource.user,
          userEditedAt: DateTime.parse(stamp),
          updatedAt: stamp,
        ).toColumns(kind),
        'created_at': existing?['created_at'] ?? stamp,
        'updated_at': stamp,
      };
      await writeIn(txn, row, exists: existing != null);
    });
  }

  /// The listener's timing correction, applied on read.
  Future<void> setUserOffset(String songId, Duration offset) {
    final ms = offset.inMilliseconds;
    if (ms.abs() > 600000) {
      throw ArgumentError.value(offset, 'offset', 'Must be within 10 minutes.');
    }
    final stamp = _now().toUtc().toIso8601String();
    return appDatabase.transaction((txn) async {
      final existing = await readIn(txn, songId);
      final row = <String, Object?>{
        for (final c in LyricsColumns.all) c: existing?[c],
        'song_id': songId,
        LyricsColumns.offsetMs: ms,
        LyricsColumns.offsetUserEditedAt: stamp,
        'created_at': existing?['created_at'] ?? stamp,
        'updated_at': stamp,
      };
      await writeIn(txn, row, exists: existing != null);
    });
  }
}
