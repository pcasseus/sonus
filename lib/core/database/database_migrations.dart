import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../identity/entity_id.dart';
import '../identity/text_normalizer.dart';
import 'database_tables.dart';
import 'schema/account_schema.dart';
import 'schema/analytics_schema.dart';
import 'schema/chart_schema.dart';
import 'schema/import_schema.dart';
import 'schema/library_schema.dart';
import 'schema/lyrics_schema.dart';
import 'schema/playlist_schema.dart';
import 'schema/sync_schema.dart';

abstract final class DatabaseMigrations {
  static Future<void> migrate(
    Database db, {
    required int oldVersion,
    required int newVersion,
  }) async {
    if (oldVersion >= newVersion) {
      return;
    }

    for (
      var targetVersion = oldVersion + 1;
      targetVersion <= newVersion;
      targetVersion++
    ) {
      await _migrateTo(db, targetVersion);
    }
  }

  static Future<bool> _columnExists(
    Database db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');

    return rows.any((row) => row['name'] == column);
  }

  static Future<void> _migrateTo(Database db, int targetVersion) async {
    switch (targetVersion) {
      case 1:
        return;

      case 2:
        await ImportSchema.createImportBatches(db);
        return;

      case 3:
        await LibrarySchema.createArtworkAssets(db);

        await db.execute(
          'ALTER TABLE ${DatabaseTables.artists} '
          'ADD COLUMN header_artwork_id TEXT '
          'REFERENCES ${DatabaseTables.artworkAssets}(id) '
          'ON UPDATE CASCADE ON DELETE SET NULL',
        );

        await db.execute(
          'ALTER TABLE ${DatabaseTables.artists} '
          'ADD COLUMN top_artists_artwork_id TEXT '
          'REFERENCES ${DatabaseTables.artworkAssets}(id) '
          'ON UPDATE CASCADE ON DELETE SET NULL',
        );

        await db.execute(
          'ALTER TABLE ${DatabaseTables.albumEditions} '
          'ADD COLUMN artwork_id TEXT '
          'REFERENCES ${DatabaseTables.artworkAssets}(id) '
          'ON UPDATE CASCADE ON DELETE SET NULL',
        );

        await db.execute(
          'ALTER TABLE ${DatabaseTables.songs} '
          'ADD COLUMN artwork_id TEXT '
          'REFERENCES ${DatabaseTables.artworkAssets}(id) '
          'ON UPDATE CASCADE ON DELETE SET NULL',
        );

        await db.execute('''
          CREATE INDEX idx_artists_header_artwork_id
          ON ${DatabaseTables.artists}(header_artwork_id)
        ''');

        await db.execute('''
          CREATE INDEX idx_artists_top_artists_artwork_id
          ON ${DatabaseTables.artists}(top_artists_artwork_id)
        ''');

        await db.execute('''
          CREATE INDEX idx_album_editions_artwork_id
          ON ${DatabaseTables.albumEditions}(artwork_id)
        ''');

        await db.execute('''
          CREATE INDEX idx_songs_artwork_id
          ON ${DatabaseTables.songs}(artwork_id)
        ''');

        return;

      case 4:
        await SyncSchema.create(db);
        return;

      case 5:
        await db.execute(
          'ALTER TABLE ${DatabaseTables.artists} '
          'ADD COLUMN is_blacklisted INTEGER NOT NULL DEFAULT 0 '
          'CHECK (is_blacklisted IN (0, 1))',
        );
        return;

      case 6:
        await ImportSchema.createImportSources(db);
        return;

      case 7:
        await db.execute(
          'ALTER TABLE ${DatabaseTables.mediaFileBindings} '
          'ADD COLUMN source_id TEXT '
          'REFERENCES ${DatabaseTables.importSources}(id) '
          'ON UPDATE CASCADE ON DELETE SET NULL',
        );

        await db.execute('''
          CREATE INDEX idx_media_file_bindings_source_id
          ON ${DatabaseTables.mediaFileBindings}(source_id)
        ''');

        return;

      case 8:
        await ImportSchema.createSongImportReviews(db);
        return;

      case 9:
        await db.execute(
          'ALTER TABLE ${DatabaseTables.songs} '
          'ADD COLUMN disc_number INTEGER NOT NULL DEFAULT 1 '
          'CHECK (disc_number >= 0)',
        );
        return;

      case 10:
        const legacyTable = 'song_import_reviews_v9';

        await db.execute(
          'ALTER TABLE ${DatabaseTables.songImportReviews} '
          'RENAME TO $legacyTable',
        );

        await db.execute('DROP INDEX idx_song_import_reviews_resolved_at');

        await ImportSchema.createSongImportReviews(db);

        await db.execute('''
          INSERT INTO ${DatabaseTables.songImportReviews} (
            song_id,
            metadata_source,
            review_reasons,
            resolved_at,
            created_at,
            updated_at
          )
          SELECT
            song_id,
            metadata_source,
            review_reasons,
            resolved_at,
            created_at,
            updated_at
          FROM $legacyTable
        ''');

        await db.execute('DROP TABLE $legacyTable');
        return;

      case 11:
        await LyricsSchema.create(db);
        return;

      case 12:
        await AnalyticsSchema.create(db);
        return;

      case 13:
        await db.execute(
          'ALTER TABLE ${DatabaseTables.songs} '
          'ADD COLUMN is_blocked INTEGER NOT NULL DEFAULT 0 '
          'CHECK (is_blocked IN (0, 1))',
        );
        return;

      case 14:
        await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_playback_listening_segments_one_open_per_session
          ON ${DatabaseTables.playbackListeningSegments}(playback_session_id)
          WHERE ended_at IS NULL
        ''');
        return;

      case 15:
        await db.update(
          DatabaseTables.artists,
          const {'is_blacklisted': 0},
          where: 'is_blacklisted != ?',
          whereArgs: [0],
        );
        return;

      case 16:
        await ChartSchema.createChartSnapshots(db);
        await ChartSchema.createChartEntries(db);
        await ChartSchema.createChartIndexes(db);
        return;

      case 17:
        await ChartSchema.createChartMomentEvents(db);
        await ChartSchema.createChartMomentIndexes(db);
        return;

      case 18:
        if (!await _columnExists(
          db,
          DatabaseTables.chartEntries,
          'artist_id',
        )) {
          await db.execute(
            'ALTER TABLE ${DatabaseTables.chartEntries} '
            'ADD COLUMN artist_id TEXT',
          );
        }

        if (!await _columnExists(
          db,
          DatabaseTables.chartMomentEvents,
          'entity_artist_id',
        )) {
          await db.execute(
            'ALTER TABLE ${DatabaseTables.chartMomentEvents} '
            'ADD COLUMN entity_artist_id TEXT',
          );
        }

        if (!await _columnExists(
          db,
          DatabaseTables.chartMomentEvents,
          'related_entity_artist_id',
        )) {
          await db.execute(
            'ALTER TABLE ${DatabaseTables.chartMomentEvents} '
            'ADD COLUMN related_entity_artist_id TEXT',
          );
        }

        await db.execute('''
          UPDATE ${DatabaseTables.chartEntries}
          SET artist_id = (
            SELECT playback.artist_id
            FROM ${DatabaseTables.playbackSessions} AS playback
            WHERE playback.song_id =
                ${DatabaseTables.chartEntries}.entity_id
            ORDER BY playback.started_at ASC, playback.id ASC
            LIMIT 1
          )
          WHERE artist_id IS NULL
            AND chart_snapshot_id IN (
              SELECT id
              FROM ${DatabaseTables.chartSnapshots}
              WHERE chart_type = 'songs'
            )
        ''');

        await db.execute('''
          UPDATE ${DatabaseTables.chartEntries}
          SET artist_id = (
            SELECT playback.artist_id
            FROM ${DatabaseTables.playbackSessions} AS playback
            WHERE playback.album_id =
                ${DatabaseTables.chartEntries}.entity_id
            ORDER BY playback.started_at ASC, playback.id ASC
            LIMIT 1
          )
          WHERE artist_id IS NULL
            AND chart_snapshot_id IN (
              SELECT id
              FROM ${DatabaseTables.chartSnapshots}
              WHERE chart_type = 'albums'
            )
        ''');

        return;
      case 19:
        await PlaylistSchema.create(db);
        return;

      case 20:
        const legacyOutbox = 'sync_outbox_v19';

        await db.execute('DROP INDEX IF EXISTS idx_sync_outbox_user_created');

        await db.execute(
          'ALTER TABLE ${DatabaseTables.syncOutbox} '
          'RENAME TO $legacyOutbox',
        );

        await SyncSchema.createSyncOutbox(db);

        await db.execute('''
          INSERT INTO ${DatabaseTables.syncOutbox} (
            id,
            user_id,
            entity_type,
            entity_id,
            operation,
            created_at,
            updated_at
          )
          SELECT
            id,
            user_id,
            entity_type,
            entity_id,
            operation,
            created_at,
            updated_at
          FROM $legacyOutbox
        ''');

        await db.execute('DROP TABLE $legacyOutbox');

        return;
      case 21:
        await LibrarySchema.createSongArtistCredits(db);
        await _backfillSongArtistCredits(db);
        return;

      case 22:
        await db.execute(
          'ALTER TABLE ${DatabaseTables.songImportReviews} '
          'ADD COLUMN review_payload TEXT',
        );
        return;
      case 23:
        await LibrarySchema.createAlbumEditionTracks(db);
        await _backfillAlbumEditionTracks(db);
        return;

      case 24:
        await _addColumnIfMissing(
          db,
          table: DatabaseTables.albumEditionTracks,
          columnName: 'numbering_authority',
          definition:
              "TEXT NOT NULL DEFAULT 'inferred' "
              "CHECK (numbering_authority IN ('inferred', 'manual'))",
        );

        await _addColumnIfMissing(
          db,
          table: DatabaseTables.albumEditionTracks,
          columnName: 'ordering_authority',
          definition:
              "TEXT NOT NULL DEFAULT 'inferred' "
              "CHECK (ordering_authority IN ('inferred', 'manual'))",
        );

        return;
      case 25:
        await db.execute(
          "ALTER TABLE ${DatabaseTables.songs} "
          "ADD COLUMN version_label TEXT",
        );

        await db.execute(
          "ALTER TABLE ${DatabaseTables.songs} "
          "ADD COLUMN version_characteristics TEXT NOT NULL DEFAULT '[]'",
        );

        await db.execute(
          "ALTER TABLE ${DatabaseTables.songs} "
          "ADD COLUMN release_status TEXT NOT NULL DEFAULT 'released' "
          "CHECK (release_status IN ('released', 'unreleased'))",
        );

        await db.execute(
          "ALTER TABLE ${DatabaseTables.songs} "
          "ADD COLUMN is_leak INTEGER NOT NULL DEFAULT 0 "
          "CHECK (is_leak IN (0, 1))",
        );

        return;
      case 26:
        await AccountSchema.create(db);
        return;

      default:
        throw UnsupportedError(
          'No Sonus database migration exists for version $targetVersion.',
        );
    }
  }

  static Future<void> _addColumnIfMissing(
    Database db, {
    required String table,
    required String columnName,
    required String definition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');

    final alreadyExists = columns.any((row) => row['name'] == columnName);

    if (alreadyExists) {
      return;
    }

    await db.execute('ALTER TABLE $table ADD COLUMN $columnName $definition');
  }

  static Future<void> _backfillAlbumEditionTracks(Database db) async {
    final songs = await db.query(
      DatabaseTables.songs,
      columns: [
        'id',
        'album_edition_id',
        'disc_number',
        'track_number',
        'created_at',
        'updated_at',
      ],
      orderBy:
          'album_edition_id ASC, '
          'disc_number ASC, '
          'track_number ASC, '
          'title COLLATE NOCASE ASC, '
          'id ASC',
    );

    String? currentEditionId;
    var sortPosition = 0;

    for (final row in songs) {
      final editionId = row['album_edition_id'] as String;

      if (editionId != currentEditionId) {
        currentEditionId = editionId;
        sortPosition = 0;
      }

      await db.insert(DatabaseTables.albumEditionTracks, {
        'album_edition_id': editionId,
        'song_id': row['id'] as String,
        'disc_number': row['disc_number'] as int? ?? 1,
        'track_number': row['track_number'] as int? ?? 0,
        'sort_position': sortPosition++,
        'created_at': row['created_at'] as String,
        'updated_at': row['updated_at'] as String,
      });
    }
  }

  static Future<void> _backfillSongArtistCredits(Database db) async {
    final songs = await db.rawQuery('''
      SELECT
        s.id AS song_id,
        s.artist_id AS artist_id,
        s.featured_artists AS featured_artists,
        s.created_at AS created_at,
        s.updated_at AS updated_at,
        a.name AS artist_name,
        a.canonical_name AS artist_canonical_name
      FROM ${DatabaseTables.songs} AS s
      INNER JOIN ${DatabaseTables.artists} AS a
        ON a.id = s.artist_id
      ORDER BY s.created_at ASC, s.id ASC
    ''');

    for (final row in songs) {
      final songId = row['song_id'] as String;
      final artistId = row['artist_id'] as String;
      final artistName = row['artist_name'] as String;
      final canonicalArtistName = row['artist_canonical_name'] as String;
      final createdAt = row['created_at'] as String;
      final updatedAt = row['updated_at'] as String;

      var position = 0;

      await db.insert(DatabaseTables.songArtistCredits, {
        'id': EntityId.songArtistCredit(),
        'song_id': songId,
        'artist_id': artistId,
        'credited_name': artistName,
        'canonical_credited_name': canonicalArtistName,
        'role': 'primary',
        'position': position++,
        'created_at': createdAt,
        'updated_at': updatedAt,
      });

      final encodedFeatures = row['featured_artists'] as String? ?? '[]';

      dynamic decoded;

      try {
        decoded = jsonDecode(encodedFeatures);
      } catch (_) {
        decoded = const <dynamic>[];
      }

      if (decoded is! List) {
        continue;
      }

      final seen = <String>{canonicalArtistName};

      for (final value in decoded) {
        if (value is! String) {
          continue;
        }

        final creditedName = value.trim();

        if (creditedName.isEmpty) {
          continue;
        }

        final canonicalName = TextNormalizer.canonicalize(creditedName);

        if (canonicalName.isEmpty || !seen.add(canonicalName)) {
          continue;
        }

        final matchingArtists = await db.query(
          DatabaseTables.artists,
          columns: ['id'],
          where: 'canonical_name = ?',
          whereArgs: [canonicalName],
          limit: 2,
        );

        final linkedArtistId = matchingArtists.length == 1
            ? matchingArtists.single['id'] as String
            : null;

        await db.insert(DatabaseTables.songArtistCredits, {
          'id': EntityId.songArtistCredit(),
          'song_id': songId,
          'artist_id': linkedArtistId,
          'credited_name': creditedName,
          'canonical_credited_name': canonicalName,
          'role': 'featured',
          'position': position++,
          'created_at': createdAt,
          'updated_at': updatedAt,
        });
      }
    }
  }
}
