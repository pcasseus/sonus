import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/account/presentation/scopes/account_scope.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_application_service.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_proposal_service.dart';
import 'package:sonus_next/features/library/application/services/metadata_provider.dart';
import 'package:sonus_next/features/library/application/services/artist_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
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

      // SN-48I: the full Songs section is gone; songs are reached through
      // Top Tracks, albums and Collaborations.
      expect(find.text('Songs'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('artist-track-list')),
        findsNothing,
      );
      expect(find.text('Test Song'), findsNothing);
    });

    testWidgets(
      'keeps owned album visible when available track has another primary artist',
      (tester) async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          albums: [createAlbum()],
          tracks: const [],
          allTracks: [
            createTrack(
              songId: 'album-owner-song',
              title: 'Album Owner Song',
              artistId: 'other-artist',
            ),
          ],
        );

        await tester.pumpWidget(buildSubject(repository: repository));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('artist-album-album-1')),
          findsOneWidget,
        );

        expect(
          find.byKey(const ValueKey<String>('artist-track-album-owner-song')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'shows Collaborations when the artist is a featured performer',
      (tester) async {
        final primaryTrack = createTrack(
          songId: 'primary-song',
          title: 'Primary Song',
        );

        final featuredTrack = createTrack(
          songId: 'featured-song',
          title: 'Featured Song',
          artistId: 'other-artist',
          featuredArtists: const ['Test Artist'],
        );

        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          albums: [createAlbum()],
          tracks: [primaryTrack],
          allTracks: [primaryTrack, featuredTrack],
        );

        await tester.pumpWidget(buildSubject(repository: repository));
        await tester.pumpAndSettle();

        await tester.drag(
          find.byKey(const PageStorageKey<String>('artist-profile-scroll')),
          const Offset(0, -900),
        );
        await tester.pumpAndSettle();

        expect(find.text('Songs'), findsNothing);
        expect(find.text('Featured On'), findsNothing);
        expect(find.text('Collaborations'), findsOneWidget);
        expect(find.text('Featured Song'), findsOneWidget);
        // Their own song on their own album is not a collaboration.
        expect(find.text('Primary Song'), findsNothing);
      },
    );

    testWidgets('shows no empty sections (SN-45)', (tester) async {
      final repository = FakeLibraryQueryRepository(artist: createArtist());

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('No albums yet'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('artist-profile-albums')),
        findsNothing,
      );

      expect(find.text('Songs'), findsNothing);
      expect(find.text('Top Tracks'), findsNothing);
      expect(find.text('Collaborations'), findsNothing);
      expect(find.text('Collaborators'), findsNothing);
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

    testWidgets('tapping a top track starts playback', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        albums: [createAlbum()],
        tracks: [createTrack(songId: 'play-song', title: 'Play Song')],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
          qualifiedPlays: FakeQualifiedPlayRepository([
            qualifiedPlay('play-song'),
          ]),
        ),
      );

      await tester.pumpAndSettle();

      final row = find.byKey(
        const ValueKey<String>('artist-top-track-play-song'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);

      await tester.pump();

      expect(engine.loadQueueCallCount, 1);

      expect(engine.lastLoadedTracks, hasLength(1));

      expect(engine.lastLoadedTracks!.single.songId, 'play-song');

      expect(engine.lastAutoPlay, isTrue);

      await engine.dispose();
    });

    testWidgets('a streamed but unavailable song stays in Top Tracks, '
        'labelled and not playable', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        albums: [createAlbum()],
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
          qualifiedPlays: FakeQualifiedPlayRepository([
            qualifiedPlay('missing-song'),
            qualifiedPlay('missing-song'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(
        const ValueKey<String>('artist-top-track-missing-song'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();

      expect(find.text('Unavailable • 2 streams • Test Album'), findsOneWidget);
      expect(tester.widget<ListTile>(row).enabled, isFalse);

      await tester.tap(row, warnIfMissed: false);
      await tester.pump();
      expect(engine.loadQueueCallCount, 0);

      await engine.dispose();
    });

    testWidgets('an unavailable collaboration is not listed', (tester) async {
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

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('artist-track-missing-song')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('artist-track-menu-missing-song')),
        findsNothing,
      );
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

  testWidgets('signed-out user can rename artist locally', (tester) async {
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

    expect(menu.enabled, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('artist-profile-artwork-menu')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit artist name'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('artist-name-field')),
      'Anonymous Rename',
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(editingService.renameCallCount, 1);
    expect(editingService.lastUserId, isNull);
    expect(editingService.lastArtistId, 'artist-1');
    expect(editingService.lastName, 'Anonymous Rename');
  });

  testWidgets('artist editing remains available without account provider', (
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

    expect(menu.enabled, isTrue);
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
        onRemove: ({required String artistId, required String? userId}) async {
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
      onRemove: ({required String artistId, required String? userId}) async {
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
  testWidgets('blacklisted song remains removable from the artist track menu', (
    tester,
  ) async {
    // A main credit on another artist's album: listed under Collaborations.
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

    expect(find.text('Blacklisted • Test Album'), findsOneWidget);
    expect(find.text('Unavailable • Test Album'), findsNothing);

    final menuFinder = find.byKey(
      const ValueKey<String>('artist-track-menu-blocked-song'),
    );

    expect(tester.widget<PopupMenuButton<dynamic>>(menuFinder).enabled, isTrue);

    await tester.tap(menuFinder);
    await tester.pumpAndSettle();

    expect(find.text('Remove from blacklist'), findsOneWidget);

    await tester.tap(find.text('Remove from blacklist'));
    await tester.pumpAndSettle();

    expect(service.setBlockedCallCount, 1);
    expect(service.lastUserId, 'user-1');
    expect(service.lastSongId, 'blocked-song');
    expect(service.lastIsBlocked, isFalse);
  });

  testWidgets(
    'Artist Track Studio forwards MusicBrainz dependencies and track query',
    (tester) async {
      final provider = FakeArtistTrackMetadataProvider();
      final applicationService = FakeArtistTrackMetadataApplicationService();
      final proposalService = FakeArtistTrackMetadataProposalService();

      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        albums: [createAlbum()],
        tracks: [
          createTrack(
            songId: 'musicbrainz-artist-track',
            title: 'Artist Studio Song',
          ),
        ],
      );

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          accountRepository: FakeAccountRepository(
            currentUser: const AccountUser(id: 'user-1'),
          ),
          trackProfileEditingService: EnabledTrackStudioEditingService(),
          metadataProvider: provider,
          externalMetadataApplicationService: applicationService,
          externalMetadataProposalService: proposalService,
          qualifiedPlays: FakeQualifiedPlayRepository([
            qualifiedPlay('musicbrainz-artist-track'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      final menu = find.byKey(
        const ValueKey<String>(
          'artist-top-track-menu-musicbrainz-artist-track',
        ),
      );
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Track Studio'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('track-studio-page')),
        findsOneWidget,
      );

      final musicBrainzTile = find.byKey(
        const ValueKey<String>('track-studio-search-musicbrainz'),
      );

      expect(tester.widget<ListTile>(musicBrainzTile).enabled, isTrue);

      await tester.tap(musicBrainzTile);
      await tester.pumpAndSettle();

      expect(find.text('Search MusicBrainz?'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('track-studio-musicbrainz-continue')),
      );
      await tester.pumpAndSettle();

      expect(provider.searchCount, 1);
      expect(provider.lastQuery?.entityKind, ExternalMetadataEntityKind.track);
      expect(provider.lastQuery?.title, 'Artist Studio Song');
    },
  );

  testWidgets('Artist Track Studio opens from the track menu', (tester) async {
    final repository = FakeLibraryQueryRepository(
      artist: createArtist(),
      albums: [createAlbum()],
      tracks: [createTrack(songId: 'studio-song', title: 'Studio Song')],
    );

    final accountRepository = FakeAccountRepository(
      currentUser: const AccountUser(id: 'user-1', email: 'user@example.com'),
    );

    final editingService = EnabledTrackStudioEditingService();

    await tester.pumpWidget(
      buildSubject(
        repository: repository,
        accountRepository: accountRepository,
        trackProfileEditingService: editingService,
        qualifiedPlays: FakeQualifiedPlayRepository([
          qualifiedPlay('studio-song'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    final menuFinder = find.byKey(
      const ValueKey<String>('artist-top-track-menu-studio-song'),
    );

    expect(menuFinder, findsOneWidget);
    await tester.ensureVisible(menuFinder);
    await tester.pumpAndSettle();

    await tester.tap(menuFinder);
    await tester.pumpAndSettle();

    expect(find.text('Track Studio'), findsOneWidget);
    expect(find.text('Edit song details'), findsNothing);
    expect(find.text('Change artwork'), findsNothing);
    expect(find.text('Clear artwork'), findsNothing);

    await tester.tap(find.text('Track Studio'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('track-studio-page')),
      findsOneWidget,
    );
  });
}

class FakeArtistTrackMetadataProposalService extends Fake
    implements ExternalMetadataProposalService {}

Widget buildSubject({
  required LibraryQueryRepository? repository,
  PlaybackCoordinator? playbackCoordinator,
  AccountRepository? accountRepository,
  ArtistProfileEditingService? artistProfileEditingService,
  TrackProfileEditingService? trackProfileEditingService,
  SongBlockService? songBlockService,
  MetadataProvider? metadataProvider,
  ExternalMetadataApplicationService? externalMetadataApplicationService,
  ExternalMetadataProposalService? externalMetadataProposalService,
  bool wrapArtistInRoute = false,
  ThemeData? theme,
  TransitionBuilder? appBuilder,
  QualifiedPlayRepository? qualifiedPlays,
  PlaybackSessionRepository? playbackSessions,
  PlaybackListeningSegmentRepository? listeningSegments,
  Widget? home,
}) {
  final app = wrapArtistInRoute
      ? MaterialApp(
          theme: theme,
          builder: appBuilder,
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
      : MaterialApp(
          theme: theme,
          builder: appBuilder,
          home:
              home ??
              const ArtistProfilePage(
                artistId: 'artist-1',
                initialArtistName: 'Test Artist',
              ),
        );

  return Provider<MetadataProvider?>.value(
    value: metadataProvider,
    child: Provider<ExternalMetadataApplicationService?>.value(
      value: externalMetadataApplicationService,
      child: Provider<LibraryQueryRepository?>.value(
        value: repository,
        child: Provider<PlaybackCoordinator?>.value(
          value: playbackCoordinator,
          child: Provider<ArtistProfileEditingService?>.value(
            value: artistProfileEditingService,
            child: Provider<TrackProfileEditingService?>.value(
              value: trackProfileEditingService,
              child: Provider<SongBlockService?>.value(
                value: songBlockService,
                child: AccountScope(
                  repository: accountRepository,
                  child: Provider<ExternalMetadataProposalService?>.value(
                    value: externalMetadataProposalService,
                    child: Provider<QualifiedPlayRepository?>.value(
                      value: qualifiedPlays,
                      child: Provider<PlaybackSessionRepository?>.value(
                        value: playbackSessions,
                        child:
                            Provider<PlaybackListeningSegmentRepository?>.value(
                              value: listeningSegments,
                              child: app,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
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
  int albumCount = 1,
  int songCount = 1,
  String? headerArtworkPath,
  String? topArtistsArtworkPath,
}) {
  return LibraryArtist(
    artistId: artistId,
    name: name,
    albumCount: albumCount,
    songCount: songCount,
    headerArtworkPath: headerArtworkPath,
    topArtistsArtworkPath: topArtistsArtworkPath,
    dateAdded: DateTime(2026, 1, 1),
  );
}

LibraryAlbum createAlbum({
  String albumId = 'album-1',
  String title = 'Test Album',
  String artistId = 'artist-1',
  String artistName = 'Test Artist',
  String? artworkPath,
}) {
  return LibraryAlbum(
    albumId: albumId,
    title: title,
    artistId: artistId,
    artistName: artistName,
    artworkPath: artworkPath,
    trackCount: 1,
    dateAdded: DateTime(2026, 1, 1),
  );
}

LibraryTrack createTrack({
  String songId = 'song-1',
  String title = 'Test Song',
  String artistId = 'artist-1',
  String artistName = 'Test Artist',
  String albumId = 'album-1',
  String albumTitle = 'Test Album',
  String? filePath,
  bool isAvailable = true,
  bool isSongBlocked = false,
  List<String> featuredArtists = const [],
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: artistId,
    artistName: artistName,
    albumId: albumId,
    albumTitle: albumTitle,
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.values.first,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: featuredArtists,
    dateAdded: DateTime(2026, 1, 1),
    filePath: filePath ?? '/music/$songId.mp3',
    isAvailable: isAvailable,
    isSongBlocked: isSongBlocked,
  );
}

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  FakeLibraryQueryRepository({
    this.artist,
    this.albums = const [],
    this.tracks = const [],
    this.allTracks = const [],
    this.artistError,
    this.artistLoader,
  });

  LibraryArtist? artist;
  final List<LibraryAlbum> albums;
  final List<LibraryTrack> tracks;
  final List<LibraryTrack> allTracks;
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
    return allTracks;
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
    String? userId,
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
      required String? userId,
      required String artistId,
      required String name,
    });

typedef FakeArtistRemoveCallback =
    Future<void> Function({required String? userId, required String artistId});

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
    required String? userId,
    required String artistId,
  }) async {
    removeCallCount++;
    lastUserId = userId;
    lastArtistId = artistId;

    await onRemove?.call(userId: userId, artistId: artistId);
  }

  @override
  Future<Artist> renameArtist({
    required String? userId,
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

class EnabledTrackStudioEditingService extends TrackProfileEditingService {
  EnabledTrackStudioEditingService()
    : super(mutationRunner: UnusedSyncMutationRunner());
}

class FakeArtistTrackMetadataProvider implements MetadataProvider {
  ExternalMetadataSearchQuery? lastQuery;
  int searchCount = 0;

  @override
  ExternalMetadataProviderKind get providerKind =>
      ExternalMetadataProviderKind.musicBrainz;

  @override
  Future<List<ExternalMetadataCandidate>> search(
    ExternalMetadataSearchQuery query,
  ) async {
    searchCount++;
    lastQuery = query;
    return const [];
  }

  @override
  Future<ExternalMetadataCandidate?> lookup({
    required ExternalMetadataEntityKind entityKind,
    required String providerEntityId,
  }) async {
    return null;
  }
}

class FakeArtistTrackMetadataApplicationService
    extends ExternalMetadataApplicationService {
  FakeArtistTrackMetadataApplicationService()
    : super(mutationRunner: UnusedSyncMutationRunner());
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

/// Qualified plays held in memory (SN-48I Top Tracks).
class FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  FakeQualifiedPlayRepository([List<QualifiedPlay>? plays])
    : plays = plays ?? [];

  final List<QualifiedPlay> plays;
  int getAllCount = 0;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    getAllCount++;
    return List.of(plays);
  }

  @override
  Future<void> create(QualifiedPlay play) async => plays.add(play);

  @override
  Future<void> save(QualifiedPlay play) async => plays.add(play);

  @override
  Future<QualifiedPlay?> getById(String id) async => null;

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(
    String playbackSessionId,
  ) async => null;

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) async => const [];
}

int _qualifiedPlayCounter = 0;

QualifiedPlay qualifiedPlay(
  String songId, {
  DateTime? at,
  String artistId = 'artist-1',
  String albumId = 'album-1',
}) {
  final id = 'play-${_qualifiedPlayCounter++}';
  final qualifiedAt = at ?? DateTime.utc(2026, 1, 1);

  return QualifiedPlay(
    id: id,
    playbackSessionId: 'session-$id',
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: 'edition-1',
    qualifiedAt: qualifiedAt,
    listenedDuration: const Duration(seconds: 120),
    trackDuration: const Duration(seconds: 180),
    createdAt: qualifiedAt,
  );
}

/// A structured repository, as in production: main and collaboration
/// tracks come from credits, and only artists with a main credit are
/// profile eligible.
class FakeStructuredLibraryQueryRepository extends FakeLibraryQueryRepository
    implements StructuredArtistQueryRepository {
  FakeStructuredLibraryQueryRepository({
    super.artist,
    super.albums,
    super.allTracks,
    this.mainTracks = const [],
    this.collaborationTracks = const [],
    this.artists = const [],
    this.profileEligible = true,
  });

  final List<LibraryTrack> mainTracks;
  final List<LibraryTrack> collaborationTracks;
  final List<LibraryArtist> artists;
  final bool profileEligible;

  @override
  Future<List<LibraryArtist>> getProfileEligibleArtists() async =>
      profileEligible && artist != null ? [artist!] : const [];

  @override
  Future<LibraryArtist?> getProfileEligibleArtistById(String artistId) async =>
      profileEligible ? artist : null;

  @override
  Future<List<LibraryTrack>> getMainTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => mainTracks;

  @override
  Future<List<LibraryTrack>> getCollaborationTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => collaborationTracks;

  @override
  Future<List<LibraryArtist>> getArtists() async => artists;
}
