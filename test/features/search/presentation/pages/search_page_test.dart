import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/presentation/pages/album_profile_page.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/search/application/models/library_search_results.dart';
import 'package:sonus_next/features/search/application/repositories/library_search_repository.dart';
import 'package:sonus_next/features/search/presentation/pages/search_page.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

void main() {
  group('SearchPage', () {
    testWidgets('shows initializing state when repository is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(const _SearchTestApp(repository: null));

      expect(
        find.byKey(const ValueKey<String>('search-initializing')),
        findsOneWidget,
      );
    });

    testWidgets('shows search prompt initially', (tester) async {
      final repository = _FakeSearchRepository();

      await tester.pumpWidget(_SearchTestApp(repository: repository));

      expect(
        find.byKey(const ValueKey<String>('search-field')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('search-prompt')),
        findsOneWidget,
      );

      expect(find.text('Search your library'), findsOneWidget);
      expect(repository.queries, isEmpty);
    });

    testWidgets('shows grouped artist album and track results', (tester) async {
      final repository = _FakeSearchRepository(result: _results());

      await tester.pumpWidget(_SearchTestApp(repository: repository));

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'query',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(repository.queries, ['query']);

      expect(
        find.byKey(const ValueKey<String>('search-results')),
        findsOneWidget,
      );

      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Tracks'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('search-artist-artist-1')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('search-album-album-1')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('search-track-song-1')),
        findsOneWidget,
      );

      expect(find.text('Query Artist'), findsOneWidget);
      expect(find.text('Query Album'), findsOneWidget);
      expect(find.text('Query Track'), findsOneWidget);
    });

    testWidgets('shows no-results state', (tester) async {
      final repository = _FakeSearchRepository();

      await tester.pumpWidget(_SearchTestApp(repository: repository));

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'missing',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('search-empty')),
        findsOneWidget,
      );

      expect(find.text('No results for "missing"'), findsOneWidget);
    });

    testWidgets('shows error and retry action when search fails', (
      tester,
    ) async {
      final repository = _FailingThenSuccessfulSearchRepository();

      await tester.pumpWidget(_SearchTestApp(repository: repository));

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'query',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('search-error')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('search-retry-button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('search-retry-button')),
      );

      await tester.pump();
      await tester.pump();

      expect(repository.queries, ['query', 'query']);

      expect(
        find.byKey(const ValueKey<String>('search-results')),
        findsOneWidget,
      );
    });

    testWidgets('clear button resets query and returns to prompt', (
      tester,
    ) async {
      final repository = _FakeSearchRepository(result: _results());

      await tester.pumpWidget(_SearchTestApp(repository: repository));

      final searchField = find.byKey(const ValueKey<String>('search-field'));

      await tester.enterText(searchField, 'query');

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('search-clear-button')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('search-results')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('search-clear-button')),
      );

      await tester.pump();

      final textField = tester.widget<TextField>(searchField);

      expect(textField.controller?.text, isEmpty);

      expect(
        find.byKey(const ValueKey<String>('search-prompt')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('search-clear-button')),
        findsNothing,
      );
    });

    testWidgets('unavailable track is visibly unavailable', (tester) async {
      final repository = _FakeSearchRepository(
        result: LibrarySearchResults(
          tracks: [
            _track(
              songId: 'song-unavailable',
              title: 'Unavailable Track',
              isAvailable: false,
              filePath: null,
            ),
          ],
        ),
      );

      await tester.pumpWidget(_SearchTestApp(repository: repository));

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'unavailable',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('search-track-song-unavailable')),
        findsOneWidget,
      );

      expect(find.text('Query Artist • Unavailable'), findsOneWidget);
    });

    testWidgets('tapping playable track starts playback', (tester) async {
      final engine = _RecordingPlaybackEngine();

      await tester.pumpWidget(
        _SearchTestApp(
          repository: _FakeSearchRepository(result: _results()),
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'query',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('search-track-song-1')),
      );

      await tester.pump();

      expect(engine.loadedQueues, hasLength(1));
      expect(engine.loadedQueues.single, hasLength(1));
      expect(engine.loadedQueues.single.single.songId, 'song-1');
      expect(engine.lastLoadAutoPlay, isTrue);
    });

    testWidgets('play next sends track through playback coordinator', (
      tester,
    ) async {
      final engine = _RecordingPlaybackEngine();

      await tester.pumpWidget(
        _SearchTestApp(
          repository: _FakeSearchRepository(result: _results()),
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'query',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('search-track-menu-song-1')),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Play next'));

      await tester.pumpAndSettle();

      expect(engine.loadedQueues, hasLength(1));
      expect(engine.loadedQueues.single.single.songId, 'song-1');
      expect(engine.lastLoadAutoPlay, isFalse);
    });

    testWidgets('add to queue appends track', (tester) async {
      final engine = _RecordingPlaybackEngine();

      await tester.pumpWidget(
        _SearchTestApp(
          repository: _FakeSearchRepository(result: _results()),
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'query',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('search-track-menu-song-1')),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Add to queue'));

      await tester.pumpAndSettle();

      expect(engine.appendedTracks, hasLength(1));
      expect(engine.appendedTracks.single.songId, 'song-1');
    });

    testWidgets('unavailable track does not invoke playback', (tester) async {
      final engine = _RecordingPlaybackEngine();

      final unavailableTrack = _track(
        songId: 'song-unavailable',
        title: 'Unavailable Track',
        isAvailable: false,
        filePath: null,
      );

      await tester.pumpWidget(
        _SearchTestApp(
          repository: _FakeSearchRepository(
            result: LibrarySearchResults(tracks: [unavailableTrack]),
          ),
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'unavailable',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('search-track-song-unavailable')),
      );

      expect(tile.enabled, isTrue);
      expect(tile.onTap, isNull);

      expect(
        find.byKey(
          const ValueKey<String>('search-track-menu-song-unavailable'),
        ),
        findsOneWidget,
      );

      expect(engine.loadedQueues, isEmpty);
      expect(engine.appendedTracks, isEmpty);
      expect(engine.insertedTracks, isEmpty);
    });

    testWidgets('tapping artist result opens artist profile', (tester) async {
      final queryRepository = _FakeLibraryQueryRepository(
        artist: _results().artists.single,
      );

      await tester.pumpWidget(
        _SearchTestApp(
          repository: _FakeSearchRepository(result: _results()),
          libraryQueryRepository: queryRepository,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'query',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('search-artist-artist-1')),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ArtistProfilePage), findsOneWidget);
    });

    testWidgets('tapping album result opens album profile', (tester) async {
      final queryRepository = _FakeLibraryQueryRepository(
        album: _results().albums.single,
      );

      await tester.pumpWidget(
        _SearchTestApp(
          repository: _FakeSearchRepository(result: _results()),
          libraryQueryRepository: queryRepository,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'query',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('search-album-album-1')),
      );

      await tester.pumpAndSettle();

      expect(find.byType(AlbumProfilePage), findsOneWidget);
    });

    testWidgets('track menu can open artist profile', (tester) async {
      final queryRepository = _FakeLibraryQueryRepository(
        artist: _results().artists.single,
      );

      await tester.pumpWidget(
        _SearchTestApp(
          repository: _FakeSearchRepository(result: _results()),
          libraryQueryRepository: queryRepository,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'query',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('search-track-menu-song-1')),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Go to artist'));

      await tester.pumpAndSettle();

      expect(find.byType(ArtistProfilePage), findsOneWidget);
    });

    testWidgets('track menu can open album profile', (tester) async {
      final queryRepository = _FakeLibraryQueryRepository(
        album: _results().albums.single,
      );

      await tester.pumpWidget(
        _SearchTestApp(
          repository: _FakeSearchRepository(result: _results()),
          libraryQueryRepository: queryRepository,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'query',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('search-track-menu-song-1')),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Go to album'));

      await tester.pumpAndSettle();

      expect(find.byType(AlbumProfilePage), findsOneWidget);
    });

    testWidgets('signed-in search user can block a song', (tester) async {
      final track = _track(songId: 'song-block', title: 'Block Me');

      final accountController = AccountController(
        repository: _FakeAccountRepository(
          currentUser: const AccountUser(
            id: 'user-1',
            email: 'user@example.com',
          ),
        ),
      );

      final service = _FakeSongBlockService();

      await tester.pumpWidget(
        _SearchTestApp(
          repository: _FakeSearchRepository(
            result: LibrarySearchResults(tracks: [track]),
          ),
          accountController: accountController,
          songBlockService: service,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'block',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final menuFinder = find.byKey(
        const ValueKey<String>('search-track-menu-song-block'),
      );

      await tester.tap(menuFinder);
      await tester.pumpAndSettle();

      expect(find.text('Block song'), findsOneWidget);

      await tester.tap(find.text('Block song'));
      await tester.pumpAndSettle();

      expect(service.setBlockedCallCount, 1);
      expect(service.lastUserId, 'user-1');
      expect(service.lastSongId, 'song-block');
      expect(service.lastIsBlocked, isTrue);
    });

    testWidgets('explicitly blocked search song exposes unblock action', (
      tester,
    ) async {
      final track = _track(
        songId: 'song-unblock',
        title: 'Unblock Me',
        isSongBlocked: true,
      );

      final accountController = AccountController(
        repository: _FakeAccountRepository(
          currentUser: const AccountUser(
            id: 'user-1',
            email: 'user@example.com',
          ),
        ),
      );

      final service = _FakeSongBlockService();

      await tester.pumpWidget(
        _SearchTestApp(
          repository: _FakeSearchRepository(
            result: LibrarySearchResults(tracks: [track]),
          ),
          accountController: accountController,
          songBlockService: service,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('search-field')),
        'unblock',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('Query Artist • Blocked'), findsOneWidget);
      expect(find.text('Query Artist • Unavailable'), findsNothing);

      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('search-track-song-unblock')),
      );

      expect(tile.onTap, isNull);

      final menuFinder = find.byKey(
        const ValueKey<String>('search-track-menu-song-unblock'),
      );

      await tester.tap(menuFinder);
      await tester.pumpAndSettle();

      expect(find.text('Unblock song'), findsOneWidget);

      await tester.tap(find.text('Unblock song'));
      await tester.pumpAndSettle();

      expect(service.setBlockedCallCount, 1);
      expect(service.lastUserId, 'user-1');
      expect(service.lastSongId, 'song-unblock');
      expect(service.lastIsBlocked, isFalse);
    });
  });
}

class _SearchTestApp extends StatelessWidget {
  const _SearchTestApp({
    required this.repository,
    this.playbackCoordinator,
    this.libraryQueryRepository,
    this.accountController,
    this.songBlockService,
  });

  final LibrarySearchRepository? repository;
  final PlaybackCoordinator? playbackCoordinator;
  final LibraryQueryRepository? libraryQueryRepository;
  final AccountController? accountController;
  final SongBlockService? songBlockService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<LibrarySearchRepository?>.value(value: repository),
        Provider<PlaybackCoordinator?>.value(value: playbackCoordinator),
        Provider<LibraryQueryRepository?>.value(value: libraryQueryRepository),
        ChangeNotifierProvider<AccountController?>.value(
          value: accountController,
        ),
        Provider<SongBlockService?>.value(value: songBlockService),
      ],
      child: const MaterialApp(home: SearchPage()),
    );
  }
}

class _FakeSearchRepository implements LibrarySearchRepository {
  _FakeSearchRepository({this.result = const LibrarySearchResults()});

  final LibrarySearchResults result;

  final List<String> queries = [];

  @override
  Future<LibrarySearchResults> search(String query) async {
    queries.add(query);
    return result;
  }
}

class _FailingThenSuccessfulSearchRepository
    implements LibrarySearchRepository {
  final List<String> queries = [];

  int _calls = 0;

  @override
  Future<LibrarySearchResults> search(String query) async {
    queries.add(query);
    _calls++;

    if (_calls == 1) {
      throw StateError('search failed');
    }

    return _results();
  }
}

LibrarySearchResults _results() {
  return LibrarySearchResults(
    artists: [
      LibraryArtist(
        artistId: 'artist-1',
        name: 'Query Artist',
        albumCount: 1,
        songCount: 1,
        dateAdded: DateTime.utc(2026, 9, 25),
      ),
    ],
    albums: [
      LibraryAlbum(
        albumId: 'album-1',
        title: 'Query Album',
        artistId: 'artist-1',
        artistName: 'Query Artist',
        trackCount: 1,
        dateAdded: DateTime.utc(2026, 9, 25),
      ),
    ],
    tracks: [_track(songId: 'song-1', title: 'Query Track')],
  );
}

LibraryTrack _track({
  required String songId,
  required String title,
  bool isAvailable = true,
  bool isSongBlocked = false,
  bool isArtistBlacklisted = false,
  String? filePath = r'C:\Music\Query Track.mp3',
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: 'artist-1',
    artistName: 'Query Artist',
    albumId: 'album-1',
    albumTitle: 'Query Album',
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Query Album',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 9, 25),
    isAvailable: isAvailable,
    filePath: filePath,
    isSongBlocked: isSongBlocked,
    isArtistBlacklisted: isArtistBlacklisted,
  );
}

class _FakeSongBlockService extends SongBlockService {
  _FakeSongBlockService() : super(mutationRunner: _UnusedSyncMutationRunner());

  int setBlockedCallCount = 0;
  String? lastUserId;
  String? lastSongId;
  bool? lastIsBlocked;

  @override
  Future<Song> setBlocked({
    required String userId,
    required String songId,
    required bool isBlocked,
    DateTime? now,
  }) async {
    setBlockedCallCount++;
    lastUserId = userId;
    lastSongId = songId;
    lastIsBlocked = isBlocked;

    final timestamp = now ?? DateTime.utc(2026, 1, 1);

    return Song(
      id: songId,
      artistId: 'artist-1',
      albumId: 'album-1',
      albumEditionId: 'edition-1',
      title: 'Song',
      canonicalTitle: 'song',
      trackNumber: 1,
      discNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: const [],
      artworkId: null,
      isBlocked: isBlocked,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({this.currentUser});

  @override
  AccountUser? currentUser;

  @override
  Stream<AccountUser?> watchAuthState() {
    return Stream<AccountUser?>.value(currentUser);
  }

  @override
  Future<AccountUser?> signInWithGoogle() async {
    return currentUser;
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
  }
}

class _UnusedSyncMutationRunner implements SyncMutationRunner {
  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    throw StateError('Sync mutation runner should not be used by this fake.');
  }
}

class _RecordingPlaybackEngine implements PlaybackEngine {
  final List<List<PlaybackTrack>> loadedQueues = [];
  final List<PlaybackTrack> insertedTracks = [];
  final List<PlaybackTrack> appendedTracks = [];

  bool? lastLoadAutoPlay;

  final PlaybackState _state = const PlaybackState();

  @override
  Stream<PlaybackState> get states => const Stream<PlaybackState>.empty();

  @override
  PlaybackState get currentState => _state;

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {
    loadedQueues.add(List<PlaybackTrack>.from(tracks));
    lastLoadAutoPlay = autoPlay;
  }

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {
    insertedTracks.add(track);
  }

  @override
  Future<void> appendTrack(PlaybackTrack track) async {
    appendedTracks.add(track);
  }

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

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({this.artist, this.album});

  final LibraryArtist? artist;
  final LibraryAlbum? album;

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
    return album == null ? const [] : [album!];
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return album == null ? const [] : [album!];
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    if (album?.albumId == albumId) {
      return album;
    }

    return null;
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    if (album?.artistId == artistId) {
      return [album!];
    }

    return const [];
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return artist == null ? const [] : [artist!];
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    if (artist?.artistId == artistId) {
      return artist;
    }

    return null;
  }
}
