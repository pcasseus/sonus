import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/core/database/schema/lyrics_schema.dart';
import 'package:sonus_next/features/player/data/daos/track_lyrics_dao.dart';
import 'package:sonus_next/features/player/data/repositories/sqlite_track_lyrics_repository.dart';

import '../../../../support/library_seed.dart';

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

  group('coordinated with restore admission', () {
    late Directory directory;
    late AppDatabase appDatabase;
    late SqliteTrackLyricsRepository coordinated;

    setUp(() async {
      // A separate file: sqflite shares one in-memory handle per path, and
      // the file-level setUp already holds it with a minimal schema.
      directory = await Directory.systemTemp.createTemp('sonus_lyrics_');
      appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${directory.path}${Platform.pathSeparator}lyrics.db',
      );
      final executor = await appDatabase.database;

      // Seeds song-a with existing plain lyrics 'Lyrics a'.
      await seedConnectedLibrary(executor, key: 'a');

      coordinated = SqliteTrackLyricsRepository(
        TrackLyricsDao(executor),
        appDatabase: appDatabase,
      );
    });

    tearDown(() async {
      await appDatabase.close();
      await directory.delete(recursive: true);
    });

    Future<List<Map<String, Object?>>> lyricsRows() async {
      return (await appDatabase.database).query(DatabaseTables.trackLyrics);
    }

    test('save and delete are rejected during an exclusive restore', () async {
      final before = await lyricsRows();
      expect(before.single['plain_text'], 'Lyrics a');

      final entered = Completer<void>();
      final release = Completer<void>();
      final restore = appDatabase.mutationCoordinator.runExclusiveRestore(
        () async {
          entered.complete();
          await release.future;
        },
      );
      await entered.future;

      try {
        await expectLater(
          coordinated.save(songId: 'song-a', syncedText: '[00:01.00]New'),
          throwsA(isA<LibraryMutationUnavailable>()),
        );
        await expectLater(
          coordinated.deleteBySongId('song-a'),
          throwsA(isA<LibraryMutationUnavailable>()),
        );

        expect(await lyricsRows(), before);
      } finally {
        release.complete();
        await restore;
      }
    });

    test('save and delete work when no restore is active', () async {
      await coordinated.save(songId: 'song-a', syncedText: '[00:01.00]New');

      final saved = await coordinated.getBySongId('song-a');
      expect(saved?.plainText, isNull);
      expect(saved?.syncedLines.single.text, 'New');
      expect(appDatabase.mutationCoordinator.activeMutations, 0);

      await coordinated.deleteBySongId('song-a');

      expect(await coordinated.getBySongId('song-a'), isNull);
    });
  });
}
