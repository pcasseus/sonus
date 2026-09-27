import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/account/presentation/scopes/account_scope.dart';
import 'package:sonus_next/features/library/application/services/artist_blacklist_service.dart';
import 'package:sonus_next/features/library/application/services/artist_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

void main() {
  group('ArtistProfilePage', () {
    testWidgets('shows stable page while repository is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(repository: null));

      expect(
        find.byKey(const ValueKey<String>('artist-profile-page')),
        findsOneWidget,
      );

      expect(find.text('Loading artist...'), findsOneWidget);
    });

    testWidgets('shows loading state while artist is loading', (tester) async {
      final completer = Completer<LibraryArtist?>();

      final repository = FakeLibraryQueryRepository(
        artistLoader: (_) => completer.future,
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(null);

      await tester.pump();
      await tester.pump();
    });

    testWidgets('shows artist profile content', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        albums: [createAlbum()],
        tracks: [createTrack()],
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Test Artist'), findsWidgets);

      expect(find.text('1 album \u2022 1 song'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('artist-profile-albums-grid')),
        findsOneWidget,
      );

      expect(find.text('Test Album'), findsWidgets);

      await tester.drag(
        find.byKey(const PageStorageKey<String>('artist-profile-scroll')),
        const Offset(0, -500),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('artist-profile-tracks-list')),
        findsOneWidget,
      );

      expect(find.text('Test Song'), findsOneWidget);

      expect(find.text('3:00'), findsOneWidget);
    });

    testWidgets('shows empty album and song sections', (tester) async {
      final repository = FakeLibraryQueryRepository(artist: createArtist());

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('No albums yet'), findsOneWidget);

      expect(find.text('No songs yet'), findsOneWidget);
    });

    testWidgets('shows artist not found state', (tester) async {
      final repository = FakeLibraryQueryRepository();

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Artist not found'), findsOneWidget);
    });

    testWidgets('shows error state when loading fails', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artistError: StateError('failed'),
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Could not load this artist.'), findsOneWidget);

      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('retry reloads profile after failure', (tester) async {
      var shouldFail = true;

      final repository = FakeLibraryQueryRepository(
        artistLoader: (_) async {
          if (shouldFail) {
            throw StateError('failed');
          }

          return createArtist(name: 'Recovered Artist');
        },
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Could not load this artist.'), findsOneWidget);

      shouldFail = false;

      await tester.tap(find.text('Try again'));

      await tester.pumpAndSettle();

      expect(find.text('Recovered Artist'), findsWidgets);
    });

    testWidgets('play button plays artist tracks', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [
          createTrack(songId: 'song-1', title: 'First Song'),
          createTrack(songId: 'song-2', title: 'Second Song'),
        ],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.pumpAndSettle();

      final playButton = find.byKey(
        const ValueKey<String>('artist-profile-play-all-button'),
      );

      expect(playButton, findsOneWidget);

      await tester.tap(playButton);
      await tester.pump();

      expect(engine.loadQueueCallCount, 1);

      expect(engine.lastLoadedTracks!.map((track) => track.songId), [
        'song-1',
        'song-2',
      ]);

      expect(engine.lastStartIndex, 0);

      expect(engine.lastAutoPlay, isTrue);

      await engine.dispose();
    });

    testWidgets('shuffle button updates playback shuffle state', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [createTrack()],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.pumpAndSettle();

      final shuffleButton = find.byKey(
        const ValueKey<String>('artist-profile-shuffle-button'),
      );

      expect(shuffleButton, findsOneWidget);

      await tester.tap(shuffleButton);
      await tester.pump();

      expect(engine.lastShuffleEnabled, isTrue);

      await tester.tap(shuffleButton);
      await tester.pump();

      expect(engine.lastShuffleEnabled, isFalse);

      await engine.dispose();
    });

    testWidgets('tapping playable song starts playback', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [createTrack(songId: 'play-song', title: 'Play Song')],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const PageStorageKey<String>('artist-profile-scroll')),
        const Offset(0, -500),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-track-play-song')),
      );

      await tester.pump();

      expect(engine.loadQueueCallCount, 1);

      expect(engine.lastLoadedTracks, hasLength(1));

      expect(engine.lastLoadedTracks!.single.songId, 'play-song');

      expect(engine.lastAutoPlay, isTrue);

      await engine.dispose();
    });

    testWidgets('unavailable song is disabled and does not start playback', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [
          createTrack(
            songId: 'missing-song',
            title: 'Missing Song',
            filePath: '',
            isAvailable: false,
          ),
        ],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Unavailable • Test Album'), findsOneWidget);

      await tester.drag(
        find.byKey(const PageStorageKey<String>('artist-profile-scroll')),
        const Offset(0, -500),
      );

      await tester.pumpAndSettle();

      final tileFinder = find.byKey(
        const ValueKey<String>('artist-track-missing-song'),
      );

      expect(tileFinder, findsOneWidget);

      final tile = tester.widget<ListTile>(tileFinder);

      expect(tile.enabled, isFalse);

      expect(tile.onTap, isNull);

      expect(engine.loadQueueCallCount, 0);

      await engine.dispose();
    });

    testWidgets('unavailable track still exposes metadata editing', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [
          createTrack(
            songId: 'missing-song',
            title: 'Missing Song',
            filePath: '',
            isAvailable: false,
          ),
        ],
      );

      final editingService = TrackProfileEditingService(
        mutationRunner: UnusedSyncMutationRunner(),
      );

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          accountRepository: FakeAccountRepository(
            currentUser: const AccountUser(id: 'user-1'),
          ),
          trackProfileEditingService: editingService,
        ),
      );

      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const PageStorageKey<String>('artist-profile-scroll')),
        const Offset(0, -500),
      );

      await tester.pumpAndSettle();

      final tileFinder = find.byKey(
        const ValueKey<String>('artist-track-missing-song'),
      );

      final tile = tester.widget<ListTile>(tileFinder);
      expect(tile.enabled, isFalse);

      final menuFinder = find.byKey(
        const ValueKey<String>('artist-track-menu-missing-song'),
      );

      expect(
        tester.widget<PopupMenuButton<dynamic>>(menuFinder).enabled,
        isTrue,
      );

      await tester.tap(menuFinder);
      await tester.pumpAndSettle();

      expect(find.text('Edit song details'), findsOneWidget);
    });
    testWidgets('playback controls are disabled when no tracks are playable', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.pumpAndSettle();

      final playButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('artist-profile-play-all-button')),
      );

      expect(playButton.onPressed, isNull);

      final shuffleButton = tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('artist-profile-shuffle-button')),
      );

      expect(shuffleButton.onPressed, isNull);

      await engine.dispose();
    });
  });

  testWidgets('signed-in user can rename artist', (tester) async {
    final repository = FakeLibraryQueryRepository(artist: createArtist());

    final editingService = FakeArtistProfileEditingService(
      onRename: ({required artistId, required name, required userId}) async {
        repository.artist = createArtist(artistId: artistId, name: name.trim());
      },
    );

    await tester.pumpWidget(
      buildSubject(
        repository: repository,
        accountRepository: FakeAccountRepository(
          currentUser: const AccountUser(id: 'user-1'),
        ),
        artistProfileEditingService: editingService,
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('artist-profile-artwork-menu')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit artist name'), findsOneWidget);

    await tester.tap(find.text('Edit artist name'));
    await tester.pumpAndSettle();

    final nameField = find.byKey(const ValueKey<String>('artist-name-field'));

    expect(nameField, findsOneWidget);

    final textField = tester.widget<TextFormField>(nameField);
    expect(textField.controller?.text, 'Test Artist');

    await tester.enterText(nameField, 'Renamed Artist');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(editingService.renameCallCount, 1);
    expect(editingService.lastUserId, 'user-1');
    expect(editingService.lastArtistId, 'artist-1');
    expect(editingService.lastName, 'Renamed Artist');

    expect(find.text('Renamed Artist'), findsWidgets);
    expect(find.text('Artist name updated.'), findsOneWidget);
  });

  testWidgets('artist rename rejects blank name', (tester) async {
    final repository = FakeLibraryQueryRepository(artist: createArtist());

    final editingService = FakeArtistProfileEditingService();

    await tester.pumpWidget(
      buildSubject(
        repository: repository,
        accountRepository: FakeAccountRepository(
          currentUser: const AccountUser(id: 'user-1'),
        ),
        artistProfileEditingService: editingService,
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('artist-profile-artwork-menu')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit artist name'));
    await tester.pumpAndSettle();

    final nameField = find.byKey(const ValueKey<String>('artist-name-field'));

    await tester.enterText(nameField, '   ');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Artist name cannot be blank.'), findsOneWidget);
    expect(editingService.renameCallCount, 0);
  });

  testWidgets('signed-out user cannot rename artist', (tester) async {
    final repository = FakeLibraryQueryRepository(artist: createArtist());

    final editingService = FakeArtistProfileEditingService();

    await tester.pumpWidget(
      buildSubject(
        repository: repository,
        accountRepository: FakeAccountRepository(),
        artistProfileEditingService: editingService,
      ),
    );

    await tester.pumpAndSettle();

    final menu = tester.widget<PopupMenuButton>(
      find.byKey(const ValueKey<String>('artist-profile-artwork-menu')),
    );

    expect(menu.enabled, isFalse);
    expect(editingService.renameCallCount, 0);
  });

  testWidgets('artist rename remains unavailable without account provider', (
    tester,
  ) async {
    final repository = FakeLibraryQueryRepository(artist: createArtist());

    final editingService = FakeArtistProfileEditingService();

    await tester.pumpWidget(
      buildSubject(
        repository: repository,
        artistProfileEditingService: editingService,
      ),
    );

    await tester.pumpAndSettle();

    final menu = tester.widget<PopupMenuButton>(
      find.byKey(const ValueKey<String>('artist-profile-artwork-menu')),
    );

    expect(menu.enabled, isFalse);
    expect(editingService.renameCallCount, 0);
  });

  testWidgets(
    'signed-in user can cancel artist removal without calling service',
    (tester) async {
      final repository = FakeLibraryQueryRepository(artist: createArtist());
      final editingService = FakeArtistProfileEditingService();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          accountRepository: FakeAccountRepository(
            currentUser: const AccountUser(id: 'user-1'),
          ),
          artistProfileEditingService: editingService,
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Remove artist from library'), findsOneWidget);

      await tester.tap(find.text('Remove artist from library'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('artist-remove-confirmation-dialog')),
        findsOneWidget,
      );
      expect(find.text('Remove Test Artist?'), findsOneWidget);
      expect(
        find.text(
          'This removes the artist entry from Sonus. '
          'Your music and audio files will not be deleted.',
        ),
        findsOneWidget,
      );

      expect(editingService.removeCallCount, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(editingService.removeCallCount, 0);
      expect(
        find.byKey(const ValueKey<String>('artist-profile-page')),
        findsOneWidget,
      );
    },
  );

  testWidgets('signed-in user can remove artist after confirmation', (
    tester,
  ) async {
    final repository = FakeLibraryQueryRepository(artist: createArtist());
    final editingService = FakeArtistProfileEditingService();

    await tester.pumpWidget(
      buildSubject(
        repository: repository,
        accountRepository: FakeAccountRepository(
          currentUser: const AccountUser(id: 'user-1'),
        ),
        artistProfileEditingService: editingService,
        wrapArtistInRoute: true,
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('artist-profile-page')),
      findsNothing,
    );

    await tester.tap(find.text('Open artist'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('artist-profile-page')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('artist-profile-artwork-menu')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove artist from library'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('artist-remove-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(editingService.removeCallCount, 1);
    expect(editingService.lastUserId, 'user-1');
    expect(editingService.lastArtistId, 'artist-1');

    expect(
      find.byKey(const ValueKey<String>('artist-profile-page')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('artist-profile-test-host')),
      findsOneWidget,
    );
  });

  testWidgets(
    'referenced artist removal stays on page and explains reassignment',
    (tester) async {
      final repository = FakeLibraryQueryRepository(artist: createArtist());

      final editingService = FakeArtistProfileEditingService(
        onRemove: ({required String artistId, required String userId}) async {
          throw const ArtistStillReferencedException();
        },
      );

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          accountRepository: FakeAccountRepository(
            currentUser: const AccountUser(id: 'user-1'),
          ),
          artistProfileEditingService: editingService,
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();

      // The read model reports 1 album and 1 song. Removal must still be
      // available; the mutation service owns the authoritative reference check.
      expect(find.text('Remove artist from library'), findsOneWidget);

      await tester.tap(find.text('Remove artist from library'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-remove-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(editingService.removeCallCount, 1);
      expect(editingService.lastUserId, 'user-1');
      expect(editingService.lastArtistId, 'artist-1');

      expect(
        find.byKey(const ValueKey<String>('artist-profile-page')),
        findsOneWidget,
      );
      expect(
        find.text(
          'This artist still has songs or albums in your library. '
          'Reassign them before removing the artist.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('unexpected artist removal failure shows generic message', (
    tester,
  ) async {
    final repository = FakeLibraryQueryRepository(artist: createArtist());

    final editingService = FakeArtistProfileEditingService(
      onRemove: ({required String artistId, required String userId}) async {
        throw StateError('boom');
      },
    );

    await tester.pumpWidget(
      buildSubject(
        repository: repository,
        accountRepository: FakeAccountRepository(
          currentUser: const AccountUser(id: 'user-1'),
        ),
        artistProfileEditingService: editingService,
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('artist-profile-artwork-menu')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove artist from library'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('artist-remove-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(editingService.removeCallCount, 1);
    expect(
      find.byKey(const ValueKey<String>('artist-profile-page')),
      findsOneWidget,
    );
    expect(find.text('Could not remove artist.'), findsOneWidget);
  });

  testWidgets('tapping album opens album profile', (tester) async {
    final repository = FakeLibraryQueryRepository(
      artist: createArtist(),
      albums: [createAlbum()],
      tracks: [createTrack()],
    );

    await tester.pumpWidget(buildSubject(repository: repository));

    await tester.pumpAndSettle();

    final albumCard = find.byKey(
      const ValueKey<String>('artist-album-album-1'),
    );

    expect(albumCard, findsOneWidget);

    await tester.tap(albumCard);

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('album-profile-page')),
      findsOneWidget,
    );

    expect(find.text('Test Album'), findsWidgets);
  });
  testWidgets('blocked artist track remains unblockable from its menu', (
    tester,
  ) async {
    final repository = FakeLibraryQueryRepository(
      artist: createArtist(),
      tracks: [
        createTrack(
          songId: 'blocked-song',
          title: 'Blocked Song',
          isSongBlocked: true,
        ),
      ],
    );

    final accountRepository = FakeAccountRepository(
      currentUser: const AccountUser(id: 'user-1', email: 'user@example.com'),
    );

    final service = FakeSongBlockService();

    await tester.pumpWidget(
      buildSubject(
        repository: repository,
        accountRepository: accountRepository,
        songBlockService: service,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Blocked • Test Album'), findsOneWidget);
    expect(find.text('Unavailable • Test Album'), findsNothing);

    final menuFinder = find.byKey(
      const ValueKey<String>('artist-track-menu-blocked-song'),
    );

    expect(tester.widget<PopupMenuButton<dynamic>>(menuFinder).enabled, isTrue);

    await tester.tap(menuFinder);
    await tester.pumpAndSettle();

    expect(find.text('Unblock song'), findsOneWidget);

    await tester.tap(find.text('Unblock song'));
    await tester.pumpAndSettle();

    expect(service.setBlockedCallCount, 1);
    expect(service.lastUserId, 'user-1');
    expect(service.lastSongId, 'blocked-song');
    expect(service.lastIsBlocked, isFalse);
  });

  testWidgets('signed-in user can block artist from profile menu', (
    tester,
  ) async {
    final repository = FakeLibraryQueryRepository(
      artist: createArtist(),
      tracks: [createTrack()],
    );

    final accountRepository = FakeAccountRepository(
      currentUser: const AccountUser(id: 'user-1', email: 'user@example.com'),
    );

    final service = FakeArtistBlacklistService();

    await tester.pumpWidget(
      buildSubject(
        repository: repository,
        accountRepository: accountRepository,
        artistBlacklistService: service,
      ),
    );

    await tester.pumpAndSettle();

    final menuFinder = find.byKey(
      const ValueKey<String>('artist-profile-artwork-menu'),
    );

    expect(tester.widget<PopupMenuButton<dynamic>>(menuFinder).enabled, isTrue);

    await tester.tap(menuFinder);
    await tester.pumpAndSettle();

    expect(find.text('Block artist'), findsOneWidget);

    await tester.tap(find.text('Block artist'));
    await tester.pumpAndSettle();

    expect(service.setBlacklistedCallCount, 1);
    expect(service.lastUserId, 'user-1');
    expect(service.lastArtistId, 'artist-1');
    expect(service.lastIsBlacklisted, isTrue);
  });

  testWidgets('blacklisted artist can be unblocked from profile menu', (
    tester,
  ) async {
    final repository = FakeLibraryQueryRepository(
      artist: createArtist(isBlacklisted: true),
      tracks: [createTrack(isArtistBlacklisted: true)],
    );

    final accountRepository = FakeAccountRepository(
      currentUser: const AccountUser(id: 'user-1', email: 'user@example.com'),
    );

    final service = FakeArtistBlacklistService();

    await tester.pumpWidget(
      buildSubject(
        repository: repository,
        accountRepository: accountRepository,
        artistBlacklistService: service,
      ),
    );

    await tester.pumpAndSettle();

    final menuFinder = find.byKey(
      const ValueKey<String>('artist-profile-artwork-menu'),
    );

    await tester.tap(menuFinder);
    await tester.pumpAndSettle();

    expect(find.text('Unblock artist'), findsOneWidget);

    await tester.tap(find.text('Unblock artist'));
    await tester.pumpAndSettle();

    expect(service.setBlacklistedCallCount, 1);
    expect(service.lastUserId, 'user-1');
    expect(service.lastArtistId, 'artist-1');
    expect(service.lastIsBlacklisted, isFalse);
  });
}

Widget buildSubject({
  required LibraryQueryRepository? repository,
  PlaybackCoordinator? playbackCoordinator,
  AccountRepository? accountRepository,
  ArtistProfileEditingService? artistProfileEditingService,
  ArtistBlacklistService? artistBlacklistService,
  TrackProfileEditingService? trackProfileEditingService,
  SongBlockService? songBlockService,
  bool wrapArtistInRoute = false,
}) {
  final app = wrapArtistInRoute
      ? MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                key: const ValueKey<String>('artist-profile-test-host'),
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ArtistProfilePage(
                            artistId: 'artist-1',
                            initialArtistName: 'Test Artist',
                          ),
                        ),
                      );
                    },
                    child: const Text('Open artist'),
                  ),
                ),
              );
            },
          ),
        )
      : const MaterialApp(
          home: ArtistProfilePage(
            artistId: 'artist-1',
            initialArtistName: 'Test Artist',
          ),
        );

  return Provider<LibraryQueryRepository?>.value(
    value: repository,
    child: Provider<PlaybackCoordinator?>.value(
      value: playbackCoordinator,
      child: Provider<ArtistProfileEditingService?>.value(
        value: artistProfileEditingService,
        child: Provider<TrackProfileEditingService?>.value(
          value: trackProfileEditingService,
          child: Provider<ArtistBlacklistService?>.value(
            value: artistBlacklistService,
            child: Provider<SongBlockService?>.value(
              value: songBlockService,
              child: AccountScope(repository: accountRepository, child: app),
            ),
          ),
        ),
      ),
    ),
  );
}

LibraryArtist createArtist({
  String artistId = 'artist-1',
  String name = 'Test Artist',
  bool isBlacklisted = false,
}) {
  return LibraryArtist(
    artistId: artistId,
    name: name,
    albumCount: 1,
    songCount: 1,
    isBlacklisted: isBlacklisted,
    dateAdded: DateTime(2026, 1, 1),
  );
}

LibraryAlbum createAlbum() {
  return LibraryAlbum(
    albumId: 'album-1',
    title: 'Test Album',
    artistId: 'artist-1',
    artistName: 'Test Artist',
    trackCount: 1,
    dateAdded: DateTime(2026, 1, 1),
  );
}

LibraryTrack createTrack({
  String songId = 'song-1',
  String title = 'Test Song',
  String? filePath,
  bool isAvailable = true,
  bool isSongBlocked = false,
  bool isArtistBlacklisted = false,
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: 'artist-1',
    artistName: 'Test Artist',
    albumId: 'album-1',
    albumTitle: 'Test Album',
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.values.first,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026, 1, 1),
    filePath: filePath ?? '/music/$songId.mp3',
    isAvailable: isAvailable,
    isSongBlocked: isSongBlocked,
    isArtistBlacklisted: isArtistBlacklisted,
  );
}

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  FakeLibraryQueryRepository({
    this.artist,
    this.albums = const [],
    this.tracks = const [],
    this.artistError,
    this.artistLoader,
  });

  LibraryArtist? artist;
  final List<LibraryAlbum> albums;
  final List<LibraryTrack> tracks;
  final Object? artistError;

  final Future<LibraryArtist?> Function(String artistId)? artistLoader;

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    final loader = artistLoader;

    if (loader != null) {
      return loader(artistId);
    }

    final error = artistError;

    if (error != null) {
      throw error;
    }

    return artist;
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return albums;
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks;
  }

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
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return tracks.where((track) => track.albumId == albumId).toList();
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
    for (final album in albums) {
      if (album.albumId == albumId) {
        return album;
      }
    }

    return null;
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return const [];
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

class FakeArtistBlacklistService extends ArtistBlacklistService {
  FakeArtistBlacklistService()
    : super(mutationRunner: UnusedSyncMutationRunner());

  int setBlacklistedCallCount = 0;
  String? lastUserId;
  String? lastArtistId;
  bool? lastIsBlacklisted;

  @override
  Future<Artist> setBlacklisted({
    required String userId,
    required String artistId,
    required bool isBlacklisted,
    DateTime? now,
  }) async {
    setBlacklistedCallCount++;
    lastUserId = userId;
    lastArtistId = artistId;
    lastIsBlacklisted = isBlacklisted;

    final timestamp = now ?? DateTime.utc(2026, 1, 1);

    return Artist(
      id: artistId,
      name: 'Test Artist',
      canonicalName: 'test artist',
      isBlacklisted: isBlacklisted,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }
}

class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({this.currentUser});

  @override
  AccountUser? currentUser;

  final StreamController<AccountUser?> _authStateController =
      StreamController<AccountUser?>.broadcast();

  @override
  Stream<AccountUser?> watchAuthState() {
    return _authStateController.stream;
  }

  @override
  Future<AccountUser?> signInWithGoogle() async {
    return currentUser;
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
    _authStateController.add(null);
  }
}

typedef FakeArtistRenameCallback =
    Future<void> Function({
      required String userId,
      required String artistId,
      required String name,
    });

typedef FakeArtistRemoveCallback =
    Future<void> Function({required String userId, required String artistId});

class FakeArtistProfileEditingService extends ArtistProfileEditingService {
  FakeArtistProfileEditingService({this.onRename, this.onRemove})
    : super(mutationRunner: UnusedSyncMutationRunner());

  final FakeArtistRenameCallback? onRename;
  final FakeArtistRemoveCallback? onRemove;

  int renameCallCount = 0;
  int removeCallCount = 0;
  String? lastUserId;
  String? lastArtistId;
  String? lastName;

  @override
  Future<void> removeArtist({
    required String userId,
    required String artistId,
  }) async {
    removeCallCount++;
    lastUserId = userId;
    lastArtistId = artistId;

    await onRemove?.call(userId: userId, artistId: artistId);
  }

  @override
  Future<Artist> renameArtist({
    required String userId,
    required String artistId,
    required String name,
    DateTime? now,
  }) async {
    renameCallCount++;
    lastUserId = userId;
    lastArtistId = artistId;
    lastName = name;

    await onRename?.call(userId: userId, artistId: artistId, name: name);

    final timestamp = now ?? DateTime.utc(2026, 1, 1);
    final trimmedName = name.trim();

    return Artist(
      id: artistId,
      name: trimmedName,
      canonicalName: trimmedName.toLowerCase(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }
}

class UnusedSyncMutationRunner implements SyncMutationRunner {
  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    throw StateError('Sync mutation runner should not be used by this fake.');
  }
}

class FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _statesController =
      StreamController<PlaybackState>.broadcast();

  PlaybackState _currentState = const PlaybackState();

  List<PlaybackTrack>? lastLoadedTracks;
  int? lastStartIndex;
  bool? lastAutoPlay;

  bool? lastShuffleEnabled;

  int loadQueueCallCount = 0;

  @override
  Stream<PlaybackState> get states {
    return _statesController.stream;
  }

  @override
  PlaybackState get currentState {
    return _currentState;
  }

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {
    loadQueueCallCount++;

    lastLoadedTracks = List<PlaybackTrack>.from(tracks);

    lastStartIndex = startIndex;
    lastAutoPlay = autoPlay;
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    lastShuffleEnabled = enabled;

    _currentState = _currentState.copyWith(shuffleEnabled: enabled);
  }

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {}

  @override
  Future<void> appendTrack(PlaybackTrack track) async {}

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
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _statesController.close();
  }
}
