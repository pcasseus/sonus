import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/playlists/application/models/playlist_add_result.dart';
import 'package:sonus_next/features/playlists/application/models/playlist_summary.dart';
import 'package:sonus_next/features/playlists/application/services/playlist_service.dart';
import 'package:sonus_next/features/playlists/domain/entities/playlist.dart';
import 'package:sonus_next/features/playlists/domain/repositories/playlist_repository.dart';
import 'package:sonus_next/features/playlists/presentation/widgets/add_to_playlist_sheet.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

void main() {
  testWidgets('adds song to an existing playlist', (tester) async {
    final service = _FakePlaylistService(
      playlists: [_summary(id: 'playlist_existing', name: 'Favorites')],
    );

    await tester.pumpWidget(
      _FlowHarness(
        service: service,
        track: _track(songId: 'song_existing', title: 'Existing Song'),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('open-add-to-playlist')),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey<String>('add-to-playlist-title')),
      findsOneWidget,
    );

    expect(find.text('Favorites'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('add-to-playlist-playlist_existing')),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.addSongCallCount, 1);
    expect(service.lastPlaylistId, 'playlist_existing');
    expect(service.lastSongId, 'song_existing');

    expect(find.text('Added "Existing Song" to Favorites.'), findsOneWidget);
  });

  testWidgets('creates playlist from chooser and immediately adds song', (
    tester,
  ) async {
    final service = _FakePlaylistService();

    await tester.pumpWidget(
      _FlowHarness(
        service: service,
        track: _track(songId: 'song_new_playlist', title: 'New Playlist Song'),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('open-add-to-playlist')),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey<String>('add-to-playlist-new')));

    await tester.pumpAndSettle();

    final nameField = find.byKey(
      const ValueKey<String>('add-to-playlist-name-field'),
    );

    expect(nameField, findsOneWidget);

    await tester.enterText(nameField, 'Road Trip');
    await tester.pump();

    final createButtonFinder = find.widgetWithText(FilledButton, 'Create');

    expect(createButtonFinder, findsOneWidget);

    final createButton = tester.widget<FilledButton>(createButtonFinder);

    expect(createButton.onPressed, isNotNull);

    await tester.tap(createButtonFinder);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.createPlaylistCallCount, 1);
    expect(service.lastCreatedName, 'Road Trip');

    expect(service.addSongCallCount, 1);
    expect(service.lastPlaylistId, 'playlist_created_1');
    expect(service.lastSongId, 'song_new_playlist');

    expect(
      find.text('Added "New Playlist Song" to Road Trip.'),
      findsOneWidget,
    );
  });

  testWidgets('blacklisted unavailable song can still be added to playlist', (
    tester,
  ) async {
    final service = _FakePlaylistService(
      playlists: [_summary(id: 'playlist_keep', name: 'Keep Organized')],
    );

    final track = _track(
      songId: 'song_blocked',
      title: 'Blocked Song',
      isAvailable: false,
      isSongBlocked: true,
      filePath: null,
    );

    expect(track.isAvailable, isFalse);
    expect(track.isBlocked, isTrue);

    await tester.pumpWidget(_FlowHarness(service: service, track: track));

    await tester.tap(
      find.byKey(const ValueKey<String>('open-add-to-playlist')),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(const ValueKey<String>('add-to-playlist-playlist_keep')),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.addSongCallCount, 1);
    expect(service.lastPlaylistId, 'playlist_keep');
    expect(service.lastSongId, 'song_blocked');
  });

  testWidgets('says a song is already in the playlist instead of "Added"', (
    tester,
  ) async {
    final service = _FakePlaylistService(
      playlists: [_summary(id: 'playlist_dupe', name: 'Night Drive')],
      presentSongIds: {'song_dupe'},
    );

    await tester.pumpWidget(
      _FlowHarness(
        service: service,
        track: _track(songId: 'song_dupe', title: 'Paper Lanterns'),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('open-add-to-playlist')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(const ValueKey<String>('add-to-playlist-playlist_dupe')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('"Paper Lanterns" is already in Night Drive.'), findsOne);
    expect(find.textContaining('Added'), findsNothing);
  });

  testWidgets('adds several songs and reports duplicates in one message', (
    tester,
  ) async {
    final service = _FakePlaylistService(
      playlists: [_summary(id: 'playlist_bulk', name: 'Lakeside')],
      presentSongIds: {'song_b', 'song_d'},
    );
    final tracks = [
      for (final id in ['song_a', 'song_b', 'song_c', 'song_d', 'song_e'])
        _track(songId: id, title: 'Title $id'),
    ];

    await tester.pumpWidget(_FlowHarness(service: service, tracks: tracks));

    await tester.tap(
      find.byKey(const ValueKey<String>('open-add-to-playlist')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('5 songs'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('add-to-playlist-playlist_bulk')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.addSongCallCount, 1);
    expect(service.lastSongIds, [
      'song_a',
      'song_b',
      'song_c',
      'song_d',
      'song_e',
    ]);
    expect(
      find.text('Added 3 songs to Lakeside. 2 were already in this playlist.'),
      findsOneWidget,
    );
  });

  testWidgets('SN-50 BUG-02: the sheet names the version and its credits', (
    tester,
  ) async {
    final service = _FakePlaylistService(
      playlists: [_summary(id: 'playlist_existing', name: 'Favorites')],
    );

    await tester.pumpWidget(
      _FlowHarness(
        service: service,
        track: _track(
          songId: 'song_remix',
          title: 'Original Song (Remix)',
          versionLabel: 'Remix',
          featured: const ['Artist A'],
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('open-add-to-playlist')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Original Song (Remix) · Artist Ft. Artist A'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('add-to-playlist-playlist_existing')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Added "Original Song (Remix)" to Favorites.'),
      findsOneWidget,
    );
  });

  test('SN-50 BUG-02: the message uses the display title', () {
    expect(
      addToPlaylistMessage(
        const PlaylistAddResult(
          playlistName: 'Harbor',
          added: 1,
          alreadyPresent: 0,
          failed: 0,
        ),
        [
          _track(
            songId: 'song_alt',
            title: 'Original Song',
            versionLabel: 'Alternate Remix',
          ),
        ],
      ),
      'Added "Original Song (Alternate Remix)" to Harbor.',
    );
  });

  test('bulk message counts songs no longer in the library', () {
    final tracks = [
      _track(songId: 'song_x', title: 'X'),
      _track(songId: 'song_y', title: 'Y'),
    ];

    expect(
      addToPlaylistMessage(
        const PlaylistAddResult(
          playlistName: 'Harbor',
          added: 0,
          alreadyPresent: 1,
          failed: 1,
        ),
        tracks,
      ),
      'No songs were added to Harbor. 1 was already in this playlist. '
      '1 is no longer in your library.',
    );
  });
}

class _FlowHarness extends StatelessWidget {
  const _FlowHarness({required this.service, this.track, this.tracks});

  final PlaylistService service;
  final LibraryTrack? track;
  final List<LibraryTrack>? tracks;

  @override
  Widget build(BuildContext context) {
    return Provider<PlaylistService?>.value(
      value: service,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: FilledButton(
                  key: const ValueKey<String>('open-add-to-playlist'),
                  onPressed: () {
                    final many = tracks;
                    unawaited(
                      many == null
                          ? showAddToPlaylistFlow(context, track!)
                          : showAddTracksToPlaylistFlow(context, many),
                    );
                  },
                  child: const Text('Open chooser'),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FakePlaylistService extends PlaylistService {
  _FakePlaylistService({
    List<PlaylistSummary> playlists = const [],
    this.presentSongIds = const {},
  }) : _playlists = List<PlaylistSummary>.of(playlists),
       super(
         repository: _UnusedPlaylistRepository(),
         library: _UnusedLibraryQueryRepository(),
         mutationRunner: _UnusedSyncMutationRunner(),
       );

  final List<PlaylistSummary> _playlists;
  final Set<String> presentSongIds;

  int createPlaylistCallCount = 0;
  int addSongCallCount = 0;

  String? lastCreatedName;
  String? lastPlaylistId;
  String? lastSongId;
  List<String>? lastSongIds;

  int _createdCounter = 0;

  @override
  Future<List<PlaylistSummary>> getPlaylists() async {
    return List<PlaylistSummary>.unmodifiable(_playlists);
  }

  @override
  Future<Playlist> createPlaylist({required String name, DateTime? now}) async {
    createPlaylistCallCount++;
    lastCreatedName = name;

    _createdCounter++;

    final timestamp = now ?? DateTime.utc(2026, 9, 30, 12);

    final playlist = Playlist(
      id: 'playlist_created_$_createdCounter',
      name: name.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    _playlists.add(PlaylistSummary(playlist: playlist, trackCount: 0));

    return playlist;
  }

  @override
  Future<PlaylistAddResult> addSongs({
    required String playlistId,
    required List<String> songIds,
    DateTime? now,
  }) async {
    addSongCallCount++;
    lastPlaylistId = playlistId;
    lastSongIds = songIds;
    lastSongId = songIds.last;

    final present = songIds.where(presentSongIds.contains).length;

    return PlaylistAddResult(
      playlistName: _playlists
          .firstWhere((summary) => summary.playlist.id == playlistId)
          .playlist
          .name,
      added: songIds.length - present,
      alreadyPresent: present,
      failed: 0,
    );
  }
}

PlaylistSummary _summary({
  required String id,
  required String name,
  int trackCount = 0,
}) {
  final timestamp = DateTime.utc(2026, 9, 30, 12);

  return PlaylistSummary(
    playlist: Playlist(
      id: id,
      name: name,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    trackCount: trackCount,
  );
}

LibraryTrack _track({
  required String songId,
  required String title,
  bool isAvailable = true,
  bool isSongBlocked = false,
  String? filePath = '/music/song.mp3',
  String? versionLabel,
  List<String> featured = const [],
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: 'artist_1',
    artistName: 'Artist',
    albumId: 'album_1',
    albumTitle: 'Album',
    albumEditionId: 'edition_1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: featured,
    versionLabel: versionLabel,
    dateAdded: DateTime.utc(2026, 9, 30),
    filePath: filePath,
    isAvailable: isAvailable,
    isSongBlocked: isSongBlocked,
  );
}

class _UnusedPlaylistRepository implements PlaylistRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('PlaylistRepository should not be used by this fake.');
  }
}

class _UnusedLibraryQueryRepository implements LibraryQueryRepository {
  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return const [];
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async {
    return const [];
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) async {
    return null;
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return const [];
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return const [];
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return const [];
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return const [];
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    return null;
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return const [];
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return const [];
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    return null;
  }
}

class _UnusedSyncMutationRunner implements SyncMutationRunner {
  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    throw StateError('SyncMutationRunner should not be used by this fake.');
  }
}
