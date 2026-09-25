import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/lyrics_schema.dart';
import 'package:sonus_next/features/player/data/daos/track_lyrics_dao.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late TrackLyricsDao dao;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');

    await db.execute('''
      CREATE TABLE ${DatabaseTables.songs} (
        id TEXT PRIMARY KEY NOT NULL
      )
    ''');

    await LyricsSchema.create(db);

    dao = TrackLyricsDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upsert stores and reads plain and synchronized lyrics', () async {
    await db.insert(DatabaseTables.songs, {'id': 'song_1'});

    final createdAt = DateTime.utc(2026, 9, 20, 12);
    final updatedAt = DateTime.utc(2026, 9, 20, 13);

    await dao.upsert(
      songId: 'song_1',
      plainText: 'First line\nSecond line',
      syncedText: '''
[00:05.00]Second
[00:01.50]First
''',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final lyrics = await dao.findBySongId('song_1');

    expect(lyrics, isNotNull);
    expect(lyrics!.songId, 'song_1');
    expect(lyrics.plainText, 'First line\nSecond line');
    expect(lyrics.syncedLines, hasLength(2));
    expect(lyrics.syncedLines[0].timestamp, const Duration(milliseconds: 1500));
    expect(lyrics.syncedLines[0].text, 'First');
    expect(lyrics.syncedLines[1].timestamp, const Duration(seconds: 5));
    expect(lyrics.syncedLines[1].text, 'Second');
  });

  test('upsert replaces lyrics for the same song', () async {
    await db.insert(DatabaseTables.songs, {'id': 'song_1'});

    final first = DateTime.utc(2026, 9, 20, 12);
    final second = DateTime.utc(2026, 9, 20, 13);

    await dao.upsert(
      songId: 'song_1',
      plainText: 'Old lyrics',
      syncedText: null,
      createdAt: first,
      updatedAt: first,
    );

    await dao.upsert(
      songId: 'song_1',
      plainText: 'New lyrics',
      syncedText: '[00:02.00]New synced lyric',
      createdAt: first,
      updatedAt: second,
    );

    final rows = await db.query(DatabaseTables.trackLyrics);
    final lyrics = await dao.findBySongId('song_1');

    expect(rows, hasLength(1));
    expect(rows.single['created_at'], first.toIso8601String());
    expect(rows.single['updated_at'], second.toIso8601String());
    expect(lyrics, isNotNull);
    expect(lyrics!.plainText, 'New lyrics');
    expect(lyrics.syncedLines.single.text, 'New synced lyric');
  });

  test('findBySongId returns null when lyrics do not exist', () async {
    expect(await dao.findBySongId('missing_song'), isNull);
  });

  test('deleteBySongId removes stored lyrics', () async {
    await db.insert(DatabaseTables.songs, {'id': 'song_1'});

    final now = DateTime.utc(2026, 9, 20, 12);

    await dao.upsert(
      songId: 'song_1',
      plainText: 'Lyrics',
      syncedText: null,
      createdAt: now,
      updatedAt: now,
    );

    await dao.deleteBySongId('song_1');

    expect(await dao.findBySongId('song_1'), isNull);
  });

  test('deleting a song cascades to its lyrics', () async {
    await db.insert(DatabaseTables.songs, {'id': 'song_1'});

    final now = DateTime.utc(2026, 9, 20, 12);

    await dao.upsert(
      songId: 'song_1',
      plainText: 'Lyrics',
      syncedText: '[00:01.00]Lyrics',
      createdAt: now,
      updatedAt: now,
    );

    await db.delete(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: ['song_1'],
    );

    expect(await dao.findBySongId('song_1'), isNull);
  });

  test('lyrics cannot be stored for a missing song', () async {
    final now = DateTime.utc(2026, 9, 20, 12);

    await expectLater(
      dao.upsert(
        songId: 'missing_song',
        plainText: 'Lyrics',
        syncedText: null,
        createdAt: now,
        updatedAt: now,
      ),
      throwsA(anything),
    );
  });
}
