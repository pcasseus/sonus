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
import 'package:sonus_next/features/playlists/application/models/playlist_summary.dart';
import 'package:sonus_next/features/playlists/application/services/playlist_service.dart';
import 'package:sonus_next/features/playlists/domain/entities/playlist.dart';
import 'package:sonus_next/features/playlists/domain/entities/playlist_item.dart';
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
}

class _FlowHarness extends StatelessWidget {
  const _FlowHarness({required this.service, required this.track});

  final PlaylistService service;
  final LibraryTrack track;

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
                    unawaited(showAddToPlaylistFlow(context, track));
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
  _FakePlaylistService({List<PlaylistSummary> playlists = const []})
    : _playlists = List<PlaylistSummary>.of(playlists),
      super(
        repository: _UnusedPlaylistRepository(),
        library: _UnusedLibraryQueryRepository(),
        mutationRunner: _UnusedSyncMutationRunner(),
      );

  final List<PlaylistSummary> _playlists;

  int createPlaylistCallCount = 0;
  int addSongCallCount = 0;

  String? lastCreatedName;
  String? lastPlaylistId;
  String? lastSongId;

  int _createdCounter = 0;
  int _itemCounter = 0;

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
  Future<PlaylistItem> addSong({
    required String playlistId,
    required String songId,
    DateTime? now,
  }) async {
    addSongCallCount++;
    lastPlaylistId = playlistId;
    lastSongId = songId;

    _itemCounter++;

    final timestamp = now ?? DateTime.utc(2026, 9, 30, 12);

    return PlaylistItem(
      id: 'playlist_item_fake_$_itemCounter',
      playlistId: playlistId,
      songId: songId,
      position: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
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
    featuredArtists: const [],
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
