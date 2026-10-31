import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/artwork/data/daos/artwork_asset_dao.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/presentation/pages/album_profile_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

const _albumId = 'album_r5';
const _standard = 'edition_standard';
const _deluxe = 'edition_deluxe';
const _bare = 'edition_bare';

const _standardCover = r'C:\Artwork\R5\standard.jpg';
const _deluxeCover = r'C:\Artwork\R5\deluxe.jpg';
const _songCover = r'C:\Artwork\R5\custom.jpg';

/// SN-50 A-Q12 on the Album page, over the real library queries: in an
/// edition view a song shows that edition's cover, then its own artwork,
/// then the primary edition's cover, then the placeholder.
void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() => appDatabase.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  /// Plays the edition on screen and returns each queued song's artwork.
  Future<Map<String, String?>> queuedArtwork(
    WidgetTester tester,
    String editionId,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final engine = _QueueEngine();
    final db = (await tester.runAsync(() => appDatabase.database))!;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryQueryRepository?>.value(
            value: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
          ),
          Provider<PlaybackCoordinator?>.value(
            value: PlaybackCoordinator(engine: engine),
          ),
        ],
        child: MaterialApp(
          home: AlbumProfilePage(
            albumId: _albumId,
            initialAlbumTitle: 'R5 Album',
            initialEditionId: editionId,
          ),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('album-profile-play-all-button')),
    );
    await settle(tester);

    return {for (final track in engine.loaded) track.songId: track.artworkPath};
  }

  String? headerCover(WidgetTester tester) {
    final images = find.descendant(
      of: find.byKey(const ValueKey<String>('album-profile-artwork-$_albumId')),
      matching: find.byType(Image),
    );
    if (images.evaluate().isEmpty) return null;

    final provider = tester.widget<Image>(images.first).image;
    final file = switch (provider) {
      ResizeImage(imageProvider: final FileImage image) => image,
      final FileImage image => image,
      _ => throw StateError('Unexpected cover image: $provider'),
    };
    return file.file.path;
  }

  testWidgets('the edition on screen gives its cover, even over a song\'s '
      'own artwork', (tester) async {
    await tester.runAsync(() => _seed(appDatabase));

    final standard = await queuedArtwork(tester, _standard);
    expect(standard, {
      'song_custom': _standardCover,
      'song_shared': _standardCover,
    });
    expect(headerCover(tester), _standardCover);

    final deluxe = await queuedArtwork(tester, _deluxe);
    expect(deluxe, {
      'song_custom': _deluxeCover,
      'song_shared': _deluxeCover,
      'song_bonus': _deluxeCover,
    });
    expect(headerCover(tester), _deluxeCover);
  });

  testWidgets('an edition without a cover uses the primary cover, never '
      'the Deluxe', (tester) async {
    await tester.runAsync(() => _seed(appDatabase));

    expect(await queuedArtwork(tester, _bare), {'song_tour': _standardCover});
    expect(headerCover(tester), _standardCover);
  });

  testWidgets('with no primary cover either, the placeholder shows', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await _seed(appDatabase);
      await (await appDatabase.database).update(
        DatabaseTables.albumEditions,
        {'artwork_id': null},
        where: 'id = ?',
        whereArgs: [_standard],
      );
    });

    expect(await queuedArtwork(tester, _bare), {'song_tour': null});
    expect(headerCover(tester), isNull);
  });
}

/// A release with a covered primary Standard, a covered Deluxe and a
/// coverless Tour Cut. "custom" has its own artwork and "shared" none, both
/// on Standard and Deluxe; "bonus" is Deluxe-only; "tour" is homed on the
/// Deluxe but listed only on the Tour Cut.
Future<void> _seed(AppDatabase appDatabase) async {
  final db = await appDatabase.database;
  final at = DateTime.utc(2026, 9, 10);

  for (final (id, path) in [
    ('art_standard', _standardCover),
    ('art_deluxe', _deluxeCover),
    ('art_custom', _songCover),
  ]) {
    await ArtworkAssetDao(db).insert(
      ArtworkAsset(
        id: id,
        filePath: path,
        normalizedPath: path.toLowerCase(),
        createdAt: at,
        updatedAt: at,
      ),
    );
  }

  await ArtistDao(db).insert(
    Artist(
      id: 'artist_r5',
      name: 'R5 Artist',
      canonicalName: 'r5 artist',
      createdAt: at,
      updatedAt: at,
    ),
  );
  await AlbumDao(db).insert(
    Album(
      id: _albumId,
      artistId: 'artist_r5',
      title: 'R5 Album',
      canonicalTitle: 'r5 album',
      createdAt: at,
      updatedAt: at,
    ),
  );

  for (final (id, title, type, primary, artwork) in [
    (_standard, 'R5 Album', AlbumEditionType.standard, true, 'art_standard'),
    (_deluxe, 'R5 Album Deluxe', AlbumEditionType.deluxe, false, 'art_deluxe'),
    (_bare, 'R5 Album (Tour Cut)', AlbumEditionType.other, false, null),
  ]) {
    await AlbumEditionDao(db).insert(
      AlbumEdition(
        id: id,
        albumId: _albumId,
        title: title,
        type: type,
        isPrimary: primary,
        artworkId: artwork,
        createdAt: at,
        updatedAt: at,
      ),
    );
  }

  final listings = <String, List<String>>{
    _standard: [],
    _deluxe: [],
    _bare: [],
  };
  for (final (index, (id, home, artwork, listedIn)) in [
    ('song_custom', _standard, 'art_custom', [_standard, _deluxe]),
    ('song_shared', _standard, null, [_standard, _deluxe]),
    ('song_bonus', _deluxe, null, [_deluxe]),
    ('song_tour', _deluxe, null, [_bare]),
  ].indexed) {
    await SongDao(db).insert(
      Song(
        id: id,
        artistId: 'artist_r5',
        albumId: _albumId,
        albumEditionId: home,
        title: 'Track $id',
        canonicalTitle: 'track $id',
        trackNumber: index + 1,
        durationSeconds: 180,
        isSingle: false,
        featuredArtists: const [],
        artworkId: artwork,
        createdAt: at,
        updatedAt: at,
      ),
    );
    final file = '${Directory.systemTemp.path}/r5/$id.mp3';
    await MediaFileBindingDao(db).insert(
      MediaFileBinding(
        id: 'media_$id',
        songId: id,
        filePath: file,
        normalizedPath: file.toLowerCase(),
        isAvailable: true,
        lastSeenAt: at,
        createdAt: at,
        updatedAt: at,
      ),
    );
    for (final edition in listedIn) {
      listings[edition]!.add(id);
    }
  }

  for (final MapEntry(key: edition, value: songs) in listings.entries) {
    for (final (index, songId) in songs.indexed) {
      await AlbumEditionTrackDao(db).insert(
        AlbumEditionTrack(
          albumEditionId: edition,
          songId: songId,
          discNumber: 1,
          trackNumber: index + 1,
          sortPosition: index,
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
  }
}

/// Keeps the last queue loaded.
class _QueueEngine implements PlaybackEngine {
  List<PlaybackTrack> loaded = const [];

  @override
  Stream<PlaybackState> get states => const Stream.empty();

  @override
  PlaybackState get currentState => const PlaybackState();

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async => loaded = List.of(tracks);

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {}

  @override
  Future<void> appendTrack(PlaybackTrack track) async {}

  @override
  Future<void> removeTrackAt(int index) async {}

  @override
  Future<void> moveTrack({
    required int oldIndex,
    required int newIndex,
  }) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
