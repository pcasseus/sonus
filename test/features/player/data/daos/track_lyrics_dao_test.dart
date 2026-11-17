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

  Future<void> store(String songId, {String? plain, String? synced}) =>
      db.insert(DatabaseTables.trackLyrics, {
        'song_id': songId,
        'plain_text': plain,
        'synced_text': synced,
        'created_at': '2026-09-20T12:00:00.000Z',
        'updated_at': '2026-09-20T12:00:00.000Z',
      });

  test('reads plain and synchronized lyrics, lines in time order', () async {
    await db.insert(DatabaseTables.songs, {'id': 'song_1'});
    await store(
      'song_1',
      plain: 'First line\nSecond line',
      synced: '''
[00:05.00]Second
[00:01.50]First
''',
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

  test('findBySongId returns null when lyrics do not exist', () async {
    expect(await dao.findBySongId('missing_song'), isNull);
  });

  test('deleting a song cascades to its lyrics', () async {
    await db.insert(DatabaseTables.songs, {'id': 'song_1'});
    await store('song_1', plain: 'Lyrics', synced: '[00:01.00]Lyrics');

    await db.delete(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: ['song_1'],
    );

    expect(await dao.findBySongId('song_1'), isNull);
  });

  test('lyrics cannot be stored for a missing song', () async {
    await expectLater(
      store('missing_song', plain: 'Lyrics'),
      throwsA(anything),
    );
  });
}
