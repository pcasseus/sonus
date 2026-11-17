import 'dart:convert';
import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/schema/new_release_publication_schema.dart';
import '../../../library/domain/entities/library_organization.dart';
import '../../../library/domain/entities/release_date.dart';
import '../../application/services/new_release_publication_store.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/moments/new_release_eligibility.dart';
import '../../domain/moments/new_release_publication.dart';

/// Published new-release debut stories in SQLite (App Update 1.3).
///
/// Writes go through [AppDatabase.transaction], so they wait for no
/// restore and are refused while one runs (restore admission). The song
/// id is the primary key and rows are inserted with ON CONFLICT DO
/// NOTHING, so however many loads race, a song has one record: the first.
class SqliteNewReleasePublicationRepository
    implements NewReleasePublicationStore {
  const SqliteNewReleasePublicationRepository(this.database);

  final AppDatabase database;

  static const String _table = NewReleasePublicationSchema.table;

  @override
  int get restoreGeneration => database.mutationCoordinator.restoreGeneration;

  @override
  Future<Map<String, NewReleasePublication>> readAll() async {
    final db = await database.database;
    return _decodeAll(await db.query(_table, orderBy: 'song_id'));
  }

  @override
  Future<Map<String, NewReleasePublication>> publish(
    Iterable<NewReleasePublication> publications, {
    required int restoreGeneration,
  }) {
    final bySong = {
      for (final publication in publications) publication.songId: publication,
    };
    if (bySong.isEmpty) return Future.value(const {});
    return database.transaction((txn) async {
      // A restore since the facts were read: they may be gone.
      if (restoreGeneration == this.restoreGeneration) {
        for (final publication in bySong.values) {
          await txn.insert(
            _table,
            toRow(publication),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      final ids = bySong.keys.toList();
      return _decodeAll(
        await txn.query(
          _table,
          where: 'song_id IN (${List.filled(ids.length, '?').join(', ')})',
          whereArgs: ids,
        ),
      );
    });
  }

  /// The row stored for [publication].
  static Map<String, Object?> toRow(NewReleasePublication publication) => {
    'song_id': publication.songId,
    'story_id': publication.storyId,
    'event_id': publication.eventId,
    'event_deduplication_key': publication.eventKey,
    'kind': publication.kind.name,
    'chart_scope': publication.scope.name,
    'chart_rank': publication.rank,
    'chart_name': publication.chartName,
    'week_start_utc': publication.weekStartUtc.toUtc().toIso8601String(),
    'debuted_at_utc': publication.debutedAtUtc.toUtc().toIso8601String(),
    'song_title': publication.songTitle,
    'artist_name': publication.artistName,
    'featured_artists': jsonEncode(publication.featuredArtists),
    'album_id': publication.albumId,
    'album_title': publication.albumTitle,
    'album_format': publication.albumFormat?.name,
    'release_date': publication.releaseDate.iso,
    'release_date_precision': publication.releaseDate.precision.name,
    'headline': publication.headline,
    'published_at': publication.publishedAtUtc.toUtc().toIso8601String(),
    'revision': publication.revision,
    'corrected_at': publication.correctedAtUtc?.toUtc().toIso8601String(),
  };

  /// The publication stored in [row]; null when the row cannot be read
  /// (then that song's debut is not re-told, and nothing is rewritten).
  static NewReleasePublication? fromRow(Map<String, Object?> row) {
    try {
      final precision = row['release_date_precision']! as String;
      final releaseDate = ReleaseDate.tryParse(row['release_date']! as String);
      if (releaseDate == null || releaseDate.precision.name != precision) {
        throw FormatException('release date', row['release_date']);
      }
      final format = row['album_format'] as String?;
      final corrected = row['corrected_at'] as String?;
      return NewReleasePublication(
        songId: row['song_id']! as String,
        storyId: row['story_id']! as String,
        eventId: row['event_id']! as String,
        eventKey: row['event_deduplication_key']! as String,
        kind: NewReleaseDebutKind.values.byName(row['kind']! as String),
        scope: ChartMomentScope.values.byName(row['chart_scope']! as String),
        rank: row['chart_rank']! as int,
        chartName: row['chart_name']! as String,
        weekStartUtc: DateTime.parse(row['week_start_utc']! as String).toUtc(),
        debutedAtUtc: DateTime.parse(row['debuted_at_utc']! as String).toUtc(),
        songTitle: row['song_title']! as String,
        artistName: row['artist_name']! as String,
        featuredArtists: List.unmodifiable(
          (jsonDecode(row['featured_artists']! as String) as List)
              .cast<String>(),
        ),
        albumId: row['album_id'] as String?,
        albumTitle: row['album_title'] as String?,
        albumFormat: format == null
            ? null
            : ReleaseFormat.values.byName(format),
        releaseDate: releaseDate,
        headline: row['headline']! as String,
        publishedAtUtc: DateTime.parse(row['published_at']! as String).toUtc(),
        revision: row['revision']! as int,
        correctedAtUtc: corrected == null
            ? null
            : DateTime.parse(corrected).toUtc(),
      );
    } catch (error) {
      developer.log(
        'A new-release publication could not be read (${error.runtimeType})',
        name: 'sonus.charts',
        level: 900,
        error: error,
      );
      return null;
    }
  }

  /// Unreadable rows still claim their song (kept by id, told by nothing):
  /// [_unreadable] stands in so the song is never published again.
  static Map<String, NewReleasePublication> _decodeAll(
    List<Map<String, Object?>> rows,
  ) => {
    for (final row in rows)
      row['song_id']! as String:
          fromRow(row) ?? _unreadable(row['song_id']! as String),
  };

  static NewReleasePublication _unreadable(String songId) =>
      NewReleasePublication(
        songId: songId,
        storyId: '',
        eventId: '',
        // Matches no event, so no story is re-worded from it.
        eventKey: '',
        kind: NewReleaseDebutKind.single,
        scope: ChartMomentScope.finalized,
        rank: 1,
        chartName: '',
        weekStartUtc: DateTime.utc(1970),
        debutedAtUtc: DateTime.utc(1970),
        songTitle: '',
        artistName: '',
        featuredArtists: const [],
        releaseDate: ReleaseDate.of(1970)!,
        headline: '',
        publishedAtUtc: DateTime.utc(1970),
      );
}
