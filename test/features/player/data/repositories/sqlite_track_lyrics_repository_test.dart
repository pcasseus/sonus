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

  test('save and getBySongId round-trip lyrics', () async {
    await repository.save(
      songId: 'song_1',
      plainText: 'Plain lyrics',
      syncedText: '''
[00:03.00]Later
[00:01.00]Earlier
''',
    );

    final lyrics = await repository.getBySongId('song_1');

    expect(lyrics, isNotNull);
    expect(lyrics!.songId, 'song_1');
    expect(lyrics.plainText, 'Plain lyrics');
    expect(lyrics.syncedLines, hasLength(2));
    expect(lyrics.syncedLines[0].text, 'Earlier');
    expect(lyrics.syncedLines[1].text, 'Later');
  });

  test('save updates existing lyrics for the song', () async {
    await repository.save(songId: 'song_1', plainText: 'Old lyrics');

    await repository.save(
      songId: 'song_1',
      plainText: 'Updated lyrics',
      syncedText: '[00:01.00]Updated',
    );

    final rows = await db.query(DatabaseTables.trackLyrics);
    final lyrics = await repository.getBySongId('song_1');

    expect(rows, hasLength(1));
    expect(lyrics, isNotNull);
    expect(lyrics!.plainText, 'Updated lyrics');
    expect(lyrics.syncedLines.single.text, 'Updated');
  });

  test('deleteBySongId removes lyrics', () async {
    await repository.save(songId: 'song_1', plainText: 'Lyrics');

    await repository.deleteBySongId('song_1');

    expect(await repository.getBySongId('song_1'), isNull);
  });
}
