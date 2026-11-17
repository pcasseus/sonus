import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/lyrics_schema.dart';
import 'package:sonus_next/features/player/data/daos/track_lyrics_dao.dart';
import 'package:sonus_next/features/player/data/repositories/sqlite_track_lyrics_repository.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late SqliteTrackLyricsRepository repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');

    await db.execute('''
      CREATE TABLE ${DatabaseTables.songs} (
        id TEXT PRIMARY KEY NOT NULL
      )
    ''');

    await LyricsSchema.create(db);

    repository = SqliteTrackLyricsRepository(TrackLyricsDao(db));

    await db.insert(DatabaseTables.songs, {'id': 'song_1'});
  });

  tearDown(() async {
    await db.close();
  });

  test('getBySongId reads stored lyrics', () async {
    await db.insert(DatabaseTables.trackLyrics, {
      'song_id': 'song_1',
      'plain_text': 'Plain lyrics',
      'synced_text': '''
[00:03.00]Later
[00:01.00]Earlier
''',
      'created_at': '2026-09-20T12:00:00.000Z',
      'updated_at': '2026-09-20T12:00:00.000Z',
    });

    final lyrics = await repository.getBySongId('song_1');

    expect(lyrics, isNotNull);
    expect(lyrics!.songId, 'song_1');
    expect(lyrics.plainText, 'Plain lyrics');
    expect(lyrics.syncedLines, hasLength(2));
    expect(lyrics.syncedLines[0].text, 'Earlier');
    expect(lyrics.syncedLines[1].text, 'Later');
  });

  test('getBySongId is null without lyrics', () async {
    expect(await repository.getBySongId('song_1'), isNull);
  });
}
