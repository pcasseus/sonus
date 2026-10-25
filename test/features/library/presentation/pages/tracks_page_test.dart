import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_proposal.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_proposal_service.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_application_service.dart';
import 'package:sonus_next/features/library/application/services/metadata_provider.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/song_artist_credit_service.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/domain/repositories/song_artist_credit_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/presentation/pages/track_studio_page.dart';
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

    testWidgets('ghosts unavailable tracks from the library list', (
      tester,
    ) async {
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

      expect(
        find.byKey(const ValueKey<String>('track-available')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('track-unavailable')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('track-menu-unavailable')),
        findsNothing,
      );
      expect(find.text('Unavailable Song'), findsNothing);
    });

    testWidgets('ghosted unavailable track exposes no library row menu', (
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

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('track-unavailable')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('track-menu-unavailable')),
        findsNothing,
      );
      expect(find.text('Unavailable Song'), findsNothing);
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

    testWidgets('signed-out user can blacklist a song from the track menu', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [createTrack(songId: 'song-local-block', title: 'Local Block')],
      );

      final service = FakeSongBlockService();

      await tester.pumpWidget(
        buildSubject(repository: repository, songBlockService: service),
      );

      await tester.pumpAndSettle();

      final menuFinder = find.byKey(
        const ValueKey<String>('track-menu-song-local-block'),
      );

      expect(
        tester.widget<PopupMenuButton<dynamic>>(menuFinder).enabled,
        isTrue,
      );

      await tester.tap(menuFinder);
      await tester.pumpAndSettle();

      expect(find.text('Blacklist song'), findsOneWidget);

      await tester.tap(find.text('Blacklist song'));
      await tester.pumpAndSettle();

      expect(service.setBlockedCallCount, 1);
      expect(service.lastUserId, isNull);
      expect(service.lastSongId, 'song-local-block');
      expect(service.lastIsBlocked, isTrue);
      expect(find.text('Song blacklisted.'), findsOneWidget);
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

      expect(find.text('Blacklist song'), findsOneWidget);

      await tester.tap(find.text('Blacklist song'));
      await tester.pumpAndSettle();

      expect(service.setBlockedCallCount, 1);
      expect(service.lastUserId, 'user-1');
      expect(service.lastSongId, 'song-block');
      expect(service.lastIsBlocked, isTrue);
      expect(find.text('Song blacklisted.'), findsOneWidget);
    });

    testWidgets(
      'blacklisted song can be removed from the blacklist from the track menu',
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
        expect(find.text('Blacklisted'), findsOneWidget);
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

        expect(find.text('Remove from blacklist'), findsOneWidget);

        await tester.tap(find.text('Remove from blacklist'));
        await tester.pumpAndSettle();

        expect(service.setBlockedCallCount, 1);
        expect(service.lastUserId, 'user-1');
        expect(service.lastSongId, 'song-unblock');
        expect(service.lastIsBlocked, isFalse);
        expect(find.text('Removed from blacklist.'), findsOneWidget);
      },
    );
    testWidgets('Track Studio disables MusicBrainz without dependencies', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [createTrack(songId: 'song-disabled', title: 'Original')],
      );

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          trackProfileEditingService: FakeTrackStudioEditingService(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('track-menu-song-disabled')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Track Studio'));
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('track-studio-search-musicbrainz')),
      );

      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    });

    testWidgets('Track Studio requires proposal service for MusicBrainz', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [createTrack(songId: 'song-no-proposal', title: 'Original')],
      );

      final provider = FakeTrackMusicBrainzProvider(results: const []);
      final applicationService = FakeTrackMusicBrainzApplicationService();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          trackProfileEditingService: FakeTrackStudioEditingService(),
          metadataProvider: provider,
          externalMetadataApplicationService: applicationService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('track-menu-song-no-proposal')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Track Studio'));
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('track-studio-search-musicbrainz')),
      );

      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
      expect(provider.searchCount, 0);
      expect(applicationService.applyCount, 0);
    });
    testWidgets('canceling MusicBrainz preserves unsaved Track Studio edits', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [createTrack(songId: 'song-cancel', title: 'Original')],
      );
      final editingService = FakeTrackStudioEditingService();
      final provider = FakeTrackMusicBrainzProvider(results: const []);
      final applicationService = FakeTrackMusicBrainzApplicationService();
      final proposalService = FakeTrackMetadataProposalService();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          trackProfileEditingService: editingService,
          metadataProvider: provider,
          externalMetadataApplicationService: applicationService,
          externalMetadataProposalService: proposalService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('track-menu-song-cancel')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Track Studio'));
      await tester.pumpAndSettle();

      const titleKey = ValueKey<String>('track-title-field');
      await tester.enterText(find.byKey(titleKey), 'Unsaved Manual Title');

      await tester.tap(
        find.byKey(const ValueKey<String>('track-studio-search-musicbrainz')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Search MusicBrainz?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('track-studio-page')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(find.byKey(titleKey)).controller!.text,
        'Unsaved Manual Title',
      );
      expect(provider.searchCount, 0);
      expect(proposalService.previewCallCount, 0);
      expect(applicationService.applyCount, 0);
      expect(editingService.structuredUpdateCallCount, 0);
    });

    testWidgets(
      'MusicBrainz applies to original song and closes without manual save',
      (tester) async {
        var currentTrack = createTrack(
          songId: 'song-musicbrainz',
          title: 'Original Song',
          artistName: 'Original Artist',
          albumTitle: 'Original Album',
          durationSeconds: 218,
          featuredArtists: const ['Featured Artist'],
        );

        final repository = FakeLibraryQueryRepository(
          tracksLoader: (_) async => [currentTrack],
        );
        final editingService = FakeTrackStudioEditingService();

        final provider = FakeTrackMusicBrainzProvider(
          results: const [
            ExternalMetadataCandidate(
              provider: ExternalMetadataProviderKind.musicBrainz,
              entityKind: ExternalMetadataEntityKind.track,
              providerEntityId: 'recording-mbid-123',
              displayName: 'Matched Recording',
              durationSeconds: 220,
            ),
          ],
        );

        final applicationService = FakeTrackMusicBrainzApplicationService()
          ..onApply = (candidate) async {
            currentTrack = createTrack(
              songId: 'song-musicbrainz',
              title: candidate.displayName,
              artistName: 'Original Artist',
              albumTitle: 'Original Album',
              durationSeconds: 220,
              featuredArtists: const ['Featured Artist'],
            );
          };

        final proposalService = FakeTrackMetadataProposalService();

        await tester.pumpWidget(
          buildSubject(
            repository: repository,
            trackProfileEditingService: editingService,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            externalMetadataProposalService: proposalService,
          ),
        );
        await tester.pumpAndSettle();

        final originalLoadCount = repository.requestedOrders.length;

        await tester.tap(
          find.byKey(const ValueKey<String>('track-menu-song-musicbrainz')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Track Studio'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('track-title-field')),
          'Do Not Save This Title',
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('track-studio-search-musicbrainz')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey<String>('track-studio-musicbrainz-continue'),
          ),
        );
        await tester.pumpAndSettle();

        expect(provider.searchCount, 1);
        expect(
          provider.lastQuery?.entityKind,
          ExternalMetadataEntityKind.track,
        );
        expect(provider.lastQuery?.title, 'Original Song');
        expect(provider.lastQuery?.artistName, 'Original Artist');
        expect(provider.lastQuery?.albumTitle, 'Original Album');
        expect(provider.lastQuery?.durationSeconds, 218);

        await tester.tap(
          find.byKey(
            const ValueKey<String>('musicbrainz-result-recording-mbid-123'),
          ),
        );
        await tester.pumpAndSettle();

        expect(proposalService.previewCallCount, 1);
        expect(proposalService.lastSongId, 'song-musicbrainz');
        expect(
          proposalService.lastCandidate?.providerEntityId,
          'recording-mbid-123',
        );
        expect(
          find.byKey(
            const ValueKey<String>('musicbrainz-proposal-review-dialog'),
          ),
          findsOneWidget,
        );
        expect(applicationService.applyCount, 0);

        await tester.tap(
          find.byKey(const ValueKey<String>('musicbrainz-proposal-apply')),
        );
        await tester.pumpAndSettle();

        expect(applicationService.applyCount, 1);
        expect(applicationService.lastSongId, 'song-musicbrainz');
        expect(applicationService.lastUserId, isNull);
        expect(
          applicationService.lastCandidate?.providerEntityId,
          'recording-mbid-123',
        );
        expect(
          repository.requestedOrders.length,
          greaterThan(originalLoadCount),
        );

        expect(
          find.byKey(const ValueKey<String>('track-studio-page')),
          findsNothing,
        );
        expect(find.text('Matched Recording'), findsOneWidget);
        expect(currentTrack.featuredArtists, ['Featured Artist']);
        expect(currentTrack.albumId, 'album-1');
        expect(currentTrack.albumEditionId, 'edition-1');
        expect(currentTrack.trackNumber, 1);

        expect(editingService.structuredUpdateCallCount, 0);
        expect(editingService.updateCallCount, 0);
      },
    );
    testWidgets(
      'MusicBrainz application remains successful when library refresh fails',
      (tester) async {
        var loadCount = 0;

        final repository = FakeLibraryQueryRepository(
          tracksLoader: (_) async {
            loadCount++;
            if (loadCount > 1) {
              throw StateError('Refresh failed');
            }
            return [
              createTrack(songId: 'song-refresh-fail', title: 'Original'),
            ];
          },
        );

        final editingService = FakeTrackStudioEditingService();
        final provider = FakeTrackMusicBrainzProvider(
          results: const [
            ExternalMetadataCandidate(
              provider: ExternalMetadataProviderKind.musicBrainz,
              entityKind: ExternalMetadataEntityKind.track,
              providerEntityId: 'recording-refresh-fail',
              displayName: 'Matched Recording',
            ),
          ],
        );
        final applicationService = FakeTrackMusicBrainzApplicationService();
        final proposalService = FakeTrackMetadataProposalService();

        await tester.pumpWidget(
          buildSubject(
            repository: repository,
            trackProfileEditingService: editingService,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            externalMetadataProposalService: proposalService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('track-menu-song-refresh-fail')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Track Studio'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('track-studio-search-musicbrainz')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey<String>('track-studio-musicbrainz-continue'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey<String>('musicbrainz-result-recording-refresh-fail'),
          ),
        );
        await tester.pumpAndSettle();
        expect(proposalService.previewCallCount, 1);
        expect(
          find.byKey(
            const ValueKey<String>('musicbrainz-proposal-review-dialog'),
          ),
          findsOneWidget,
        );
        expect(applicationService.applyCount, 0);

        await tester.tap(
          find.byKey(const ValueKey<String>('musicbrainz-proposal-apply')),
        );
        await tester.pumpAndSettle();

        expect(applicationService.applyCount, 1);
        expect(proposalService.lastSongId, 'song-refresh-fail');
        expect(loadCount, greaterThan(1));
        expect(
          find.byKey(const ValueKey<String>('track-studio-page')),
          findsNothing,
        );
        expect(editingService.structuredUpdateCallCount, 0);
      },
    );
    testWidgets('Track Studio edits and saves a track from the Tracks menu', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [createTrack(songId: 'song-studio', title: 'Original Title')],
      );
      final editingService = FakeTrackStudioEditingService();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          trackProfileEditingService: editingService,
        ),
      );
      await tester.pumpAndSettle();

      final menuFinder = find.byKey(
        const ValueKey<String>('track-menu-song-studio'),
      );

      expect(menuFinder, findsOneWidget);

      await tester.tap(menuFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Track Studio'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('track-studio-page')),
        findsOneWidget,
      );
      expect(find.text('Track Studio'), findsOneWidget);

      final titleField = find.byKey(
        const ValueKey<String>('track-title-field'),
      );

      expect(titleField, findsOneWidget);

      await tester.enterText(titleField, 'Studio Title');

      await tester.tap(
        find.byKey(const ValueKey<String>('track-studio-save-button')),
      );
      await tester.pumpAndSettle();

      expect(editingService.structuredUpdateCallCount, 1);
      expect(editingService.updateCallCount, 1);
      expect(editingService.lastUserId, isNull);
      expect(editingService.lastSongId, 'song-studio');
      expect(editingService.lastTitle, 'Studio Title');
      expect(editingService.lastTrackNumber, 1);
      expect(editingService.lastDiscNumber, 1);
      expect(editingService.lastAdditionalCredits, isEmpty);
      expect(editingService.lastFeaturedArtists, isEmpty);
      expect(editingService.lastIsSingle, isFalse);
      expect(editingService.lastArtistId, 'artist-1');
      expect(editingService.lastAlbumId, 'album-1');
      expect(editingService.lastAlbumEditionId, 'edition-1');

      expect(
        find.byKey(const ValueKey<String>('track-studio-page')),
        findsNothing,
      );
    });
    testWidgets('Track Studio edits ordered structured artist credits', (
      tester,
    ) async {
      final timestamp = DateTime.utc(2026, 10, 3);
      final repository = FakeLibraryQueryRepository(
        tracks: [createTrack(songId: 'song-credits', title: 'Credit Test')],
      );
      final creditRepository = FakeSongArtistCreditRepository(
        credits: [
          SongArtistCredit(
            id: 'credit-co-primary',
            songId: 'song-credits',
            artistId: 'artist-partner',
            creditedName: 'Partner',
            canonicalCreditedName: 'partner',
            role: SongArtistCreditRole.coPrimary,
            position: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
          SongArtistCredit(
            id: 'credit-feature',
            songId: 'song-credits',
            artistId: 'artist-feature',
            creditedName: 'Feature Artist',
            canonicalCreditedName: 'feature artist',
            role: SongArtistCreditRole.featured,
            position: 2,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
          SongArtistCredit(
            id: 'credit-guest',
            songId: 'song-credits',
            creditedName: 'Guest Artist',
            canonicalCreditedName: 'guest artist',
            role: SongArtistCreditRole.guest,
            position: 3,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ],
      );
      final editingService = FakeTrackStudioEditingService();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          trackProfileEditingService: editingService,
          songArtistCreditRepository: creditRepository,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('track-menu-song-credits')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Track Studio'));
      await tester.pumpAndSettle();

      final studioList = find.descendant(
        of: find.byKey(const ValueKey<String>('track-studio-page')),
        matching: find.byType(ListView),
      );
      expect(studioList, findsOneWidget);

      await tester.drag(studioList, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('track-credit-row-0')),
        findsOneWidget,
      );
      expect(find.text('Partner'), findsOneWidget);
      expect(find.text('Feature Artist'), findsOneWidget);
      expect(find.text('Guest Artist'), findsOneWidget);

      // Rename the co-primary credit. Its old linked Artist ID must not survive.
      final editFirst = find.byKey(
        const ValueKey<String>('track-edit-credit-0'),
      );
      await tester.ensureVisible(editFirst);
      await tester.pumpAndSettle();
      await tester.tap(editFirst);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('track-credit-name-field')),
        'Renamed Partner',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('track-credit-save-button')),
      );
      await tester.pumpAndSettle();

      // Change the second credit's role without changing its name.
      // Its existing linked Artist identity should remain intact.
      final editSecond = find.byKey(
        const ValueKey<String>('track-edit-credit-1'),
      );
      await tester.ensureVisible(editSecond);
      await tester.pumpAndSettle();
      await tester.tap(editSecond);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('track-credit-role-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guest').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('track-credit-save-button')),
      );
      await tester.pumpAndSettle();

      // Add a new feature. New free-form credits remain unlinked.
      final addCredit = find.byKey(
        const ValueKey<String>('track-add-credit-button'),
      );
      await tester.ensureVisible(addCredit);
      await tester.pumpAndSettle();
      await tester.tap(addCredit);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('track-credit-name-field')),
        'New Feature',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('track-credit-save-button')),
      );
      await tester.pumpAndSettle();

      // Remove the original third-row guest credit.
      final removeThird = find.byKey(
        const ValueKey<String>('track-remove-credit-2'),
      );
      await tester.ensureVisible(removeThird);
      await tester.pumpAndSettle();
      await tester.tap(removeThird);
      await tester.pumpAndSettle();

      expect(find.text('Guest Artist'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('track-studio-save-button')),
      );
      await tester.pumpAndSettle();

      expect(editingService.structuredUpdateCallCount, 1);

      final submitted = editingService.lastAdditionalCredits;
      expect(submitted, isNotNull);
      expect(submitted, hasLength(3));

      expect(submitted![0].creditedName, 'Renamed Partner');
      expect(submitted[0].role, SongArtistCreditRole.coPrimary);
      expect(submitted[0].artistId, isNull);

      expect(submitted[1].creditedName, 'Feature Artist');
      expect(submitted[1].role, SongArtistCreditRole.guest);
      expect(submitted[1].artistId, 'artist-feature');

      expect(submitted[2].creditedName, 'New Feature');
      expect(submitted[2].role, SongArtistCreditRole.featured);
      expect(submitted[2].artistId, isNull);
    });
    testWidgets(
      'Track Studio closes and warns when refresh callback throws after apply',
      (tester) async {
        final candidate = ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.track,
          providerEntityId: 'recording-callback-failure',
          displayName: 'Matched Recording',
        );

        final provider = FakeTrackMusicBrainzProvider(results: [candidate]);
        final applicationService = FakeTrackMusicBrainzApplicationService();
        final proposalService = FakeTrackMetadataProposalService();

        var refreshCalls = 0;
        var routeFinished = false;
        Object? routeResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return Center(
                    child: FilledButton(
                      key: const ValueKey<String>('open-test-track-studio'),
                      onPressed: () async {
                        routeResult = await Navigator.of(context).push<Object?>(
                          MaterialPageRoute<Object?>(
                            builder: (_) => TrackStudioPage(
                              track: createTrack(
                                songId: 'song-callback-failure',
                                title: 'Original Recording',
                              ),
                              userId: 'user-1',
                              metadataProvider: provider,
                              externalMetadataApplicationService:
                                  applicationService,
                              externalMetadataProposalService: proposalService,
                              onMetadataApplied: () async {
                                refreshCalls++;
                                throw StateError('Library refresh failed');
                              },
                            ),
                          ),
                        );
                        routeFinished = true;
                      },
                      child: const Text('Open Studio'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('open-test-track-studio')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('track-studio-page')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('track-studio-search-musicbrainz')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey<String>('track-studio-musicbrainz-continue'),
          ),
        );
        await tester.pumpAndSettle();

        expect(provider.searchCount, 1);

        await tester.tap(
          find.byKey(
            const ValueKey<String>(
              'musicbrainz-result-recording-callback-failure',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(proposalService.previewCallCount, 1);
        expect(
          find.byKey(
            const ValueKey<String>('musicbrainz-proposal-review-dialog'),
          ),
          findsOneWidget,
        );
        expect(applicationService.applyCount, 0);

        await tester.tap(
          find.byKey(const ValueKey<String>('musicbrainz-proposal-apply')),
        );
        await tester.pumpAndSettle();

        expect(applicationService.applyCount, 1);
        expect(proposalService.lastSongId, 'song-callback-failure');
        expect(applicationService.lastSongId, 'song-callback-failure');
        expect(applicationService.lastUserId, 'user-1');
        expect(
          applicationService.lastCandidate?.providerEntityId,
          'recording-callback-failure',
        );

        expect(refreshCalls, 1);
        expect(routeFinished, isTrue);
        expect(routeResult, isNull);

        expect(
          find.byKey(const ValueKey<String>('track-studio-page')),
          findsNothing,
        );

        expect(
          find.text(
            'MusicBrainz metadata was applied, but the library could not refresh.',
          ),
          findsOneWidget,
        );

        expect(
          find.text('Could not complete the MusicBrainz operation.'),
          findsNothing,
        );
      },
    );
  });
}

Widget buildSubject({
  required LibraryQueryRepository? repository,
  AccountController? accountController,
  TrackProfileEditingService? trackProfileEditingService,
  SongBlockService? songBlockService,
  SongArtistCreditRepository? songArtistCreditRepository,
  PlaybackEngine? engine,
  MetadataProvider? metadataProvider,
  ExternalMetadataApplicationService? externalMetadataApplicationService,
  ExternalMetadataProposalService? externalMetadataProposalService,
  ThemeData? theme,
  TransitionBuilder? appBuilder,
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
      Provider<SongArtistCreditRepository?>.value(
        value: songArtistCreditRepository,
      ),
      Provider<PlaybackCoordinator>.value(value: coordinator),
      Provider<MetadataProvider?>.value(value: metadataProvider),
      Provider<ExternalMetadataApplicationService?>.value(
        value: externalMetadataApplicationService,
      ),
      Provider<ExternalMetadataProposalService?>.value(
        value: externalMetadataProposalService,
      ),
    ],
    child: MaterialApp(
      theme: theme,
      builder: appBuilder,
      home: const Scaffold(body: TracksPage()),
    ),
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
  PlaybackState get currentState => const PlaybackState();

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
  final AccountUser? currentUser;

  @override
  Stream<AccountUser?> watchAuthState() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class FakeTrackMetadataProposalService extends Fake
    implements ExternalMetadataProposalService {
  int previewCallCount = 0;
  String? lastSongId;
  ExternalMetadataCandidate? lastCandidate;

  @override
  Future<ExternalMetadataProposal> previewTrack({
    required String songId,
    required ExternalMetadataCandidate candidate,
  }) async {
    previewCallCount++;
    lastSongId = songId;
    lastCandidate = candidate;

    return ExternalMetadataProposal(
      entityType: MetadataEntityType.song,
      entityId: songId,
      candidate: candidate,
      fields: [
        ExternalMetadataProposalField(
          fieldName: MetadataFields.songTitle,
          currentValue: 'Original Song',
          proposedValue: candidate.displayName,
          status: ExternalMetadataProposalFieldStatus.valueChange,
        ),
        ExternalMetadataProposalField(
          fieldName: MetadataFields.songDuration,
          currentValue: 218,
          proposedValue: candidate.durationSeconds,
          status: candidate.durationSeconds == null
              ? ExternalMetadataProposalFieldStatus.notProposed
              : ExternalMetadataProposalFieldStatus.valueChange,
        ),
      ],
    );
  }
}

class FakeTrackMusicBrainzProvider implements MetadataProvider {
  FakeTrackMusicBrainzProvider({required this.results});

  final List<ExternalMetadataCandidate> results;
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
    return results;
  }

  @override
  Future<ExternalMetadataCandidate?> lookup({
    required ExternalMetadataEntityKind entityKind,
    required String providerEntityId,
  }) async {
    return null;
  }
}

class FakeTrackMusicBrainzApplicationService
    extends ExternalMetadataApplicationService {
  FakeTrackMusicBrainzApplicationService()
    : super(mutationRunner: UnusedSyncMutationRunner());

  int applyCount = 0;
  String? lastSongId;
  String? lastUserId;
  ExternalMetadataCandidate? lastCandidate;
  Future<void> Function(ExternalMetadataCandidate)? onApply;

  @override
  Future<ExternalMetadataApplicationResult> applyTrackCandidate({
    required String? userId,
    required String songId,
    required ExternalMetadataCandidate candidate,
    DateTime? now,
  }) async {
    applyCount++;
    lastSongId = songId;
    lastUserId = userId;
    lastCandidate = candidate;

    final callback = onApply;
    if (callback != null) {
      await callback(candidate);
    }

    return const ExternalMetadataApplicationResult(
      changedFields: {'song.title'},
    );
  }
}

class UnusedSyncMutationRunner implements SyncMutationRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('Sync mutation runner should not be used by this test.');
  }

  PlaybackState get currentState => const PlaybackState();
}

class FakeTrackStudioEditingService extends TrackProfileEditingService {
  FakeTrackStudioEditingService()
    : super(mutationRunner: UnusedTrackStudioSyncMutationRunner());

  int updateCallCount = 0;
  int structuredUpdateCallCount = 0;
  List<SongArtistCreditInput>? lastAdditionalCredits;

  String? lastUserId;
  String? lastSongId;
  String? lastTitle;
  int? lastTrackNumber;
  int? lastDiscNumber;
  List<String>? lastFeaturedArtists;
  bool? lastIsSingle;
  String? lastArtistId;
  String? lastAlbumId;
  String? lastAlbumEditionId;

  @override
  Future<TrackProfileEditResult> updateTrackWithCredits({
    required String? userId,
    required String songId,
    required String title,
    required int trackNumber,
    required int discNumber,
    required Iterable<SongArtistCreditInput> additionalCredits,
    required bool isSingle,
    String? versionLabel,
    List<SongVersionCharacteristic> versionCharacteristics = const [],
    SongReleaseStatus releaseStatus = SongReleaseStatus.released,
    bool isLeak = false,
    bool updateVersionMetadata = false,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    DateTime? now,
  }) async {
    structuredUpdateCallCount++;
    lastAdditionalCredits = List<SongArtistCreditInput>.from(additionalCredits);

    final featuredArtists = lastAdditionalCredits!
        .where((credit) => credit.role == SongArtistCreditRole.featured)
        .map((credit) => credit.creditedName)
        .toList(growable: false);

    return updateTrack(
      userId: userId,
      songId: songId,
      title: title,
      trackNumber: trackNumber,
      discNumber: discNumber,
      featuredArtists: featuredArtists,
      isSingle: isSingle,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: albumEditionId,
      now: now,
    );
  }

  @override
  Future<TrackProfileEditResult> updateTrack({
    required String? userId,
    required String songId,
    required String title,
    required int trackNumber,
    required int discNumber,
    required List<String> featuredArtists,
    required bool isSingle,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    DateTime? now,
  }) async {
    updateCallCount++;

    lastUserId = userId;
    lastSongId = songId;
    lastTitle = title;
    lastTrackNumber = trackNumber;
    lastDiscNumber = discNumber;
    lastFeaturedArtists = List<String>.from(featuredArtists);
    lastIsSingle = isSingle;
    lastArtistId = artistId;
    lastAlbumId = albumId;
    lastAlbumEditionId = albumEditionId;

    final timestamp = now ?? DateTime.utc(2026, 10, 2);

    return TrackProfileEditResult(
      song: Song(
        id: songId,
        artistId: artistId ?? 'artist-1',
        albumId: albumId ?? 'album-1',
        albumEditionId: albumEditionId ?? 'edition-1',
        title: title,
        canonicalTitle: title.trim().toLowerCase(),
        trackNumber: trackNumber,
        discNumber: discNumber,
        durationSeconds: 180,
        isSingle: isSingle,
        featuredArtists: List<String>.from(featuredArtists),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      changed: true,
    );
  }
}

class UnusedTrackStudioSyncMutationRunner implements SyncMutationRunner {
  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    throw StateError('Sync mutation runner should not be used by this fake.');
  }
}

class FakeSongArtistCreditRepository implements SongArtistCreditRepository {
  FakeSongArtistCreditRepository({this.credits = const []});

  final List<SongArtistCredit> credits;

  @override
  Future<List<SongArtistCredit>> getBySongId(String songId) async {
    return credits
        .where((credit) => credit.songId == songId)
        .toList(growable: false);
  }

  @override
  Future<void> create(SongArtistCredit credit) async {}

  @override
  Future<void> save(SongArtistCredit credit) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> deleteBySongId(String songId) async {}

  @override
  Future<SongArtistCredit?> getById(String id) async => null;

  @override
  Future<List<SongArtistCredit>> getByArtistId(String artistId) async {
    return credits
        .where((credit) => credit.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<SongArtistCredit>> getUnlinkedByCanonicalName(
    String canonicalName,
  ) async {
    return credits
        .where(
          (credit) =>
              credit.artistId == null &&
              credit.canonicalCreditedName == canonicalName,
        )
        .toList(growable: false);
  }
}
