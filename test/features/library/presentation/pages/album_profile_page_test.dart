import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/presentation/scopes/account_scope.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/presentation/pages/album_profile_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

void main() {
  group('AlbumProfilePage', () {
    testWidgets('shows stable page while repository is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(repository: null));

      expect(
        find.byKey(const ValueKey<String>('album-profile-page')),
        findsOneWidget,
      );

      expect(find.text('Loading album...'), findsOneWidget);
    });

    testWidgets('shows loading state while album is loading', (tester) async {
      final completer = Completer<LibraryAlbum?>();

      final repository = FakeLibraryQueryRepository(
        albumLoader: (_) => completer.future,
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(null);

      await tester.pump();
      await tester.pump();
    });

    testWidgets('shows album profile content with detailed metadata', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(
          genre: 'Pop',
          releaseDate: DateTime(2026, 4, 12),
          primaryEditionTitle: 'Standard',
        ),
        tracks: [
          createTrack(
            songId: 'song-1',
            title: 'First Song',
            trackNumber: 1,
            durationSeconds: 180,
          ),
          createTrack(
            songId: 'song-2',
            title: 'Second Song',
            trackNumber: 2,
            durationSeconds: 245,
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Test Album'), findsWidgets);
      expect(find.text('Test Artist'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('album-profile-summary')),
        findsOneWidget,
      );
      expect(find.text('2 tracks \u2022 7 min'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('album-profile-metadata')),
        findsOneWidget,
      );
      expect(find.text('April 12, 2026 \u2022 Pop'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('album-profile-availability-notice')),
        findsNothing,
      );

      expect(
        find.byKey(const ValueKey<String>('album-profile-tracks-list')),
        findsOneWidget,
      );

      expect(find.text('First Song'), findsOneWidget);
      expect(find.text('Second Song'), findsOneWidget);
      expect(find.text('3:00'), findsOneWidget);
      expect(find.text('4:05'), findsOneWidget);
    });

    testWidgets('shows edition count for multi-edition album', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(
          genre: 'Pop',
          releaseDate: DateTime(2024, 5, 17),
          primaryEditionTitle: 'Standard',
        ),
        tracks: [
          createTrack(
            songId: 'standard-song',
            albumEditionId: 'edition-standard',
            albumEditionTitle: 'Standard',
            albumEditionType: AlbumEditionType.standard,
          ),
          createTrack(
            songId: 'deluxe-song',
            albumEditionId: 'edition-deluxe',
            albumEditionTitle: 'Deluxe',
            albumEditionType: AlbumEditionType.deluxe,
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.text('May 17, 2024 \u2022 Pop \u2022 2 editions'),
        findsOneWidget,
      );
    });

    testWidgets('shows unavailable track notice', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'available-song'),
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('album-profile-availability-notice')),
        findsOneWidget,
      );

      expect(find.text('1 track unavailable'), findsOneWidget);
    });

    testWidgets('pluralizes unavailable track notice', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'missing-1', filePath: '', isAvailable: false),
          createTrack(songId: 'missing-2', filePath: '', isAvailable: false),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('2 tracks unavailable'), findsOneWidget);
    });

    testWidgets('shows empty track state', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(trackCount: 0),
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('No tracks yet'), findsOneWidget);
    });

    testWidgets('shows album not found state', (tester) async {
      final repository = FakeLibraryQueryRepository();

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Album not found'), findsOneWidget);
    });

    testWidgets('shows error state when loading fails', (tester) async {
      final repository = FakeLibraryQueryRepository(
        albumError: StateError('failed'),
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Could not load this album.'), findsOneWidget);

      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('retry reloads profile after failure', (tester) async {
      var shouldFail = true;

      final repository = FakeLibraryQueryRepository(
        albumLoader: (_) async {
          if (shouldFail) {
            throw StateError('failed');
          }

          return createAlbum(title: 'Recovered Album');
        },
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Could not load this album.'), findsOneWidget);

      shouldFail = false;

      await tester.tap(find.text('Try again'));

      await tester.pumpAndSettle();

      expect(find.text('Recovered Album'), findsWidgets);
    });

    testWidgets('signed-in user can edit album details', (tester) async {
      var currentAlbum = createAlbum(
        title: 'Test Album',
        primaryEditionTitle: 'Standard',
        primaryEditionType: AlbumEditionType.standard,
        releaseDate: DateTime(2024, 5, 17),
        genre: 'Pop',
      );

      final repository = FakeLibraryQueryRepository(
        albumLoader: (_) async => currentAlbum,
      );

      final editingService = FakeAlbumProfileEditingService(
        onUpdate:
            ({
              required userId,
              required albumId,
              required primaryEditionId,
              required title,
              required editionTitle,
              required editionType,
              required releaseDate,
              required genre,
            }) async {
              currentAlbum = createAlbum(
                albumId: albumId,
                title: title.trim(),
                primaryEditionId: primaryEditionId,
                primaryEditionTitle: editionTitle.trim(),
                primaryEditionType: editionType,
                releaseDate: releaseDate,
                genre: genre,
              );
            },
      );

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          accountRepository: FakeAccountRepository(
            currentUser: const AccountUser(id: 'user-1'),
          ),
          albumProfileEditingService: editingService,
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit album details'), findsOneWidget);

      await tester.tap(find.text('Edit album details'));
      await tester.pumpAndSettle();

      final titleField = find.byKey(
        const ValueKey<String>('album-title-field'),
      );
      final editionTitleField = find.byKey(
        const ValueKey<String>('album-edition-title-field'),
      );
      final releaseDateField = find.byKey(
        const ValueKey<String>('album-release-date-field'),
      );
      final genreField = find.byKey(
        const ValueKey<String>('album-genre-field'),
      );

      expect(
        tester.widget<TextFormField>(titleField).controller?.text,
        'Test Album',
      );
      expect(
        tester.widget<TextFormField>(editionTitleField).controller?.text,
        'Standard',
      );
      expect(
        tester.widget<TextFormField>(releaseDateField).controller?.text,
        '2024-05-17',
      );
      expect(tester.widget<TextFormField>(genreField).controller?.text, 'Pop');

      await tester.enterText(titleField, 'Renamed Album');
      await tester.enterText(editionTitleField, 'Deluxe Edition');
      await tester.enterText(releaseDateField, '2025-06-20');
      await tester.enterText(genreField, 'Alternative');

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('album-edition-type-field')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-edition-type-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deluxe').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(editingService.updateCallCount, 1);
      expect(editingService.lastUserId, 'user-1');
      expect(editingService.lastAlbumId, 'album-1');
      expect(editingService.lastPrimaryEditionId, 'edition-1');
      expect(editingService.lastTitle, 'Renamed Album');
      expect(editingService.lastEditionTitle, 'Deluxe Edition');
      expect(editingService.lastEditionType, AlbumEditionType.deluxe);
      expect(editingService.lastReleaseDate, DateTime(2025, 6, 20));
      expect(editingService.lastGenre, 'Alternative');

      expect(find.text('Renamed Album'), findsWidgets);
      expect(find.text('Album details updated.'), findsOneWidget);
    });

    testWidgets('album edit can change album artist', (tester) async {
      final editingService = FakeAlbumProfileEditingService();

      await tester.pumpWidget(
        buildSubject(
          repository: FakeLibraryQueryRepository(
            album: createAlbum(
              artistId: 'artist-1',
              artistName: 'Test Artist',
              primaryEditionTitle: 'Standard',
            ),
          ),
          accountRepository: FakeAccountRepository(
            currentUser: const AccountUser(id: 'user-1'),
          ),
          albumProfileEditingService: editingService,
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit album details'));
      await tester.pumpAndSettle();

      final artistField = find.byKey(
        const ValueKey<String>('album-artist-field'),
      );

      expect(artistField, findsOneWidget);

      await tester.tap(artistField);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Second Artist').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-edit-save-button')),
      );
      await tester.pumpAndSettle();

      expect(editingService.updateCallCount, 1);
      expect(editingService.lastArtistId, 'artist-2');
    });
    testWidgets('album edit validates required fields and release date', (
      tester,
    ) async {
      final editingService = FakeAlbumProfileEditingService();

      await tester.pumpWidget(
        buildSubject(
          repository: FakeLibraryQueryRepository(
            album: createAlbum(primaryEditionTitle: 'Standard'),
          ),
          accountRepository: FakeAccountRepository(
            currentUser: const AccountUser(id: 'user-1'),
          ),
          albumProfileEditingService: editingService,
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit album details'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('album-title-field')),
        '   ',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('album-edition-title-field')),
        '',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('album-release-date-field')),
        '2026-02-31',
      );

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Album title cannot be blank.'), findsOneWidget);
      expect(find.text('Edition title cannot be blank.'), findsOneWidget);
      expect(find.text('Use YYYY-MM-DD.'), findsOneWidget);
      expect(editingService.updateCallCount, 0);
    });

    testWidgets('album edit can clear release date and genre', (tester) async {
      final editingService = FakeAlbumProfileEditingService();

      await tester.pumpWidget(
        buildSubject(
          repository: FakeLibraryQueryRepository(
            album: createAlbum(
              primaryEditionTitle: 'Standard',
              releaseDate: DateTime(2024, 5, 17),
              genre: 'Pop',
            ),
          ),
          accountRepository: FakeAccountRepository(
            currentUser: const AccountUser(id: 'user-1'),
          ),
          albumProfileEditingService: editingService,
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit album details'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('album-release-date-field')),
        '',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('album-genre-field')),
        '',
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(editingService.updateCallCount, 1);
      expect(editingService.lastReleaseDate, isNull);
      expect(editingService.lastGenre, isNull);
    });

    testWidgets('signed-out user cannot edit album details', (tester) async {
      final editingService = FakeAlbumProfileEditingService();

      await tester.pumpWidget(
        buildSubject(
          repository: FakeLibraryQueryRepository(
            album: createAlbum(primaryEditionTitle: 'Standard'),
          ),
          accountRepository: FakeAccountRepository(),
          albumProfileEditingService: editingService,
        ),
      );

      await tester.pumpAndSettle();

      final menu = tester.widget<PopupMenuButton>(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );

      expect(menu.enabled, isFalse);
      expect(editingService.updateCallCount, 0);
    });

    testWidgets('album editing remains unavailable without editing service', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          repository: FakeLibraryQueryRepository(
            album: createAlbum(primaryEditionTitle: 'Standard'),
          ),
          accountRepository: FakeAccountRepository(
            currentUser: const AccountUser(id: 'user-1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final menu = tester.widget<PopupMenuButton>(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );

      expect(menu.enabled, isFalse);
    });
    testWidgets('play button plays album tracks', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
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
        const ValueKey<String>('album-profile-play-all-button'),
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
        album: createAlbum(),
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
        const ValueKey<String>('album-profile-shuffle-button'),
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

    testWidgets('tapping playable track starts playback', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
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

      final trackFinder = find.byKey(
        const ValueKey<String>('album-track-play-song'),
      );

      expect(trackFinder, findsOneWidget);

      await tester.tap(trackFinder);

      await tester.pump();

      expect(engine.loadQueueCallCount, 1);

      expect(engine.lastLoadedTracks, hasLength(1));

      expect(engine.lastLoadedTracks!.single.songId, 'play-song');

      expect(engine.lastAutoPlay, isTrue);

      await engine.dispose();
    });

    testWidgets('unavailable track is disabled and does not start playback', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
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

      final tileFinder = find.byKey(
        const ValueKey<String>('album-track-missing-song'),
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
        album: createAlbum(),
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

      final tileFinder = find.byKey(
        const ValueKey<String>('album-track-missing-song'),
      );

      final tile = tester.widget<ListTile>(tileFinder);
      expect(tile.enabled, isFalse);

      final menuFinder = find.byKey(
        const ValueKey<String>('album-track-menu-missing-song'),
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
        album: createAlbum(),
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
        find.byKey(const ValueKey<String>('album-profile-play-all-button')),
      );

      expect(playButton.onPressed, isNull);

      final shuffleButton = tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('album-profile-shuffle-button')),
      );

      expect(shuffleButton.onPressed, isNull);

      await engine.dispose();
    });

    testWidgets(
      'blacklisted album track remains removable from the blacklist',
      (tester) async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(
              songId: 'blocked-song',
              title: 'Blocked Song',
              isSongBlocked: true,
            ),
          ],
        );

        final accountRepository = FakeAccountRepository(
          currentUser: const AccountUser(
            id: 'user-1',
            email: 'user@example.com',
          ),
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

        expect(find.text('Blacklisted'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey<String>('album-profile-availability-notice'),
          ),
          findsNothing,
        );

        final menuFinder = find.byKey(
          const ValueKey<String>('album-track-menu-blocked-song'),
        );

        expect(
          tester.widget<PopupMenuButton<dynamic>>(menuFinder).enabled,
          isTrue,
        );

        await tester.tap(menuFinder);
        await tester.pumpAndSettle();

        expect(find.text('Remove from blacklist'), findsOneWidget);

        await tester.tap(find.text('Remove from blacklist'));
        await tester.pumpAndSettle();

        expect(service.setBlockedCallCount, 1);
        expect(service.lastUserId, 'user-1');
        expect(service.lastSongId, 'blocked-song');
        expect(service.lastIsBlocked, isFalse);
        expect(find.text('Removed from blacklist.'), findsOneWidget);
      },
    );
  });
}

Widget buildSubject({
  required LibraryQueryRepository? repository,
  PlaybackCoordinator? playbackCoordinator,
  AccountRepository? accountRepository,
  AlbumProfileEditingService? albumProfileEditingService,
  TrackProfileEditingService? trackProfileEditingService,
  SongBlockService? songBlockService,
}) {
  return Provider<SongBlockService?>.value(
    value: songBlockService,
    child: Provider<LibraryQueryRepository?>.value(
      value: repository,
      child: Provider<PlaybackCoordinator?>.value(
        value: playbackCoordinator,
        child: Provider<AlbumProfileEditingService?>.value(
          value: albumProfileEditingService,
          child: Provider<TrackProfileEditingService?>.value(
            value: trackProfileEditingService,
            child: AccountScope(
              repository: accountRepository,
              child: const MaterialApp(
                home: AlbumProfilePage(
                  albumId: 'album-1',
                  initialAlbumTitle: 'Test Album',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

LibraryAlbum createAlbum({
  String albumId = 'album-1',
  String title = 'Test Album',
  String artistId = 'artist-1',
  String artistName = 'Test Artist',
  int trackCount = 2,
  String primaryEditionId = 'edition-1',
  String? primaryEditionTitle,
  AlbumEditionType primaryEditionType = AlbumEditionType.standard,
  DateTime? releaseDate,
  String? genre,
}) {
  return LibraryAlbum(
    albumId: albumId,
    title: title,
    artistId: artistId,
    artistName: artistName,
    primaryEditionId: primaryEditionId,
    primaryEditionTitle: primaryEditionTitle,
    primaryEditionType: primaryEditionType,
    releaseDate: releaseDate,
    genre: genre,
    trackCount: trackCount,
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
  String albumEditionId = 'edition-1',
  String albumEditionTitle = 'Standard',
  AlbumEditionType albumEditionType = AlbumEditionType.standard,
  int trackNumber = 1,
  int durationSeconds = 180,
  List<String> featuredArtists = const [],
  String? filePath,
  bool isAvailable = true,
  bool isSongBlocked = false,
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
    albumEditionType: albumEditionType,
    trackNumber: trackNumber,
    durationSeconds: durationSeconds,
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
    this.album,
    this.tracks = const [],
    this.albumError,
    this.albumLoader,
  });

  final LibraryAlbum? album;
  final List<LibraryTrack> tracks;
  final Object? albumError;

  final Future<LibraryAlbum?> Function(String albumId)? albumLoader;

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    final loader = albumLoader;

    if (loader != null) {
      return loader(albumId);
    }

    final error = albumError;

    if (error != null) {
      throw error;
    }

    return album;
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
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
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
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
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return const [];
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return [
      LibraryArtist(
        artistId: 'artist-1',
        name: 'Test Artist',
        albumCount: 1,
        songCount: 1,
        dateAdded: DateTime(2026, 1, 1),
      ),
      LibraryArtist(
        artistId: 'artist-2',
        name: 'Second Artist',
        albumCount: 1,
        songCount: 1,
        dateAdded: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    return null;
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

typedef FakeAlbumProfileUpdateCallback =
    Future<void> Function({
      required String userId,
      required String albumId,
      required String primaryEditionId,
      required String title,
      required String editionTitle,
      required AlbumEditionType editionType,
      required DateTime? releaseDate,
      required String? genre,
    });

class FakeAlbumProfileEditingService extends AlbumProfileEditingService {
  FakeAlbumProfileEditingService({this.onUpdate})
    : super(mutationRunner: UnusedSyncMutationRunner());

  final FakeAlbumProfileUpdateCallback? onUpdate;

  int updateCallCount = 0;

  String? lastUserId;
  String? lastAlbumId;
  String? lastPrimaryEditionId;
  String? lastTitle;
  String? lastEditionTitle;
  AlbumEditionType? lastEditionType;
  DateTime? lastReleaseDate;
  String? lastGenre;
  String? lastArtistId;

  @override
  Future<AlbumProfileEditResult> updateProfile({
    required String userId,
    required String albumId,
    required String primaryEditionId,
    required String title,
    required String editionTitle,
    required AlbumEditionType editionType,
    required DateTime? releaseDate,
    required String? genre,
    String? artistId,
    DateTime? now,
  }) async {
    updateCallCount++;

    lastUserId = userId;
    lastAlbumId = albumId;
    lastPrimaryEditionId = primaryEditionId;
    lastTitle = title;
    lastEditionTitle = editionTitle;
    lastEditionType = editionType;
    lastReleaseDate = releaseDate;
    lastGenre = genre;
    lastArtistId = artistId;

    await onUpdate?.call(
      userId: userId,
      albumId: albumId,
      primaryEditionId: primaryEditionId,
      title: title,
      editionTitle: editionTitle,
      editionType: editionType,
      releaseDate: releaseDate,
      genre: genre,
    );

    final timestamp = now ?? DateTime(2026, 1, 1);

    return AlbumProfileEditResult(
      album: Album(
        id: albumId,
        artistId: 'artist-1',
        title: title.trim(),
        canonicalTitle: title.trim().toLowerCase(),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      primaryEdition: AlbumEdition(
        id: primaryEditionId,
        albumId: albumId,
        title: editionTitle.trim(),
        type: editionType,
        isPrimary: true,
        releaseDate: releaseDate,
        genre: genre,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      albumChanged: true,
      primaryEditionChanged: true,
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
