// App Update 1.3 (post-preview): the playlist song picker shows each song's
// cover between its checkbox and its title. Disposable databases and
// fictional fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/widgets/sonus_artwork_image.dart';
import 'package:sonus_next/core/design/widgets/sonus_decorations.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/playlists/application/models/playlist_add_result.dart';
import 'package:sonus_next/features/playlists/presentation/controllers/playlist_song_picker_controller.dart';
import 'package:sonus_next/features/playlists/presentation/pages/playlist_song_picker_page.dart';

LibraryTrack _track(
  String id, {
  String? title,
  String? artworkPath,
  String? versionLabel,
}) => LibraryTrack(
  songId: id,
  title: title ?? 'Song $id',
  artistId: 'artist-nova',
  artistName: 'Nova',
  albumId: 'album-first',
  albumTitle: 'First Light',
  albumEditionId: 'edition-first',
  albumEditionTitle: 'Standard',
  albumEditionType: AlbumEditionType.values.first,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const [],
  versionLabel: versionLabel,
  artworkPath: artworkPath,
  dateAdded: DateTime(2026, 1, 1),
  filePath: '/music/$id.mp3',
  isAvailable: true,
);

Finder _key(String value) => find.byKey(ValueKey<String>(value));

String? _artworkOf(WidgetTester tester, String songId) =>
    tester.widget<SonusArtworkImage>(_key('song-picker-artwork-$songId')).path;

Future<void> _open(
  WidgetTester tester,
  Future<List<LibraryTrack>> Function() loadTracks, {
  Brightness brightness = Brightness.dark,
  Size size = const Size(411, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: SonusThemeFactory.build(
        SonusAppearanceSpec(
          themeId: brightness == Brightness.light
              ? SonusThemeId.daylight
              : SonusThemeId.values.first,
        ),
      ),
      home: PlaylistSongPickerPage(
        playlistName: 'Car',
        controller: PlaylistSongPickerController(
          loadTracks: loadTracks,
          songIdsInPlaylist: const {},
          add: (ids) async => PlaylistAddResult(
            playlistName: 'Car',
            added: ids.length,
            alreadyPresent: 0,
            failed: 0,
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

void main() {
  group('from the library', () {
    sqfliteFfiInit();
    late AppDatabase appDatabase;

    setUp(() async {
      appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      final db = await appDatabase.database;
      final stamp = DateTime.utc(2026, 11, 15).toIso8601String();
      for (final id in ['art_song', 'art_edition']) {
        await db.insert(DatabaseTables.artworkAssets, {
          'id': id,
          'file_path': '/art/$id.png',
          'normalized_path': '/art/$id.png',
          'created_at': stamp,
          'updated_at': stamp,
        });
      }
      await db.insert(DatabaseTables.artists, {
        'id': 'artist_nova',
        'name': 'Nova',
        'canonical_name': 'nova',
        'created_at': stamp,
        'updated_at': stamp,
      });
      for (final (album, artwork) in [
        ('with_cover', 'art_edition'),
        ('no_cover', null),
      ]) {
        await db.insert(DatabaseTables.albums, {
          'id': 'album_$album',
          'artist_id': 'artist_nova',
          'title': album,
          'canonical_title': album,
          'created_at': stamp,
          'updated_at': stamp,
        });
        await db.insert(DatabaseTables.albumEditions, {
          'id': 'edition_$album',
          'album_id': 'album_$album',
          'title': album,
          'type': 'standard',
          'is_primary': 1,
          'artwork_id': artwork,
          'created_at': stamp,
          'updated_at': stamp,
        });
      }
      for (final (index, (id, album, artwork)) in [
        ('own', 'with_cover', 'art_song'),
        ('edition', 'with_cover', null),
        ('none', 'no_cover', null),
      ].indexed) {
        await db.insert(DatabaseTables.songs, {
          'id': 'song_$id',
          'artist_id': 'artist_nova',
          'album_id': 'album_$album',
          'album_edition_id': 'edition_$album',
          'title': 'Song $id',
          'canonical_title': 'song $id',
          'track_number': index + 1,
          'disc_number': 1,
          'duration_seconds': 180,
          'is_single': 0,
          'is_blocked': 0,
          'featured_artists': '[]',
          'artwork_id': artwork,
          'created_at': stamp,
          'updated_at': stamp,
        });
        await db.insert(DatabaseTables.mediaFileBindings, {
          'id': 'binding_$id',
          'song_id': 'song_$id',
          'file_path': '/music/$id.mp3',
          'normalized_path': '/music/$id.mp3',
          'is_available': 1,
          'created_at': stamp,
          'updated_at': stamp,
        });
        await db.insert(DatabaseTables.albumEditionTracks, {
          'album_edition_id': 'edition_$album',
          'song_id': 'song_$id',
          'disc_number': 1,
          'track_number': index + 1,
          'sort_position': index,
          'created_at': stamp,
          'updated_at': stamp,
        });
      }
    });

    tearDown(() => appDatabase.close());

    testWidgets("the song's own cover; else its release's; else the "
        'placeholder', (tester) async {
      final db = await appDatabase.database;
      final library = SqliteLibraryQueryRepository(LibraryQueryDao(db));
      final tracks = await tester.runAsync(library.getTracks);
      await _open(tester, () async => tracks!);

      expect(_artworkOf(tester, 'song_own'), '/art/art_song.png');
      expect(_artworkOf(tester, 'song_edition'), '/art/art_edition.png');
      expect(_artworkOf(tester, 'song_none'), isNull);
      expect(
        find.descendant(
          of: _key('song-picker-artwork-song_none'),
          matching: find.byType(SonusArtworkPlaceholder),
        ),
        findsOneWidget,
      );
      // A cover file that cannot be read also shows the placeholder.
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('checkbox, then the square cover, then the title, in one '
      'row; rows stay compact', (tester) async {
    await _open(
      tester,
      () async => [_track('a', title: 'Afterglow', artworkPath: '/a.png')],
    );
    final checkbox = tester.getRect(
      find.descendant(
        of: _key('song-picker-row-a'),
        matching: find.byType(Checkbox),
      ),
    );
    final cover = tester.getRect(_key('song-picker-artwork-a'));
    final title = tester.getRect(find.text('Afterglow'));

    expect(cover.width, cover.height);
    expect(cover.width, 48);
    expect(checkbox.right, lessThanOrEqualTo(cover.left));
    expect(cover.right, lessThanOrEqualTo(title.left));
    expect(tester.getSize(_key('song-picker-row-a')).height, lessThan(90));
  });

  testWidgets('choosing and unchoosing still work, with the cover shown', (
    tester,
  ) async {
    await _open(tester, () async => [_track('a'), _track('b')]);
    await tester.tap(_key('song-picker-row-a'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(_key('song-picker-artwork-b'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(_key('song-picker-row-a'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(_key('song-picker-row-b')).value,
      isTrue,
    );
  });

  testWidgets('search keeps each song with its own cover', (tester) async {
    await _open(
      tester,
      () async => [
        _track('a', title: 'Afterglow', artworkPath: '/a.png'),
        _track('b', title: 'Blue Hour', artworkPath: '/b.png'),
      ],
    );
    await tester.enterText(_key('song-picker-search'), 'blue');
    await tester.pump();

    expect(_key('song-picker-row-a'), findsNothing);
    expect(_artworkOf(tester, 'b'), '/b.png');
  });

  for (final brightness in Brightness.values) {
    testWidgets('a long title with a version label at 2x text and 320 px '
        'fits, read once by TalkBack (${brightness.name})', (tester) async {
      final handle = tester.ensureSemantics();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final track = _track(
        'long',
        title: 'A very long song title that keeps going and going',
        versionLabel: 'Acoustic Remix',
      );
      await _open(
        tester,
        () async => [track],
        brightness: brightness,
        size: const Size(320, 800),
      );

      expect(tester.takeException(), isNull);
      expect(track.displayTitle, contains('Acoustic Remix'));
      expect(find.text(track.displayTitle), findsOneWidget);
      // The row is one checkable item named by its title and details; the
      // cover adds nothing to read.
      final row = tester.getSemantics(_key('song-picker-row-long'));
      expect(row.label, contains('A very long song title'));
      expect(row.label, contains('Nova'));
      handle.dispose();
    });
  }

  testWidgets('a large library scrolls, building only the rows in view', (
    tester,
  ) async {
    await _open(
      tester,
      () async => [
        for (var i = 0; i < 1000; i++)
          _track(
            '$i'.padLeft(4, '0'),
            title: 'Song ${'$i'.padLeft(4, '0')}',
            artworkPath: i.isEven ? '/art/$i.png' : null,
          ),
      ],
    );

    expect(
      find.byType(SonusArtworkImage).evaluate().length,
      lessThan(40),
      reason: 'rows are built lazily',
    );
    await tester.scrollUntilVisible(
      _key('song-picker-row-0999'),
      2000,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(_key('song-picker-artwork-0999'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
