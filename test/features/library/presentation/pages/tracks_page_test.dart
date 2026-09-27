import 'dart:async';

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
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/presentation/pages/tracks_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

void main() {
  group('TracksPage', () {
    testWidgets(
      'shows stable tracks destination while repository is unavailable',
      (tester) async {
        await tester.pumpWidget(buildSubject(repository: null));

        expect(
          find.byKey(const ValueKey<String>('app-destination-tracks')),
          findsOneWidget,
        );
        expect(find.text('Loading tracks...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('shows loading state while tracks are loading', (tester) async {
      final completer = Completer<List<LibraryTrack>>();

      final repository = FakeLibraryQueryRepository(
        tracksLoader: (_) => completer.future,
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('app-destination-tracks')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(const []);

      await tester.pump();
      await tester.pump();
    });

    testWidgets('shows empty state when there are no tracks', (tester) async {
      final repository = FakeLibraryQueryRepository(tracks: const []);

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('No tracks yet'), findsOneWidget);
      expect(
        find.text('Import music to start building your library.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.library_music_rounded), findsOneWidget);
    });

    testWidgets('shows error state when track loading fails', (tester) async {
      final repository = FakeLibraryQueryRepository(
        tracksError: StateError('track load failed'),
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Could not load your tracks.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets(
      'renders redesigned tracks destination and metadata hierarchy',
      (tester) async {
        final repository = FakeLibraryQueryRepository(
          tracks: [
            createTrack(
              songId: 'song-1',
              title: 'First Song',
              artistName: 'First Artist',
              albumTitle: 'First Album',
              trackNumber: 1,
              durationSeconds: 245,
            ),
            createTrack(
              songId: 'song-2',
              title: 'Second Song',
              artistName: 'Second Artist',
              albumTitle: 'Second Album',
              trackNumber: 2,
              durationSeconds: 62,
            ),
          ],
        );

        await tester.pumpWidget(buildSubject(repository: repository));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('tracks-page-title')),
          findsOneWidget,
        );
        expect(find.text('Tracks'), findsOneWidget);

        expect(
          find.byKey(const ValueKey<String>('tracks-count-label')),
          findsOneWidget,
        );
        expect(find.text('2 songs in your library'), findsOneWidget);

        expect(find.text('First Song'), findsOneWidget);
        expect(find.text('Second Song'), findsOneWidget);

        expect(find.text('First Artist'), findsOneWidget);
        expect(find.text('Second Artist'), findsOneWidget);

        expect(find.text('First Album'), findsOneWidget);
        expect(find.text('Second Album'), findsOneWidget);

        expect(find.text('4:05'), findsOneWidget);
        expect(find.text('1:02'), findsOneWidget);

        expect(
          find.byKey(const ValueKey<String>('tracks-order-dropdown')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('tracks-shuffle-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('tracks-play-all-button')),
          findsOneWidget,
        );

        expect(find.text('Play all'), findsOneWidget);
        expect(find.text('Shuffle'), findsOneWidget);

        expect(find.byIcon(Icons.music_note_rounded), findsNWidgets(2));
      },
    );

    testWidgets('shows singular song count for one track', (tester) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [createTrack(songId: 'song-1', title: 'Only Song')],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('1 song in your library'), findsOneWidget);
    });

    testWidgets('marks unavailable tracks as non-playable', (tester) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [
          createTrack(songId: 'available', title: 'Available Song'),
          createTrack(
            songId: 'unavailable',
            title: 'Unavailable Song',
            isAvailable: false,
            filePath: null,
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      final availableTile = tester.widget<InkWell>(
        find.byKey(const ValueKey<String>('track-available')),
      );

      final unavailableTile = tester.widget<InkWell>(
        find.byKey(const ValueKey<String>('track-unavailable')),
      );

      expect(availableTile.onTap, isNotNull);
      expect(unavailableTile.onTap, isNull);

      expect(
        find.byKey(const ValueKey<String>('track-unavailable-unavailable')),
        findsOneWidget,
      );
      expect(find.text('Unavailable'), findsOneWidget);

      expect(
        tester
            .widget<PopupMenuButton<dynamic>>(
              find.byKey(const ValueKey<String>('track-menu-unavailable')),
            )
            .enabled,
        isFalse,
      );
    });

    testWidgets('unavailable track still exposes metadata editing', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [
          createTrack(
            songId: 'unavailable',
            title: 'Unavailable Song',
            isAvailable: false,
            filePath: null,
          ),
        ],
      );

      final accountController = AccountController(
        repository: FakeAccountRepository(
          currentUser: const AccountUser(
            id: 'user-1',
            email: 'user@example.com',
          ),
        ),
      );

      final editingService = TrackProfileEditingService(
        mutationRunner: UnusedSyncMutationRunner(),
      );

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          accountController: accountController,
          trackProfileEditingService: editingService,
        ),
      );

      await tester.pumpAndSettle();

      final tile = tester.widget<InkWell>(
        find.byKey(const ValueKey<String>('track-unavailable')),
      );

      expect(tile.onTap, isNull);

      final menuFinder = find.byKey(
        const ValueKey<String>('track-menu-unavailable'),
      );

      expect(
        tester.widget<PopupMenuButton<dynamic>>(menuFinder).enabled,
        isTrue,
      );

      await tester.tap(menuFinder);
      await tester.pumpAndSettle();

      expect(find.text('Edit song details'), findsOneWidget);
    });

    testWidgets('changing order reloads tracks using selected order', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [createTrack(songId: 'song-1', title: 'Song')],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(repository.requestedOrders, [LibraryTrackOrder.title]);

      await tester.tap(
        find.byKey(const ValueKey<String>('tracks-order-dropdown')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Artist name').last);
      await tester.pumpAndSettle();

      expect(repository.requestedOrders, [
        LibraryTrackOrder.title,
        LibraryTrackOrder.artist,
      ]);
    });

    testWidgets('play all loads the playable library queue', (tester) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [
          createTrack(songId: 'song-1', title: 'First Song'),
          createTrack(
            songId: 'missing',
            title: 'Missing Song',
            isAvailable: false,
            filePath: null,
          ),
          createTrack(songId: 'song-2', title: 'Second Song'),
        ],
      );

      final engine = RecordingPlaybackEngine();

      await tester.pumpWidget(
        buildSubject(repository: repository, engine: engine),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('tracks-play-all-button')),
      );
      await tester.pumpAndSettle();

      expect(engine.loadQueueCalls, 1);
      expect(engine.lastLoadedSongIds, ['song-1', 'song-2']);
      expect(engine.lastStartIndex, 0);
      expect(engine.lastAutoPlay, isTrue);
    });

    testWidgets('shuffle control updates playback engine and presentation', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [
          createTrack(songId: 'song-1', title: 'First Song'),
          createTrack(songId: 'song-2', title: 'Second Song'),
        ],
      );

      final engine = RecordingPlaybackEngine();

      await tester.pumpWidget(
        buildSubject(repository: repository, engine: engine),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('Shuffle on'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('tracks-shuffle-button')),
      );
      await tester.pumpAndSettle();

      expect(engine.shuffleValues, [true]);
      expect(find.text('Shuffle on'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('tracks-shuffle-button')),
      );
      await tester.pumpAndSettle();

      expect(engine.shuffleValues, [true, false]);
      expect(find.text('Shuffle'), findsOneWidget);
    });

    testWidgets('retry reloads tracks after an error', (tester) async {
      var shouldFail = true;

      final repository = FakeLibraryQueryRepository(
        tracksLoader: (_) async {
          if (shouldFail) {
            throw StateError('failed');
          }

          return [createTrack(songId: 'song-1', title: 'Recovered Song')];
        },
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Could not load your tracks.'), findsOneWidget);

      shouldFail = false;

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Recovered Song'), findsOneWidget);
      expect(find.text('1 song in your library'), findsOneWidget);
    });

    testWidgets('signed-in user can block a song from the track menu', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [createTrack(songId: 'song-block', title: 'Block Me')],
      );

      final accountController = AccountController(
        repository: FakeAccountRepository(
          currentUser: const AccountUser(
            id: 'user-1',
            email: 'user@example.com',
          ),
        ),
      );

      final service = FakeSongBlockService();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          accountController: accountController,
          songBlockService: service,
        ),
      );

      await tester.pumpAndSettle();

      final menuFinder = find.byKey(
        const ValueKey<String>('track-menu-song-block'),
      );

      expect(
        tester.widget<PopupMenuButton<dynamic>>(menuFinder).enabled,
        isTrue,
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
      expect(find.text('Song blocked.'), findsOneWidget);
    });

    testWidgets(
      'explicitly blocked song can be unblocked from the track menu',
      (tester) async {
        final repository = FakeLibraryQueryRepository(
          tracks: [
            createTrack(
              songId: 'song-unblock',
              title: 'Unblock Me',
              isSongBlocked: true,
            ),
          ],
        );

        final accountController = AccountController(
          repository: FakeAccountRepository(
            currentUser: const AccountUser(
              id: 'user-1',
              email: 'user@example.com',
            ),
          ),
        );

        final service = FakeSongBlockService();

        await tester.pumpWidget(
          buildSubject(
            repository: repository,
            accountController: accountController,
            songBlockService: service,
          ),
        );

        await tester.pumpAndSettle();

        final tile = tester.widget<InkWell>(
          find.byKey(const ValueKey<String>('track-song-unblock')),
        );

        expect(tile.onTap, isNull);

        expect(
          find.byKey(const ValueKey<String>('track-blocked-song-unblock')),
          findsOneWidget,
        );
        expect(find.text('Blocked'), findsOneWidget);
        expect(find.text('Unavailable'), findsNothing);

        final menuFinder = find.byKey(
          const ValueKey<String>('track-menu-song-unblock'),
        );

        expect(
          tester.widget<PopupMenuButton<dynamic>>(menuFinder).enabled,
          isTrue,
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
        expect(find.text('Song unblocked.'), findsOneWidget);
      },
    );
  });
}

Widget buildSubject({
  required LibraryQueryRepository? repository,
  AccountController? accountController,
  TrackProfileEditingService? trackProfileEditingService,
  SongBlockService? songBlockService,
  PlaybackEngine? engine,
}) {
  final playbackEngine = engine ?? NoOpPlaybackEngine();

  final coordinator = PlaybackCoordinator(engine: playbackEngine);

  return MultiProvider(
    providers: [
      Provider<LibraryQueryRepository?>.value(value: repository),
      ChangeNotifierProvider<AccountController?>.value(
        value: accountController,
      ),
      Provider<TrackProfileEditingService?>.value(
        value: trackProfileEditingService,
      ),
      Provider<SongBlockService?>.value(value: songBlockService),
      Provider<PlaybackCoordinator>.value(value: coordinator),
    ],
    child: const MaterialApp(home: Scaffold(body: TracksPage())),
  );
}

LibraryTrack createTrack({
  required String songId,
  required String title,
  String artistId = 'artist-1',
  String artistName = 'Artist',
  String albumId = 'album-1',
  String albumTitle = 'Album',
  String albumEditionId = 'edition-1',
  String albumEditionTitle = 'Standard',
  int trackNumber = 1,
  int durationSeconds = 180,
  bool isSingle = false,
  List<String> featuredArtists = const [],
  DateTime? dateAdded,
  String? filePath = '/music/song.mp3',
  bool isAvailable = true,
  bool isSongBlocked = false,
  bool isArtistBlacklisted = false,
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: artistId,
    artistName: artistName,
    albumId: albumId,
    albumTitle: albumTitle,
    albumEditionId: albumEditionId,
    albumEditionTitle: albumEditionTitle,
    albumEditionType: AlbumEditionType.values.first,
    trackNumber: trackNumber,
    durationSeconds: durationSeconds,
    isSingle: isSingle,
    featuredArtists: featuredArtists,
    dateAdded: dateAdded ?? DateTime(2026, 1, 1),
    filePath: filePath,
    isAvailable: isAvailable,
    isSongBlocked: isSongBlocked,
    isArtistBlacklisted: isArtistBlacklisted,
  );
}

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  FakeLibraryQueryRepository({
    this.tracks = const [],
    this.tracksError,
    this.tracksLoader,
  });

  final List<LibraryTrack> tracks;
  final Object? tracksError;

  final Future<List<LibraryTrack>> Function(LibraryTrackOrder order)?
  tracksLoader;

  final List<LibraryTrackOrder> requestedOrders = [];

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    requestedOrders.add(order);

    final loader = tracksLoader;

    if (loader != null) {
      return loader(order);
    }

    final error = tracksError;

    if (error != null) {
      throw error;
    }

    return tracks;
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return const [];
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
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
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return const [];
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    return null;
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
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return const [];
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return const [];
  }
}

class NoOpPlaybackEngine implements PlaybackEngine {
  @override
  Stream<PlaybackState> get states => const Stream.empty();

  @override
  PlaybackState get currentState => const PlaybackState();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class RecordingPlaybackEngine implements PlaybackEngine {
  final List<bool> shuffleValues = [];

  int loadQueueCalls = 0;
  List<String> lastLoadedSongIds = const [];
  int lastStartIndex = 0;
  bool lastAutoPlay = true;

  @override
  Stream<PlaybackState> get states => const Stream.empty();

  @override
  Future<void> loadQueue(
    dynamic tracks, {
    int startIndex = 0,
    bool autoPlay = true,
  }) async {
    loadQueueCalls += 1;
    lastStartIndex = startIndex;
    lastAutoPlay = autoPlay;

    final iterable = tracks as Iterable<dynamic>;

    lastLoadedSongIds = iterable
        .map<String>((track) => track.songId as String)
        .toList(growable: false);
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    shuffleValues.add(enabled);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class FakeSongBlockService extends SongBlockService {
  FakeSongBlockService() : super(mutationRunner: UnusedSyncMutationRunner());

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

class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({this.currentUser});

  @override
  final AccountUser? currentUser;

  @override
  Stream<AccountUser?> watchAuthState() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class UnusedSyncMutationRunner implements SyncMutationRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('Sync mutation runner should not be used by this test.');
  }

  PlaybackState get currentState => const PlaybackState();
}
