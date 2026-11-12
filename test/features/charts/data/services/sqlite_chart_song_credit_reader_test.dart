// App Update 1.2, REF-19: song credits read for telling joint chart control
// from a collaboration. A song is complete only when every credit names an
// artist and exactly one is primary.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/charts/data/services/sqlite_chart_song_credit_reader.dart';

import '../../../../support/library_seed.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late Database db;

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await database.database;
    for (final (i, key) in ['a', 'b', 'c', 'd'].indexed) {
      await seedConnectedLibrary(db, key: key, week: i);
    }
  });

  tearDown(() => database.close());

  Future<void> credit(String song, String? artist, String role, int at) =>
      db.insert(DatabaseTables.songArtistCredits, {
        'id': 'credit-$song-$at',
        'song_id': song,
        'artist_id': artist,
        'credited_name': 'Name $at',
        'canonical_credited_name': 'name $at',
        'role': role,
        'position': at,
        'created_at': fixtureTimestamp,
        'updated_at': fixtureTimestamp,
      });

  test('every credited artist, whatever the role; unclear songs are not '
      'complete', () async {
    await credit('song-b', 'artist-c', 'featured', 1);
    await credit('song-c', 'artist-a', 'coPrimary', 1);
    await credit('song-d', null, 'guest', 1);

    final credits = await SqliteChartSongCreditReader(
      database,
    ).creditsFor({'song-a', 'song-b', 'song-c', 'song-d', 'song-missing'});

    expect(credits.keys.toSet(), {'song-a', 'song-b', 'song-c', 'song-d'});
    expect(credits['song-a']!.artistIds, {'artist-a'});
    expect(credits['song-a']!.complete, isTrue);
    expect(credits['song-b']!.artistIds, {'artist-b', 'artist-c'});
    expect(credits['song-b']!.complete, isTrue, reason: 'a featured guest');
    expect(credits['song-c']!.complete, isFalse, reason: 'two primaries');
    expect(credits['song-d']!.artistIds, {'artist-d'});
    expect(credits['song-d']!.complete, isFalse, reason: 'unresolved credit');
  });

  test('nothing asked, nothing read', () async {
    expect(await SqliteChartSongCreditReader(database).creditsFor({}), {});
  });
}
