import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/domain/services/metadata_authority_policy.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_cancellation.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_album_edition_assignment_service.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_album_edition_import_service.dart';
import 'package:sonus_next/features/artwork/application/models/cover_art_archive_image.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_candidate_discovery_service.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_archive_client.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_http_transport.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/presentation/scopes/account_scope.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_proposal.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_proposal_service.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_application_service.dart';
import 'package:sonus_next/features/library/application/services/metadata_provider.dart';
import 'package:sonus_next/features/library/application/services/album_edition_track_ordering_service.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/presentation/controllers/album_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/pages/album_profile_page.dart';
import 'package:sonus_next/features/library/presentation/pages/album_studio_page.dart';
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

    testWidgets('edition selector switches the full album presentation', (
      tester,
    ) async {
      final repository = FakeEditionAwareLibraryQueryRepository(
        album: createAlbum(
          title: 'Concept Album',
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
          primaryEditionType: AlbumEditionType.standard,
          releaseDate: DateTime(2024, 5, 17),
          genre: 'Pop',
        ),
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
            releaseDate: DateTime(2024, 5, 17),
            genre: 'Pop',
          ),
          createLibraryEdition(
            editionId: 'edition-deluxe',
            title: 'Concept Album Deluxe',
            type: AlbumEditionType.deluxe,
            releaseDate: DateTime(2025, 6, 20),
            genre: 'Alternative',
          ),
        ],
        editionTracks: {
          'edition-standard': [
            createTrack(
              songId: 'standard-track',
              title: 'Standard Song',
              albumEditionId: 'edition-standard',
              albumEditionTitle: 'Standard',
              albumEditionType: AlbumEditionType.standard,
              trackNumber: 1,
            ),
          ],
          'edition-deluxe': [
            createTrack(
              songId: 'deluxe-track-1',
              title: 'Deluxe Song',
              albumEditionId: 'edition-deluxe',
              albumEditionTitle: 'Concept Album Deluxe',
              albumEditionType: AlbumEditionType.deluxe,
              trackNumber: 5,
            ),
            createTrack(
              songId: 'deluxe-track-2',
              title: 'Bonus Song',
              albumEditionId: 'edition-deluxe',
              albumEditionTitle: 'Concept Album Deluxe',
              albumEditionType: AlbumEditionType.deluxe,
              trackNumber: 6,
            ),
          ],
        },
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('album-profile-edition-selector')),
        findsOneWidget,
      );

      expect(find.text('Concept Album'), findsWidgets);
      expect(find.text('Standard'), findsWidgets);
      expect(find.text('Standard Song'), findsOneWidget);
      expect(find.text('Deluxe Song'), findsNothing);

      expect(find.text('May 17, 2024 • Pop'), findsOneWidget);

      final segmentedButton = find.byKey(
        const ValueKey<String>('album-profile-edition-segmented-button'),
      );

      expect(segmentedButton, findsOneWidget);

      await tester.tap(
        find.descendant(of: segmentedButton, matching: find.text('Deluxe')),
      );

      await tester.pumpAndSettle();

      expect(find.text('Concept Album Deluxe'), findsWidgets);

      expect(
        find.byKey(
          const ValueKey<String>('album-profile-selected-edition-label'),
        ),
        findsOneWidget,
      );

      expect(find.text('Deluxe'), findsWidgets);
      expect(find.text('Standard Song'), findsNothing);
      expect(find.text('Deluxe Song'), findsOneWidget);
      expect(find.text('Bonus Song'), findsOneWidget);

      expect(find.text('June 20, 2025 • Alternative'), findsOneWidget);

      expect(find.text('2 tracks • 6 min'), findsOneWidget);
    });

    // Regression (SN-48J J1): the edition selector's horizontal scroller had
    // no PageStorage slot of its own. It shared the page list's slot, so when
    // it was rebuilt while scrolling back up it reopened at the page's
    // vertical offset instead of its first edition.
    testWidgets('edition selector keeps its own horizontal scroll position', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = FakeEditionAwareLibraryQueryRepository(
        album: createAlbum(
          title: 'Long Album',
          primaryEditionId: 'edition-0',
          primaryEditionTitle: 'Standard',
          primaryEditionType: AlbumEditionType.standard,
        ),
        editions: [
          for (var i = 0; i < 6; i++)
            createLibraryEdition(
              editionId: 'edition-$i',
              title: i == 0 ? 'Standard' : 'Alternate Release Number $i',
              type: i == 0 ? AlbumEditionType.standard : AlbumEditionType.other,
              isPrimary: i == 0,
            ),
        ],
        editionTracks: {
          'edition-0': [
            for (var number = 1; number <= 40; number++)
              createTrack(
                songId: 'song-$number',
                title: 'Song $number',
                albumEditionId: 'edition-0',
                albumEditionTitle: 'Standard',
                albumEditionType: AlbumEditionType.standard,
                trackNumber: number,
              ),
          ],
        },
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      final selectorFinder = find.descendant(
        of: find.byKey(
          const ValueKey<String>('album-profile-edition-selector'),
        ),
        matching: find.byType(Scrollable),
      );
      ScrollableState selector() =>
          tester.state<ScrollableState>(selectorFinder.first);
      ScrollableState page() => tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(
                const PageStorageKey<String>('album-profile-scroll'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );

      expect(selector().position.maxScrollExtent, greaterThan(0));
      expect(selector().position.pixels, 0);

      // Scroll to the end so the selector is disposed and the page stores
      // its offset; the lazy extent grows, so jump until it settles.
      for (var i = 0; i < 10; i++) {
        final end = page().position.maxScrollExtent;
        page().position.jumpTo(end);
        await tester.pumpAndSettle();
        if (page().position.maxScrollExtent == end) break;
      }
      expect(selectorFinder, findsNothing);

      // Scroll back up the way a fling does: the selector is rebuilt while
      // the page is still moving.
      unawaited(
        page().position.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
      );
      await tester.pumpAndSettle();

      expect(selector().position.pixels, 0);
    });

    testWidgets('single explicit edition does not show edition selector', (
      tester,
    ) async {
      final repository = FakeEditionAwareLibraryQueryRepository(
        album: createAlbum(
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
        ),
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
        ],
        editionTracks: {
          'edition-standard': [
            createTrack(
              songId: 'only-song',
              albumEditionId: 'edition-standard',
              albumEditionTitle: 'Standard',
            ),
          ],
        },
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('album-profile-edition-selector')),
        findsNothing,
      );

      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('only-song'), findsNothing);
    });
    testWidgets('ghosts unavailable tracks from album count and summary', (
      tester,
    ) async {
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
        findsNothing,
      );

      expect(find.textContaining('1 track'), findsWidgets);
      expect(find.textContaining('2 tracks'), findsNothing);
    });

    testWidgets(
      'all unavailable album tracks present as an empty current album',
      (tester) async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(songId: 'missing-1', filePath: '', isAvailable: false),
            createTrack(songId: 'missing-2', filePath: '', isAvailable: false),
          ],
        );

        await tester.pumpWidget(buildSubject(repository: repository));
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const ValueKey<String>('album-profile-availability-notice'),
          ),
          findsNothing,
        );

        expect(find.textContaining('0 tracks'), findsWidgets);
        expect(find.text('No tracks yet'), findsOneWidget);
      },
    );

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

      expect(find.text('Album Studio'), findsOneWidget);
      expect(find.text('Edit album details'), findsNothing);
      expect(find.text('Change artwork'), findsNothing);
      expect(find.text('Clear artwork'), findsNothing);

      await tester.tap(find.text('Album Studio'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-studio-edit-details')),
      );
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
      expect(find.text('Album details updated.'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('album-studio-page')),
        findsNothing,
      );
      expect(find.text('Renamed Album'), findsWidgets);
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

      await tester.tap(find.text('Album Studio'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-studio-edit-details')),
      );
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
      await tester.tap(find.text('Album Studio'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-studio-edit-details')),
      );
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
      await tester.tap(find.text('Album Studio'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-studio-edit-details')),
      );
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

    testWidgets('signed-out user can edit album details locally', (
      tester,
    ) async {
      final editingService = FakeAlbumProfileEditingService();

      await tester.pumpWidget(
        buildSubject(
          repository: FakeLibraryQueryRepository(
            album: createAlbum(
              primaryEditionId: 'edition-primary',
              primaryEditionTitle: 'Standard',
              primaryEditionType: AlbumEditionType.standard,
            ),
          ),
          accountRepository: FakeAccountRepository(),
          albumProfileEditingService: editingService,
        ),
      );

      await tester.pumpAndSettle();

      final menu = tester.widget<PopupMenuButton>(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );

      expect(menu.enabled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Album Studio'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-studio-edit-details')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('album-title-field')),
        'Anonymous Album Edit',
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(editingService.updateCallCount, 1);
      expect(editingService.lastUserId, isNull);
      expect(editingService.lastAlbumId, 'album-1');
      expect(editingService.lastPrimaryEditionId, 'edition-primary');
      expect(editingService.lastTitle, 'Anonymous Album Edit');
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

    testWidgets('ghosts unavailable tracks from the album profile', (
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

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('album-track-missing-song')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('album-track-menu-missing-song')),
        findsNothing,
      );
      expect(find.text('Missing Song'), findsNothing);
    });

    testWidgets('ghosted album track exposes no row menu', (tester) async {
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

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('album-track-missing-song')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('album-track-menu-missing-song')),
        findsNothing,
      );
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

    testWidgets(
      'Album Studio opens and single-disc placement hides disc by default',
      (tester) async {
        final repository = FakeEditionAwareLibraryQueryRepository(
          album: createAlbum(
            primaryEditionId: 'edition-standard',
            primaryEditionTitle: 'Standard',
          ),
          editions: [
            createLibraryEdition(
              editionId: 'edition-standard',
              title: 'Standard',
              type: AlbumEditionType.standard,
              isPrimary: true,
            ),
          ],
          editionTracks: {
            'edition-standard': [
              createTrack(
                songId: 'studio-song',
                title: 'Studio Song',
                albumEditionId: 'edition-standard',
                albumEditionTitle: 'Standard',
                trackNumber: 2,
                discNumber: 1,
              ),
            ],
          },
        );

        final service = FakeAlbumEditionTrackOrderingService();

        await tester.pumpWidget(
          buildSubject(
            repository: repository,
            albumEditionTrackOrderingService: service,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Album Studio'), findsOneWidget);

        await tester.tap(find.text('Album Studio'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('album-studio-page')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('album-studio-track-studio-song')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey<String>('album-studio-placement-studio-song'),
          ),
          findsOneWidget,
        );
        expect(find.text('Track 2'), findsOneWidget);
        expect(find.textContaining('Disc 1'), findsNothing);

        await tester.tap(
          find.byKey(
            const ValueKey<String>('album-studio-edit-placement-studio-song'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('album-studio-track-number-field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('album-studio-disc-number-field')),
          findsNothing,
        );
        expect(find.text('Edit disc number'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey<String>('album-studio-track-number-field')),
          '7',
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('album-studio-save-placement')),
        );
        await tester.pumpAndSettle();

        expect(service.placementCallCount, 1);
        expect(service.lastEditionId, 'edition-standard');
        expect(service.lastSongId, 'studio-song');
        expect(service.lastDiscNumber, 1);
        expect(service.lastTrackNumber, 7);
      },
    );

    testWidgets(
      'Album Studio routes artwork actions through management controls',
      (tester) async {
        final controller = AlbumProfileController(
          repository: FakeLibraryQueryRepository(album: createAlbum()),
          albumId: 'album-1',
        );

        addTearDown(controller.dispose);

        await controller.load();

        var changeArtworkCallCount = 0;
        var clearArtworkCallCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: AlbumStudioPage(
              controller: controller,
              userId: null,
              onChangeArtwork: () async {
                changeArtworkCallCount++;
              },
              onClearArtwork: () async {
                clearArtworkCallCount++;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final changeArtwork = find.byKey(
          const ValueKey<String>('album-studio-change-artwork'),
        );
        final clearArtwork = find.byKey(
          const ValueKey<String>('album-studio-clear-artwork'),
        );

        expect(changeArtwork, findsOneWidget);
        expect(clearArtwork, findsOneWidget);

        await tester.tap(changeArtwork);
        await tester.pumpAndSettle();

        expect(changeArtworkCallCount, 1);
        expect(clearArtworkCallCount, 0);

        await tester.tap(clearArtwork);
        await tester.pumpAndSettle();

        expect(changeArtworkCallCount, 1);
        expect(clearArtworkCallCount, 1);
      },
    );
    testWidgets('Album Studio browses CAA without applying metadata', (
      tester,
    ) async {
      const releaseGroupId = '22222222-2222-4222-8222-222222222222';

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: releaseGroupId,
        releaseGroupId: releaseGroupId,
        displayName: 'Matched Album',
      );

      const image = CoverArtArchiveImage(
        entity: CoverArtArchiveEntity.releaseGroup,
        entityId: releaseGroupId,
        imageUrl: 'https://coverartarchive.org/test.jpg',
        front: true,
        back: false,
      );

      final originalAlbum = createAlbum(
        title: 'Original Album',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      );

      final repository = FakeEditionAwareLibraryQueryRepository(
        album: originalAlbum,
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
        ],
        editionTracks: const {'edition-standard': []},
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      addTearDown(controller.dispose);
      await controller.load();

      final provider = FakeAlbumMetadataProvider(results: [candidate]);

      final client = FakeAlbumCoverArtClient(
        responses: {
          'release-group:$releaseGroupId': [image],
        },
      );

      final discovery = CoverArtCandidateDiscoveryService(client: client);

      final applicationService = FakeAlbumExternalMetadataApplicationService(
        onApply:
            ({
              required String? userId,
              required String albumId,
              required ExternalMetadataCandidate candidate,
            }) async => throw StateError('Metadata application is forbidden.'),
      );

      final importService = RecordingCoverArtImportService(
        result: const CoverArtAlbumEditionAssignmentResult(
          decision: MetadataReplacementDecision.accept,
          changed: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumStudioPage(
            controller: controller,
            userId: null,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            coverArtCandidateDiscoveryService: discovery,
            coverArtAlbumEditionImportService: importService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final searchTile = find.byKey(
        const ValueKey<String>('album-studio-search-cover-art'),
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);

      await tester.tap(searchTile);
      await tester.pumpAndSettle();

      // CAA action disabled during browsing.
      expect(tester.widget<ListTile>(searchTile).enabled, isFalse);
      expect(provider.searchCallCount, 1);
      expect(provider.lastQuery?.entityKind, ExternalMetadataEntityKind.album);
      expect(provider.lastQuery?.title, 'Original Album');

      await tester.tap(
        find.byKey(
          const ValueKey<String>('cover-art-album-result-$releaseGroupId'),
        ),
      );

      await tester.pumpAndSettle();

      expect(client.requests, ['release-group:$releaseGroupId']);

      expect(
        find.byKey(const ValueKey<String>('cover-art-image-selection-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('cover-art-image-option-0')),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('album-studio-cover-art-import-success'),
        ),
        findsOneWidget,
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);
      expect(importService.importCallCount, 1);
      expect(importService.lastEditionId, 'edition-standard');
      expect(importService.lastUserId, isNull);
      expect(importService.lastImage, same(image));
      expect(applicationService.applyCallCount, 0);
      expect(controller.album?.title, 'Original Album');
      expect(controller.album?.albumId, 'album-1');
    });
    testWidgets(
      'Album Studio imports CAA artwork into selected Deluxe edition',
      (tester) async {
        const releaseGroupId = '22222222-2222-4222-8222-222222222222';

        const candidate = ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.album,
          providerEntityId: releaseGroupId,
          releaseGroupId: releaseGroupId,
          displayName: 'Matched Album',
        );

        const image = CoverArtArchiveImage(
          entity: CoverArtArchiveEntity.releaseGroup,
          entityId: releaseGroupId,
          imageUrl: 'https://coverartarchive.org/test.jpg',
          front: true,
          back: false,
        );

        final originalAlbum = createAlbum(
          title: 'Original Album',
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
        );

        final repository = FakeEditionAwareLibraryQueryRepository(
          album: originalAlbum,
          editions: [
            createLibraryEdition(
              editionId: 'edition-standard',
              title: 'Standard',
              type: AlbumEditionType.standard,
              isPrimary: true,
            ),
            createLibraryEdition(
              editionId: 'edition-deluxe',
              title: 'Deluxe',
              type: AlbumEditionType.deluxe,
              isPrimary: false,
            ),
          ],
          editionTracks: const {'edition-standard': [], 'edition-deluxe': []},
        );

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
        );

        addTearDown(controller.dispose);
        await controller.load();
        expect(await controller.selectEdition('edition-deluxe'), isTrue);
        expect(controller.selectedEdition?.editionId, 'edition-deluxe');

        final provider = FakeAlbumMetadataProvider(results: [candidate]);

        final client = FakeAlbumCoverArtClient(
          responses: {
            'release-group:$releaseGroupId': [image],
          },
        );

        final discovery = CoverArtCandidateDiscoveryService(client: client);

        final applicationService = FakeAlbumExternalMetadataApplicationService(
          onApply:
              ({
                required String? userId,
                required String albumId,
                required ExternalMetadataCandidate candidate,
              }) async =>
                  throw StateError('Metadata application is forbidden.'),
        );

        final importService = RecordingCoverArtImportService(
          result: const CoverArtAlbumEditionAssignmentResult(
            decision: MetadataReplacementDecision.accept,
            changed: true,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AlbumStudioPage(
              controller: controller,
              userId: null,
              metadataProvider: provider,
              externalMetadataApplicationService: applicationService,
              coverArtCandidateDiscoveryService: discovery,
              coverArtAlbumEditionImportService: importService,
            ),
          ),
        );

        await tester.pumpAndSettle();

        final searchTile = find.byKey(
          const ValueKey<String>('album-studio-search-cover-art'),
        );

        expect(tester.widget<ListTile>(searchTile).enabled, isTrue);

        await tester.tap(searchTile);
        await tester.pumpAndSettle();

        // CAA action disabled during browsing.
        expect(tester.widget<ListTile>(searchTile).enabled, isFalse);
        expect(provider.searchCallCount, 1);
        expect(
          provider.lastQuery?.entityKind,
          ExternalMetadataEntityKind.album,
        );
        expect(provider.lastQuery?.title, 'Original Album');

        await tester.tap(
          find.byKey(
            const ValueKey<String>('cover-art-album-result-$releaseGroupId'),
          ),
        );

        await tester.pumpAndSettle();

        expect(client.requests, ['release-group:$releaseGroupId']);

        expect(
          find.byKey(
            const ValueKey<String>('cover-art-image-selection-dialog'),
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('cover-art-image-option-0')),
        );

        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const ValueKey<String>('album-studio-cover-art-import-success'),
          ),
          findsOneWidget,
        );

        expect(tester.widget<ListTile>(searchTile).enabled, isTrue);
        expect(importService.importCallCount, 1);
        expect(importService.lastEditionId, 'edition-deluxe');
        expect(importService.lastUserId, isNull);
        expect(importService.lastImage, same(image));
        expect(applicationService.applyCallCount, 0);
        expect(controller.album?.title, 'Original Album');
        expect(controller.album?.albumId, 'album-1');
      },
    );
    testWidgets('Album Studio handles unchanged CAA artwork', (tester) async {
      const releaseGroupId = '22222222-2222-4222-8222-222222222222';

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: releaseGroupId,
        releaseGroupId: releaseGroupId,
        displayName: 'Matched Album',
      );

      const image = CoverArtArchiveImage(
        entity: CoverArtArchiveEntity.releaseGroup,
        entityId: releaseGroupId,
        imageUrl: 'https://coverartarchive.org/test.jpg',
        front: true,
        back: false,
      );

      final originalAlbum = createAlbum(
        title: 'Original Album',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      );

      final repository = FakeEditionAwareLibraryQueryRepository(
        album: originalAlbum,
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
        ],
        editionTracks: const {'edition-standard': []},
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      addTearDown(controller.dispose);
      await controller.load();

      final provider = FakeAlbumMetadataProvider(results: [candidate]);

      final client = FakeAlbumCoverArtClient(
        responses: {
          'release-group:$releaseGroupId': [image],
        },
      );

      final discovery = CoverArtCandidateDiscoveryService(client: client);

      final applicationService = FakeAlbumExternalMetadataApplicationService(
        onApply:
            ({
              required String? userId,
              required String albumId,
              required ExternalMetadataCandidate candidate,
            }) async => throw StateError('Metadata application is forbidden.'),
      );

      final importService = RecordingCoverArtImportService(
        result: const CoverArtAlbumEditionAssignmentResult(
          decision: MetadataReplacementDecision.accept,
          changed: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumStudioPage(
            controller: controller,
            userId: null,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            coverArtCandidateDiscoveryService: discovery,
            coverArtAlbumEditionImportService: importService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final searchTile = find.byKey(
        const ValueKey<String>('album-studio-search-cover-art'),
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);

      await tester.tap(searchTile);
      await tester.pumpAndSettle();

      // CAA action disabled during browsing.
      expect(tester.widget<ListTile>(searchTile).enabled, isFalse);
      expect(provider.searchCallCount, 1);
      expect(provider.lastQuery?.entityKind, ExternalMetadataEntityKind.album);
      expect(provider.lastQuery?.title, 'Original Album');

      await tester.tap(
        find.byKey(
          const ValueKey<String>('cover-art-album-result-$releaseGroupId'),
        ),
      );

      await tester.pumpAndSettle();

      expect(client.requests, ['release-group:$releaseGroupId']);

      expect(
        find.byKey(const ValueKey<String>('cover-art-image-selection-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('cover-art-image-option-0')),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('album-studio-cover-art-import-unchanged'),
        ),
        findsOneWidget,
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);
      expect(importService.importCallCount, 1);
      expect(importService.lastEditionId, 'edition-standard');
      expect(importService.lastUserId, isNull);
      expect(importService.lastImage, same(image));
      expect(applicationService.applyCallCount, 0);
      expect(controller.album?.title, 'Original Album');
      expect(controller.album?.albumId, 'album-1');
    });
    testWidgets('Album Studio handles CAA artwork import failure', (
      tester,
    ) async {
      const releaseGroupId = '22222222-2222-4222-8222-222222222222';

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: releaseGroupId,
        releaseGroupId: releaseGroupId,
        displayName: 'Matched Album',
      );

      const image = CoverArtArchiveImage(
        entity: CoverArtArchiveEntity.releaseGroup,
        entityId: releaseGroupId,
        imageUrl: 'https://coverartarchive.org/test.jpg',
        front: true,
        back: false,
      );

      final originalAlbum = createAlbum(
        title: 'Original Album',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      );

      final repository = FakeEditionAwareLibraryQueryRepository(
        album: originalAlbum,
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
        ],
        editionTracks: const {'edition-standard': []},
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      addTearDown(controller.dispose);
      await controller.load();

      final provider = FakeAlbumMetadataProvider(results: [candidate]);

      final client = FakeAlbumCoverArtClient(
        responses: {
          'release-group:$releaseGroupId': [image],
        },
      );

      final discovery = CoverArtCandidateDiscoveryService(client: client);

      final applicationService = FakeAlbumExternalMetadataApplicationService(
        onApply:
            ({
              required String? userId,
              required String albumId,
              required ExternalMetadataCandidate candidate,
            }) async => throw StateError('Metadata application is forbidden.'),
      );

      final importService = RecordingCoverArtImportService(
        result: const CoverArtAlbumEditionAssignmentResult(
          decision: MetadataReplacementDecision.accept,
          changed: true,
        ),
        failure: StateError('Simulated artwork import failure'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumStudioPage(
            controller: controller,
            userId: null,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            coverArtCandidateDiscoveryService: discovery,
            coverArtAlbumEditionImportService: importService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final searchTile = find.byKey(
        const ValueKey<String>('album-studio-search-cover-art'),
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);

      await tester.tap(searchTile);
      await tester.pumpAndSettle();

      // CAA action disabled during browsing.
      expect(tester.widget<ListTile>(searchTile).enabled, isFalse);
      expect(provider.searchCallCount, 1);
      expect(provider.lastQuery?.entityKind, ExternalMetadataEntityKind.album);
      expect(provider.lastQuery?.title, 'Original Album');

      await tester.tap(
        find.byKey(
          const ValueKey<String>('cover-art-album-result-$releaseGroupId'),
        ),
      );

      await tester.pumpAndSettle();

      expect(client.requests, ['release-group:$releaseGroupId']);

      expect(
        find.byKey(const ValueKey<String>('cover-art-image-selection-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('cover-art-image-option-0')),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('album-studio-cover-art-import-error'),
        ),
        findsOneWidget,
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);
      expect(importService.importCallCount, 1);
      expect(importService.lastEditionId, 'edition-standard');
      expect(importService.lastUserId, isNull);
      expect(importService.lastImage, same(image));
      expect(applicationService.applyCallCount, 0);
      expect(controller.album?.title, 'Original Album');
      expect(controller.album?.albumId, 'album-1');
    });
    testWidgets('Album Studio preserves manually protected CAA artwork', (
      tester,
    ) async {
      const releaseGroupId = '22222222-2222-4222-8222-222222222222';

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: releaseGroupId,
        releaseGroupId: releaseGroupId,
        displayName: 'Matched Album',
      );

      const image = CoverArtArchiveImage(
        entity: CoverArtArchiveEntity.releaseGroup,
        entityId: releaseGroupId,
        imageUrl: 'https://coverartarchive.org/test.jpg',
        front: true,
        back: false,
      );

      final originalAlbum = createAlbum(
        title: 'Original Album',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      );

      final repository = FakeEditionAwareLibraryQueryRepository(
        album: originalAlbum,
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
        ],
        editionTracks: const {'edition-standard': []},
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      addTearDown(controller.dispose);
      await controller.load();

      final provider = FakeAlbumMetadataProvider(results: [candidate]);

      final client = FakeAlbumCoverArtClient(
        responses: {
          'release-group:$releaseGroupId': [image],
        },
      );

      final discovery = CoverArtCandidateDiscoveryService(client: client);

      final applicationService = FakeAlbumExternalMetadataApplicationService(
        onApply:
            ({
              required String? userId,
              required String albumId,
              required ExternalMetadataCandidate candidate,
            }) async => throw StateError('Metadata application is forbidden.'),
      );

      final importService = RecordingCoverArtImportService(
        result: const CoverArtAlbumEditionAssignmentResult(
          decision: MetadataReplacementDecision.rejectLowerAuthority,
          changed: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumStudioPage(
            controller: controller,
            userId: null,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            coverArtCandidateDiscoveryService: discovery,
            coverArtAlbumEditionImportService: importService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final searchTile = find.byKey(
        const ValueKey<String>('album-studio-search-cover-art'),
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);

      await tester.tap(searchTile);
      await tester.pumpAndSettle();

      // CAA action disabled during browsing.
      expect(tester.widget<ListTile>(searchTile).enabled, isFalse);
      expect(provider.searchCallCount, 1);
      expect(provider.lastQuery?.entityKind, ExternalMetadataEntityKind.album);
      expect(provider.lastQuery?.title, 'Original Album');

      await tester.tap(
        find.byKey(
          const ValueKey<String>('cover-art-album-result-$releaseGroupId'),
        ),
      );

      await tester.pumpAndSettle();

      expect(client.requests, ['release-group:$releaseGroupId']);

      expect(
        find.byKey(const ValueKey<String>('cover-art-image-selection-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('cover-art-image-option-0')),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('album-studio-cover-art-import-protected'),
        ),
        findsOneWidget,
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);
      expect(importService.importCallCount, 1);
      expect(importService.lastEditionId, 'edition-standard');
      expect(importService.lastUserId, isNull);
      expect(importService.lastImage, same(image));
      expect(applicationService.applyCallCount, 0);
      expect(controller.album?.title, 'Original Album');
      expect(controller.album?.albumId, 'album-1');
    });
    testWidgets('Album Studio preserves CAA artwork with unknown authority', (
      tester,
    ) async {
      const releaseGroupId = '22222222-2222-4222-8222-222222222222';

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: releaseGroupId,
        releaseGroupId: releaseGroupId,
        displayName: 'Matched Album',
      );

      const image = CoverArtArchiveImage(
        entity: CoverArtArchiveEntity.releaseGroup,
        entityId: releaseGroupId,
        imageUrl: 'https://coverartarchive.org/test.jpg',
        front: true,
        back: false,
      );

      final originalAlbum = createAlbum(
        title: 'Original Album',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      );

      final repository = FakeEditionAwareLibraryQueryRepository(
        album: originalAlbum,
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
        ],
        editionTracks: const {'edition-standard': []},
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      addTearDown(controller.dispose);
      await controller.load();

      final provider = FakeAlbumMetadataProvider(results: [candidate]);

      final client = FakeAlbumCoverArtClient(
        responses: {
          'release-group:$releaseGroupId': [image],
        },
      );

      final discovery = CoverArtCandidateDiscoveryService(client: client);

      final applicationService = FakeAlbumExternalMetadataApplicationService(
        onApply:
            ({
              required String? userId,
              required String albumId,
              required ExternalMetadataCandidate candidate,
            }) async => throw StateError('Metadata application is forbidden.'),
      );

      final importService = RecordingCoverArtImportService(
        result: const CoverArtAlbumEditionAssignmentResult(
          decision: MetadataReplacementDecision.requireReviewUnknownAuthority,
          changed: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumStudioPage(
            controller: controller,
            userId: null,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            coverArtCandidateDiscoveryService: discovery,
            coverArtAlbumEditionImportService: importService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final searchTile = find.byKey(
        const ValueKey<String>('album-studio-search-cover-art'),
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);

      await tester.tap(searchTile);
      await tester.pumpAndSettle();

      // CAA action disabled during browsing.
      expect(tester.widget<ListTile>(searchTile).enabled, isFalse);
      expect(provider.searchCallCount, 1);
      expect(provider.lastQuery?.entityKind, ExternalMetadataEntityKind.album);
      expect(provider.lastQuery?.title, 'Original Album');

      await tester.tap(
        find.byKey(
          const ValueKey<String>('cover-art-album-result-$releaseGroupId'),
        ),
      );

      await tester.pumpAndSettle();

      expect(client.requests, ['release-group:$releaseGroupId']);

      expect(
        find.byKey(const ValueKey<String>('cover-art-image-selection-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('cover-art-image-option-0')),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('album-studio-cover-art-import-protected'),
        ),
        findsOneWidget,
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);
      expect(importService.importCallCount, 1);
      expect(importService.lastEditionId, 'edition-standard');
      expect(importService.lastUserId, isNull);
      expect(importService.lastImage, same(image));
      expect(applicationService.applyCallCount, 0);
      expect(controller.album?.title, 'Original Album');
      expect(controller.album?.albumId, 'album-1');
    });
    testWidgets('Album Studio cancels CAA artwork selection', (tester) async {
      const releaseGroupId = '22222222-2222-4222-8222-222222222222';

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: releaseGroupId,
        releaseGroupId: releaseGroupId,
        displayName: 'Matched Album',
      );

      const image = CoverArtArchiveImage(
        entity: CoverArtArchiveEntity.releaseGroup,
        entityId: releaseGroupId,
        imageUrl: 'https://coverartarchive.org/test.jpg',
        front: true,
        back: false,
      );

      final originalAlbum = createAlbum(
        title: 'Original Album',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      );

      final repository = FakeEditionAwareLibraryQueryRepository(
        album: originalAlbum,
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
        ],
        editionTracks: const {'edition-standard': []},
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      addTearDown(controller.dispose);
      await controller.load();

      final provider = FakeAlbumMetadataProvider(results: [candidate]);

      final client = FakeAlbumCoverArtClient(
        responses: {
          'release-group:$releaseGroupId': [image],
        },
      );

      final discovery = CoverArtCandidateDiscoveryService(client: client);

      final applicationService = FakeAlbumExternalMetadataApplicationService(
        onApply:
            ({
              required String? userId,
              required String albumId,
              required ExternalMetadataCandidate candidate,
            }) async => throw StateError('Metadata application is forbidden.'),
      );

      final importService = RecordingCoverArtImportService(
        result: const CoverArtAlbumEditionAssignmentResult(
          decision: MetadataReplacementDecision.accept,
          changed: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumStudioPage(
            controller: controller,
            userId: null,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            coverArtCandidateDiscoveryService: discovery,
            coverArtAlbumEditionImportService: importService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final searchTile = find.byKey(
        const ValueKey<String>('album-studio-search-cover-art'),
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);

      await tester.tap(searchTile);
      await tester.pumpAndSettle();

      expect(provider.searchCallCount, 1);
      expect(provider.lastQuery?.entityKind, ExternalMetadataEntityKind.album);
      expect(provider.lastQuery?.title, 'Original Album');

      await tester.tap(
        find.byKey(
          const ValueKey<String>('cover-art-album-result-$releaseGroupId'),
        ),
      );

      await tester.pumpAndSettle();

      expect(client.requests, ['release-group:$releaseGroupId']);

      expect(
        find.byKey(const ValueKey<String>('cover-art-image-selection-dialog')),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('cover-art-image-selection-dialog')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>('album-studio-cover-art-selected-message'),
        ),
        findsNothing,
      );
      expect(importService.importCallCount, 0);
      expect(applicationService.applyCallCount, 0);
      expect(controller.album?.title, 'Original Album');
      expect(controller.album?.albumId, 'album-1');
    });
    testWidgets('Album Studio shows empty CAA artwork results', (tester) async {
      const releaseGroupId = '22222222-2222-4222-8222-222222222222';

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: releaseGroupId,
        releaseGroupId: releaseGroupId,
        displayName: 'Matched Album',
      );

      final originalAlbum = createAlbum(
        title: 'Original Album',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      );

      final repository = FakeEditionAwareLibraryQueryRepository(
        album: originalAlbum,
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
        ],
        editionTracks: const {'edition-standard': []},
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      addTearDown(controller.dispose);
      await controller.load();

      final provider = FakeAlbumMetadataProvider(results: [candidate]);

      final client = FakeAlbumCoverArtClient();

      final discovery = CoverArtCandidateDiscoveryService(client: client);

      final applicationService = FakeAlbumExternalMetadataApplicationService(
        onApply:
            ({
              required String? userId,
              required String albumId,
              required ExternalMetadataCandidate candidate,
            }) async => throw StateError('Metadata application is forbidden.'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumStudioPage(
            controller: controller,
            userId: null,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            coverArtCandidateDiscoveryService: discovery,
            coverArtAlbumEditionImportService: _UnusedCoverArtImportService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final searchTile = find.byKey(
        const ValueKey<String>('album-studio-search-cover-art'),
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);

      await tester.tap(searchTile);
      await tester.pumpAndSettle();

      expect(provider.searchCallCount, 1);
      expect(provider.lastQuery?.entityKind, ExternalMetadataEntityKind.album);
      expect(provider.lastQuery?.title, 'Original Album');

      await tester.tap(
        find.byKey(
          const ValueKey<String>('cover-art-album-result-$releaseGroupId'),
        ),
      );

      await tester.pumpAndSettle();

      expect(client.requests, ['release-group:$releaseGroupId']);

      expect(
        find.byKey(const ValueKey<String>('cover-art-image-selection-dialog')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('cover-art-image-empty')),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('cover-art-image-selection-dialog')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>('album-studio-cover-art-selected-message'),
        ),
        findsNothing,
      );
      expect(applicationService.applyCallCount, 0);
      expect(controller.album?.title, 'Original Album');
      expect(controller.album?.albumId, 'album-1');
    });
    testWidgets('Album Studio handles CAA discovery failure', (tester) async {
      const releaseGroupId = '22222222-2222-4222-8222-222222222222';

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: releaseGroupId,
        releaseGroupId: releaseGroupId,
        displayName: 'Matched Album',
      );

      final originalAlbum = createAlbum(
        title: 'Original Album',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      );

      final repository = FakeEditionAwareLibraryQueryRepository(
        album: originalAlbum,
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
        ],
        editionTracks: const {'edition-standard': []},
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      addTearDown(controller.dispose);
      await controller.load();

      final provider = FakeAlbumMetadataProvider(results: [candidate]);

      final client = FakeAlbumCoverArtClient(
        failure: StateError('CAA unavailable'),
      );

      final discovery = CoverArtCandidateDiscoveryService(client: client);

      final applicationService = FakeAlbumExternalMetadataApplicationService(
        onApply:
            ({
              required String? userId,
              required String albumId,
              required ExternalMetadataCandidate candidate,
            }) async => throw StateError('Metadata application is forbidden.'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumStudioPage(
            controller: controller,
            userId: null,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            coverArtCandidateDiscoveryService: discovery,
            coverArtAlbumEditionImportService: _UnusedCoverArtImportService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final searchTile = find.byKey(
        const ValueKey<String>('album-studio-search-cover-art'),
      );

      expect(tester.widget<ListTile>(searchTile).enabled, isTrue);

      await tester.tap(searchTile);
      await tester.pumpAndSettle();

      expect(provider.searchCallCount, 1);
      expect(provider.lastQuery?.entityKind, ExternalMetadataEntityKind.album);
      expect(provider.lastQuery?.title, 'Original Album');

      await tester.tap(
        find.byKey(
          const ValueKey<String>('cover-art-album-result-$releaseGroupId'),
        ),
      );

      await tester.pumpAndSettle();

      expect(client.requests, ['release-group:$releaseGroupId']);

      expect(
        find.byKey(
          const ValueKey<String>('album-studio-cover-art-search-error'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('cover-art-image-selection-dialog')),
        findsNothing,
      );
      expect(applicationService.applyCallCount, 0);
      expect(controller.album?.title, 'Original Album');
      expect(controller.album?.albumId, 'album-1');
    });
    testWidgets('Album Studio disables MusicBrainz without dependencies', (
      tester,
    ) async {
      final controller = AlbumProfileController(
        repository: FakeLibraryQueryRepository(album: createAlbum()),
        albumId: 'album-1',
      );
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumStudioPage(controller: controller, userId: null),
        ),
      );
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('album-studio-search-musicbrainz')),
      );

      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);

      final coverArtTile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('album-studio-search-cover-art')),
      );

      expect(coverArtTile.enabled, isFalse);
      expect(coverArtTile.onTap, isNull);
    });

    testWidgets('Album Studio requires proposal service for MusicBrainz', (
      tester,
    ) async {
      final controller = AlbumProfileController(
        repository: FakeLibraryQueryRepository(album: createAlbum()),
        albumId: 'album-1',
      );
      addTearDown(controller.dispose);
      await controller.load();

      final provider = FakeAlbumMetadataProvider(results: const []);

      final applicationService = FakeAlbumExternalMetadataApplicationService(
        onApply:
            ({
              required String? userId,
              required String albumId,
              required ExternalMetadataCandidate candidate,
            }) async => const ExternalMetadataApplicationResult(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumStudioPage(
            controller: controller,
            userId: null,
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final finder = find.byKey(
        const ValueKey<String>('album-studio-search-musicbrainz'),
      );

      final tile = tester.widget<ListTile>(finder);

      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
      expect(provider.searchCallCount, 0);
      expect(applicationService.applyCallCount, 0);
    });
    testWidgets(
      'Album Studio MusicBrainz match refreshes album and preserves edition',
      (tester) async {
        var currentAlbum = createAlbum(
          title: 'Original Album',
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
          releaseDate: DateTime(2024, 5, 17),
          genre: 'Pop',
        );
        var loadCount = 0;

        final edition = createLibraryEdition(
          editionId: 'edition-standard',
          title: 'Standard',
          type: AlbumEditionType.standard,
          isPrimary: true,
          releaseDate: DateTime(2024, 5, 17),
          genre: 'Pop',
        );

        final repository = FakeEditionAwareLibraryQueryRepository(
          albumLoader: (_) async {
            loadCount++;
            return currentAlbum;
          },
          editions: [edition],
          editionTracks: const {'edition-standard': []},
        );

        final provider = FakeAlbumMetadataProvider(
          results: const [
            ExternalMetadataCandidate(
              provider: ExternalMetadataProviderKind.musicBrainz,
              entityKind: ExternalMetadataEntityKind.album,
              providerEntityId: 'release-group-123',
              displayName: 'Matched Album',
            ),
          ],
        );

        final applicationService = FakeAlbumExternalMetadataApplicationService(
          onApply:
              ({
                required String? userId,
                required String albumId,
                required ExternalMetadataCandidate candidate,
              }) async {
                currentAlbum = createAlbum(
                  albumId: albumId,
                  title: candidate.displayName,
                  primaryEditionId: 'edition-standard',
                  primaryEditionTitle: 'Standard',
                  releaseDate: DateTime(2024, 5, 17),
                  genre: 'Pop',
                );

                return const ExternalMetadataApplicationResult(
                  changedFields: {'title'},
                );
              },
        );

        final proposalService = FakeAlbumMetadataProposalService();

        await tester.pumpWidget(
          buildSubject(
            repository: repository,
            albumProfileEditingService: FakeAlbumProfileEditingService(),
            metadataProvider: provider,
            externalMetadataApplicationService: applicationService,
            externalMetadataProposalService: proposalService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Album Studio'));
        await tester.pumpAndSettle();

        final musicBrainzTile = find.byKey(
          const ValueKey<String>('album-studio-search-musicbrainz'),
        );

        expect(tester.widget<ListTile>(musicBrainzTile).enabled, isTrue);

        await tester.tap(musicBrainzTile);
        await tester.pumpAndSettle();

        expect(provider.searchCallCount, 1);
        expect(
          provider.lastQuery?.entityKind,
          ExternalMetadataEntityKind.album,
        );
        expect(provider.lastQuery?.title, 'Original Album');
        expect(provider.lastQuery?.artistName, 'Test Artist');

        await tester.tap(find.text('Matched Album'));
        await tester.pumpAndSettle();

        expect(proposalService.previewCallCount, 1);
        expect(proposalService.lastAlbumId, 'album-1');
        expect(
          proposalService.lastCandidate?.providerEntityId,
          'release-group-123',
        );
        expect(
          find.byKey(
            const ValueKey<String>('musicbrainz-proposal-review-dialog'),
          ),
          findsOneWidget,
        );
        expect(applicationService.applyCallCount, 0);

        await tester.tap(
          find.byKey(const ValueKey<String>('musicbrainz-proposal-apply')),
        );
        await tester.pumpAndSettle();

        expect(applicationService.applyCallCount, 1);
        expect(applicationService.lastUserId, isNull);
        expect(applicationService.lastAlbumId, 'album-1');
        expect(
          applicationService.lastCandidate?.providerEntityId,
          'release-group-123',
        );

        expect(loadCount, greaterThanOrEqualTo(2));
        expect(find.text('MusicBrainz metadata applied.'), findsOneWidget);

        // The external match updates only the album's allowed field.
        expect(currentAlbum.title, 'Matched Album');
        expect(currentAlbum.primaryEditionId, 'edition-standard');
        expect(currentAlbum.releaseDate, DateTime(2024, 5, 17));
        expect(currentAlbum.genre, 'Pop');

        expect(edition.title, 'Standard');
        expect(edition.type, AlbumEditionType.standard);
        expect(edition.releaseDate, DateTime(2024, 5, 17));
        expect(edition.genre, 'Pop');

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.text('Matched Album'), findsWidgets);
      },
    );
    testWidgets('Album Studio edition selector swaps the editable track list', (
      tester,
    ) async {
      final repository = FakeEditionAwareLibraryQueryRepository(
        album: createAlbum(
          title: 'Concept Album',
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
        ),
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
          createLibraryEdition(
            editionId: 'edition-deluxe',
            title: 'Deluxe',
            type: AlbumEditionType.deluxe,
          ),
        ],
        editionTracks: {
          'edition-standard': [
            createTrack(
              songId: 'standard-studio-song',
              title: 'Standard Studio Song',
              albumEditionId: 'edition-standard',
              albumEditionTitle: 'Standard',
            ),
          ],
          'edition-deluxe': [
            createTrack(
              songId: 'deluxe-studio-song',
              title: 'Deluxe Studio Song',
              albumEditionId: 'edition-deluxe',
              albumEditionTitle: 'Deluxe',
              albumEditionType: AlbumEditionType.deluxe,
            ),
          ],
        },
      );

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          albumEditionTrackOrderingService:
              FakeAlbumEditionTrackOrderingService(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album Studio'));
      await tester.pumpAndSettle();

      expect(find.text('Standard Studio Song'), findsOneWidget);
      expect(find.text('Deluxe Studio Song'), findsNothing);

      final selector = find.byKey(
        const ValueKey<String>('album-studio-edition-selector'),
      );

      expect(selector, findsOneWidget);

      await tester.tap(
        find.descendant(of: selector, matching: find.text('Deluxe')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Standard Studio Song'), findsNothing);
      expect(find.text('Deluxe Studio Song'), findsOneWidget);
    });

    testWidgets(
      'Album Studio reorder forwards visual order and auto-renumber',
      (tester) async {
        final repository = FakeEditionAwareLibraryQueryRepository(
          album: createAlbum(
            primaryEditionId: 'edition-standard',
            primaryEditionTitle: 'Standard',
          ),
          editions: [
            createLibraryEdition(
              editionId: 'edition-standard',
              title: 'Standard',
              type: AlbumEditionType.standard,
              isPrimary: true,
            ),
          ],
          editionTracks: {
            'edition-standard': [
              createTrack(
                songId: 'song-a',
                title: 'Song A',
                albumEditionId: 'edition-standard',
                trackNumber: 1,
              ),
              createTrack(
                songId: 'song-b',
                title: 'Song B',
                albumEditionId: 'edition-standard',
                trackNumber: 2,
              ),
              createTrack(
                songId: 'song-c',
                title: 'Song C',
                albumEditionId: 'edition-standard',
                trackNumber: 3,
              ),
            ],
          },
        );

        final service = FakeAlbumEditionTrackOrderingService();

        await tester.pumpWidget(
          buildSubject(
            repository: repository,
            albumEditionTrackOrderingService: service,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Album Studio'));
        await tester.pumpAndSettle();

        final autoRenumberFinder = find.byKey(
          const ValueKey<String>('album-studio-auto-renumber'),
        );

        await tester.tap(autoRenumberFinder);
        await tester.pump();

        expect(tester.widget<SwitchListTile>(autoRenumberFinder).value, isTrue);

        final listFinder = find.byKey(
          const ValueKey<String>('album-studio-track-list'),
        );

        final list = tester.widget<ReorderableListView>(listFinder);

        list.onReorderItem!(0, 2);
        await tester.pumpAndSettle();

        expect(service.reorderCallCount, 1);
        expect(service.lastEditionId, 'edition-standard');
        expect(service.lastAutoRenumber, isTrue);
        expect(service.lastOrderedSongIds, ['song-b', 'song-c', 'song-a']);
      },
    );

    testWidgets('Album Track Studio opens from the track menu', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'studio-song', title: 'Studio Song')],
      );

      final accountRepository = FakeAccountRepository(
        currentUser: const AccountUser(id: 'user-1', email: 'user@example.com'),
      );

      final editingService = EnabledTrackStudioEditingService();
      final provider = FakeAlbumMetadataProvider(results: const []);
      final proposalService = FakeAlbumMetadataProposalService();
      final applicationService = FakeAlbumExternalMetadataApplicationService(
        onApply:
            ({
              required String? userId,
              required String albumId,
              required ExternalMetadataCandidate candidate,
            }) async {
              throw StateError('Metadata application should not be invoked.');
            },
      );

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          accountRepository: accountRepository,
          trackProfileEditingService: editingService,
          metadataProvider: provider,
          externalMetadataApplicationService: applicationService,
          externalMetadataProposalService: proposalService,
        ),
      );
      await tester.pumpAndSettle();

      final menuFinder = find.byKey(
        const ValueKey<String>('album-track-menu-studio-song'),
      );

      expect(menuFinder, findsOneWidget);

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

      final musicBrainzTile = find.byKey(
        const ValueKey<String>('track-studio-search-musicbrainz'),
      );
      expect(tester.widget<ListTile>(musicBrainzTile).enabled, isTrue);

      await tester.tap(musicBrainzTile);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('track-studio-musicbrainz-continue')),
      );
      await tester.pumpAndSettle();

      expect(provider.searchCallCount, 1);
      expect(provider.lastQuery?.entityKind, ExternalMetadataEntityKind.track);
      expect(provider.lastQuery?.title, 'Studio Song');
    });
  });
}

Widget buildSubject({
  required LibraryQueryRepository? repository,
  PlaybackCoordinator? playbackCoordinator,
  AccountRepository? accountRepository,
  AlbumProfileEditingService? albumProfileEditingService,
  AlbumEditionTrackOrderingService? albumEditionTrackOrderingService,
  TrackProfileEditingService? trackProfileEditingService,
  SongBlockService? songBlockService,
  MetadataProvider? metadataProvider,
  ExternalMetadataApplicationService? externalMetadataApplicationService,
  ExternalMetadataProposalService? externalMetadataProposalService,
}) {
  return MultiProvider(
    providers: [
      Provider<SongBlockService?>.value(value: songBlockService),
      Provider<MetadataProvider?>.value(value: metadataProvider),
      Provider<ExternalMetadataApplicationService?>.value(
        value: externalMetadataApplicationService,
      ),
      Provider<ExternalMetadataProposalService?>.value(
        value: externalMetadataProposalService,
      ),
      Provider<LibraryQueryRepository?>.value(value: repository),
      Provider<PlaybackCoordinator?>.value(value: playbackCoordinator),
      Provider<AlbumProfileEditingService?>.value(
        value: albumProfileEditingService,
      ),
      Provider<AlbumEditionTrackOrderingService?>.value(
        value: albumEditionTrackOrderingService,
      ),
      Provider<TrackProfileEditingService?>.value(
        value: trackProfileEditingService,
      ),
    ],
    child: AccountScope(
      repository: accountRepository,
      child: const MaterialApp(
        home: AlbumProfilePage(
          albumId: 'album-1',
          initialAlbumTitle: 'Test Album',
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

LibraryAlbumEdition createLibraryEdition({
  required String editionId,
  required String title,
  required AlbumEditionType type,
  bool isPrimary = false,
  DateTime? releaseDate,
  String? genre,
  String? artworkId,
  String? artworkPath,
}) {
  return LibraryAlbumEdition(
    editionId: editionId,
    albumId: 'album-1',
    title: title,
    type: type,
    isPrimary: isPrimary,
    releaseDate: releaseDate,
    genre: genre,
    artworkId: artworkId,
    artworkPath: artworkPath,
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
  int discNumber = 1,
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
    discNumber: discNumber,
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

class FakeEditionAwareLibraryQueryRepository extends FakeLibraryQueryRepository
    implements AlbumEditionQueryRepository {
  FakeEditionAwareLibraryQueryRepository({
    super.album,
    super.tracks = const [],
    super.albumError,
    super.albumLoader,
    this.editions = const [],
    this.editionTracks = const {},
  });

  final List<LibraryAlbumEdition> editions;
  final Map<String, List<LibraryTrack>> editionTracks;

  @override
  Future<List<LibraryAlbumEdition>> getAlbumEditions(String albumId) async {
    return editions;
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumEditionId(String editionId) async {
    return editionTracks[editionId] ?? const [];
  }
}

class FakeAlbumEditionTrackOrderingService
    extends AlbumEditionTrackOrderingService {
  FakeAlbumEditionTrackOrderingService()
    : super(mutationRunner: UnusedSyncMutationRunner());

  int reorderCallCount = 0;
  int placementCallCount = 0;

  String? lastUserId;
  String? lastEditionId;
  List<String>? lastOrderedSongIds;
  bool? lastAutoRenumber;
  String? lastSongId;
  int? lastDiscNumber;
  int? lastTrackNumber;

  @override
  Future<AlbumEditionReorderResult> reorderEdition({
    required String albumEditionId,
    required List<String> orderedSongIds,
    String? userId,
    bool autoRenumber = false,
    DateTime? now,
  }) async {
    reorderCallCount++;
    lastUserId = userId;
    lastEditionId = albumEditionId;
    lastOrderedSongIds = List<String>.from(orderedSongIds);
    lastAutoRenumber = autoRenumber;

    return const AlbumEditionReorderResult(memberships: [], changed: true);
  }

  @override
  Future<AlbumEditionTrackPlacementResult> updateTrackPlacement({
    required String? userId,
    required String albumEditionId,
    required String songId,
    required int discNumber,
    required int trackNumber,
    DateTime? now,
  }) async {
    placementCallCount++;
    lastUserId = userId;
    lastEditionId = albumEditionId;
    lastSongId = songId;
    lastDiscNumber = discNumber;
    lastTrackNumber = trackNumber;

    final timestamp = now ?? DateTime.utc(2026, 1, 1);

    return AlbumEditionTrackPlacementResult(
      membership: AlbumEditionTrack(
        albumEditionId: albumEditionId,
        songId: songId,
        discNumber: discNumber,
        trackNumber: trackNumber,
        sortPosition: 0,
        numberingAuthority: AlbumEditionTrackAuthority.manual,
        orderingAuthority: AlbumEditionTrackAuthority.inferred,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      changed: true,
      compatibilitySongChanged: false,
    );
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
      required String? userId,
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
    required String? userId,
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

class EnabledTrackStudioEditingService extends TrackProfileEditingService {
  EnabledTrackStudioEditingService()
    : super(mutationRunner: UnusedSyncMutationRunner());
}

class FakeAlbumMetadataProposalService extends Fake
    implements ExternalMetadataProposalService {
  int previewCallCount = 0;
  String? lastAlbumId;
  ExternalMetadataCandidate? lastCandidate;

  @override
  Future<ExternalMetadataProposal> previewAlbum({
    required String albumId,
    required ExternalMetadataCandidate candidate,
  }) async {
    previewCallCount++;
    lastAlbumId = albumId;
    lastCandidate = candidate;

    return ExternalMetadataProposal(
      entityType: MetadataEntityType.album,
      entityId: albumId,
      candidate: candidate,
      fields: [
        ExternalMetadataProposalField(
          fieldName: MetadataFields.albumTitle,
          currentValue: 'Original Album',
          proposedValue: candidate.displayName,
          status: ExternalMetadataProposalFieldStatus.valueChange,
        ),
      ],
    );
  }
}

class RecordingCoverArtImportService extends Fake
    implements CoverArtAlbumEditionImportService {
  RecordingCoverArtImportService({required this.result, this.failure});

  final CoverArtAlbumEditionAssignmentResult result;
  final Object? failure;

  int importCallCount = 0;
  String? lastEditionId;
  String? lastUserId;
  CoverArtArchiveImage? lastImage;

  @override
  Future<CoverArtAlbumEditionAssignmentResult> importImage({
    required String albumEditionId,
    required CoverArtArchiveImage image,
    String? userId,
    CoverArtCancellationToken? cancellationToken,
    DateTime? now,
  }) async {
    importCallCount++;
    lastEditionId = albumEditionId;
    lastUserId = userId;
    lastImage = image;

    if (failure != null) {
      throw failure!;
    }

    return result;
  }
}

class _UnusedCoverArtImportService extends Fake
    implements CoverArtAlbumEditionImportService {}

class FakeAlbumCoverArtClient extends CoverArtArchiveClient {
  FakeAlbumCoverArtClient({this.responses = const {}, this.failure})
    : super(transport: _UnusedCoverArtTransport(), userAgent: 'SonusTests/1.0');

  final Map<String, List<CoverArtArchiveImage>> responses;
  final Object? failure;
  final List<String> requests = [];

  @override
  Future<List<CoverArtArchiveImage>> lookup({
    required CoverArtArchiveEntity entity,
    required String id,
  }) async {
    final key = '${entity.path}:$id';
    requests.add(key);

    if (failure != null) throw failure!;

    return responses[key] ?? const [];
  }
}

class _UnusedCoverArtTransport implements MusicBrainzHttpTransport {
  @override
  Future<MusicBrainzHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) {
    throw StateError('Unexpected network request.');
  }
}

class FakeAlbumMetadataProvider implements MetadataProvider {
  FakeAlbumMetadataProvider({required this.results});

  final List<ExternalMetadataCandidate> results;
  int searchCallCount = 0;
  ExternalMetadataSearchQuery? lastQuery;

  @override
  ExternalMetadataProviderKind get providerKind =>
      ExternalMetadataProviderKind.musicBrainz;

  @override
  Future<List<ExternalMetadataCandidate>> search(
    ExternalMetadataSearchQuery query,
  ) async {
    searchCallCount++;
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

typedef FakeAlbumExternalApplyCallback =
    Future<ExternalMetadataApplicationResult> Function({
      required String? userId,
      required String albumId,
      required ExternalMetadataCandidate candidate,
    });

class FakeAlbumExternalMetadataApplicationService
    extends ExternalMetadataApplicationService {
  FakeAlbumExternalMetadataApplicationService({required this.onApply})
    : super(mutationRunner: UnusedSyncMutationRunner());

  final FakeAlbumExternalApplyCallback onApply;

  int applyCallCount = 0;
  String? lastUserId;
  String? lastAlbumId;
  ExternalMetadataCandidate? lastCandidate;

  @override
  Future<ExternalMetadataApplicationResult> applyAlbumCandidate({
    required String? userId,
    required String albumId,
    required ExternalMetadataCandidate candidate,
    DateTime? now,
  }) async {
    applyCallCount++;
    lastUserId = userId;
    lastAlbumId = albumId;
    lastCandidate = candidate;

    return onApply(userId: userId, albumId: albumId, candidate: candidate);
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
