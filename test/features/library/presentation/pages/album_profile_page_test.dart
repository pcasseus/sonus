import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_disc_label.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_disc_label_repository.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_cancellation.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_album_edition_assignment_service.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_album_edition_import_service.dart';
import 'package:sonus_next/features/artwork/application/models/cover_art_archive_image.dart';
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
import 'package:sonus_next/features/library/application/services/artist_creation_service.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
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
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/presentation/controllers/album_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/pages/album_profile_page.dart';
import 'package:sonus_next/features/library/presentation/pages/release_studio_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/song_stats/presentation/song_stats_page.dart';
import '../../../../support/release_date_editor_driver.dart';

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

    testWidgets('track rows show co-primary, featured and guest credits and '
        'the version suffix (SN-50 C-Q1/C-Q6)', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(primaryEditionTitle: 'Standard'),
        tracks: [
          createTrack(
            songId: 'song-1',
            title: 'First Song',
            coPrimaryArtists: const ['Ben Moor'],
            versionLabel: 'Acoustic',
          ),
          createTrack(
            songId: 'song-2',
            title: 'Second Song',
            trackNumber: 2,
            featuredArtists: const ['Cy Lark'],
            guestArtists: const ['Eve Shore'],
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('First Song (Acoustic)'), findsOneWidget);
      expect(find.textContaining('Test Artist & Ben Moor'), findsOneWidget);
      expect(find.textContaining('Ft. Cy Lark with Eve Shore'), findsOneWidget);
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

      // The Deluxe date is its own; genre is the release's (SN-50 A1).
      expect(find.text('June 20, 2025 • Pop'), findsOneWidget);

      expect(find.text('2 tracks • 6 min'), findsOneWidget);
    });

    // Regression (SN-48J J1, revised in J6): the edition selector's
    // horizontal scroller had no PageStorage slot of its own. It shared the
    // page list's slot, so when rebuilt while scrolling back up it reopened
    // at the page's vertical offset and its options slid out of view. Since
    // J6, editions that don't fit on one line wrap instead of scrolling.
    group('edition selector after scrolling away and back', () {
      Future<FakeEditionAwareLibraryQueryRepository> pumpEditions(
        WidgetTester tester,
        List<String> titles, {
        double width = 320,
      }) async {
        await tester.binding.setSurfaceSize(Size(width, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repository = FakeEditionAwareLibraryQueryRepository(
          album: createAlbum(
            title: 'Long Album',
            primaryEditionId: 'edition-0',
            primaryEditionTitle: 'Standard',
            primaryEditionType: AlbumEditionType.standard,
          ),
          editions: [
            for (final (i, title) in titles.indexed)
              createLibraryEdition(
                editionId: 'edition-$i',
                title: title,
                type: i == 0
                    ? AlbumEditionType.standard
                    : title == 'Deluxe'
                    ? AlbumEditionType.deluxe
                    : AlbumEditionType.other,
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
        return repository;
      }

      ScrollableState page(WidgetTester tester) =>
          tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(
                    const PageStorageKey<String>('album-profile-scroll'),
                  ),
                  matching: find.byType(Scrollable),
                )
                .first,
          );

      Future<void> scrollAwayAndFlingBack(WidgetTester tester) async {
        // The lazy extent grows, so jump until it settles; the selector is
        // disposed and the page stores its offset.
        for (var i = 0; i < 10; i++) {
          final end = page(tester).position.maxScrollExtent;
          page(tester).position.jumpTo(end);
          await tester.pumpAndSettle();
          if (page(tester).position.maxScrollExtent == end) break;
        }
        expect(
          find.byKey(const ValueKey<String>('album-profile-edition-selector')),
          findsNothing,
        );

        // Back up the way a fling does: rebuilt while the page still moves.
        unawaited(
          page(tester).position.animateTo(
            0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.linear,
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('short editions keep their own scroll storage', (
        tester,
      ) async {
        // Wide enough for the segmented control even in the test font.
        await pumpEditions(tester, ['Standard', 'Deluxe'], width: 411);

        final scroller = find.descendant(
          of: find.byKey(
            const ValueKey<String>('album-profile-edition-selector'),
          ),
          matching: find.byType(Scrollable),
        );
        expect(scroller, findsOneWidget);
        expect(
          find.ancestor(
            of: scroller,
            matching: find.byKey(
              const PageStorageKey<String>(
                'album-profile-edition-selector-scroll',
              ),
            ),
          ),
          findsOneWidget,
        );

        await scrollAwayAndFlingBack(tester);

        expect(tester.state<ScrollableState>(scroller).position.pixels, 0);
        expect(find.text('Deluxe').hitTestable(), findsOneWidget);
      });

      testWidgets('long editions stay fully visible', (tester) async {
        final titles = [
          'Standard',
          for (var i = 1; i < 6; i++) 'Alternate Release Number $i',
        ];
        await pumpEditions(tester, titles);
        await scrollAwayAndFlingBack(tester);

        // Every real edition is offered and none has slid out sideways.
        for (final title in titles.skip(1)) {
          final rect = tester.getRect(find.text(title));
          expect(rect.left, greaterThanOrEqualTo(0), reason: title);
          expect(rect.right, lessThanOrEqualTo(320), reason: title);
        }
        expect(
          find.byKey(const ValueKey<String>('album-profile-edition-choices')),
          findsOneWidget,
        );
      });
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

      // App Update 1.2 BUG-09 (supersedes the SN-35 silent gap): the hidden
      // song is said in words; without editing rights there is no action.
      expect(
        find.text("1 track isn't shown because its file is unavailable."),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('album-profile-review-unavailable')),
        findsNothing,
      );

      expect(find.textContaining('1 track •'), findsWidgets);
      expect(find.textContaining('2 tracks'), findsNothing);
    });

    testWidgets('BUG-09: no notice when every track has its file', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          repository: FakeLibraryQueryRepository(
            album: createAlbum(),
            tracks: [
              createTrack(songId: 'a'),
              createTrack(songId: 'b'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('album-profile-unavailable-notice')),
        findsNothing,
      );
    });

    testWidgets('BUG-09: hidden tracks lead to Edit Release, which lists and '
        'marks them', (tester) async {
      LibraryTrack track(String id, String title, {bool available = true}) =>
          createTrack(
            songId: id,
            title: title,
            albumEditionId: 'edition-standard',
            albumEditionTitle: 'Standard',
            filePath: available ? '/music/$id.mp3' : '',
            isAvailable: available,
          );
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
            track('here', 'Here'),
            track('gone-1', 'Gone One', available: false),
            track('gone-2', 'Gone Two', available: false),
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

      expect(
        find.text("2 tracks aren't shown because their files are unavailable."),
        findsOneWidget,
      );
      expect(find.text('Gone One'), findsNothing);

      final review = find.byKey(
        const ValueKey<String>('album-profile-review-unavailable'),
      );
      await tester.ensureVisible(review);
      await tester.pumpAndSettle();
      await tester.tap(review);
      await tester.pumpAndSettle();
      await openStudioSection(tester, 'tracklist');

      for (final id in ['gone-1', 'gone-2']) {
        final row = find.byKey(ValueKey<String>('album-studio-track-$id'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining('File unavailable'),
          ),
          findsOneWidget,
        );
        // Purpose repair: from here such a song can be deleted.
        expect(
          find.descendant(
            of: row,
            matching: find.byKey(ValueKey<String>('album-studio-delete-$id')),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey<String>('album-studio-delete-here')),
        findsNothing,
      );
      final here = find.byKey(
        const ValueKey<String>('album-studio-track-here'),
      );
      await tester.ensureVisible(here);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: here,
          matching: find.textContaining('File unavailable'),
        ),
        findsNothing,
      );
    });

    testWidgets('REF-13: a multi-disc release shows each disc once, in '
        'order, with its name', (tester) async {
      LibraryTrack track(String id, int disc, int number) => createTrack(
        songId: id,
        title: 'Song $id',
        albumEditionId: 'edition-standard',
        albumEditionTitle: 'Standard',
        discNumber: disc,
        trackNumber: number,
      );
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
        // A hand-made order that put a Disc 1 song after Disc 2.
        editionTracks: {
          'edition-standard': [
            track('one', 1, 1),
            track('bonus', 2, 1),
            track('two', 1, 2),
          ],
        },
      );

      await tester.pumpWidget(
        Provider<AlbumEditionDiscLabelRepository?>.value(
          value: _MemoryDiscLabels({2: 'Bonus Tracks'}),
          child: buildSubject(repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      final headings = [
        for (final element
            in find
                .byWidgetPredicate(
                  (widget) =>
                      widget is Text &&
                      widget.key is ValueKey<String> &&
                      (widget.key! as ValueKey<String>).value.startsWith(
                        'album-profile-disc-heading-',
                      ),
                )
                .evaluate())
          (element.widget as Text).data,
      ];
      expect(headings, ['Disc 1', 'Disc 2 — Bonus Tracks']);

      // Disc 1's songs stay together, above Disc 2.
      double top(String id) =>
          tester.getTopLeft(find.byKey(ValueKey<String>('album-track-$id'))).dy;
      expect(top('one'), lessThan(top('two')));
      expect(top('two'), lessThan(top('bonus')));
    });

    testWidgets('SN-50 C-Q10A: long-press selects tracks; Back leaves', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-ember'),
          createTrack(songId: 'song-fjord'),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      await tester.longPress(
        find.byKey(const ValueKey<String>('album-track-song-ember')),
      );
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('album-track-menu-song-ember')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('track-selection-all')));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('album-track-menu-song-ember')),
        findsOneWidget,
      );
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

    testWidgets('signed-in user can edit release details', (tester) async {
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

      // One entry point: everything about the release is in Edit Release.
      expect(find.text('Edit Release'), findsOneWidget);
      expect(find.text('Edit album details'), findsNothing);
      expect(find.text('Change artwork'), findsNothing);
      expect(find.text('Clear artwork'), findsNothing);

      await tester.tap(find.text('Edit Release'));
      await tester.pumpAndSettle();

      // Each field shows its value and has one way to change it.
      expect(find.text('Test Album'), findsWidgets);
      expect(find.text('May 17, 2024'), findsOneWidget);
      expect(find.text('Pop'), findsOneWidget);

      Future<void> edit(String row, String field, String value) async {
        final target = find.byKey(ValueKey<String>('release-studio-$row'));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        if (field == 'date') {
          await enterReleaseDate(tester, value);
        } else {
          await tester.enterText(
            find.byKey(ValueKey<String>('release-studio-$field-field')),
            value,
          );
        }
        final save = find.byKey(ValueKey<String>('release-studio-save-$field'));
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
      }

      await edit('date', 'date', '2025-06-20');
      expect(editingService.updateCallCount, 1);
      expect(editingService.lastUserId, 'user-1');
      expect(editingService.lastAlbumId, 'album-1');
      expect(editingService.lastPrimaryEditionId, 'edition-1');
      // The stored base title and the edition's name are never changed by
      // release details (SN-50 A-Q4).
      expect(editingService.lastTitle, 'Test Album');
      expect(editingService.lastEditionTitle, 'Standard');
      expect(editingService.lastEditionType, AlbumEditionType.standard);
      expect(editingService.lastReleaseDate, DateTime.utc(2025, 6, 20));
      expect(editingService.lastReleaseDatePrecision, ReleaseDatePrecision.day);
      expect(editingService.lastGenre, 'Pop');

      await edit('genre', 'genre', 'Alternative');
      expect(editingService.lastGenre, 'Alternative');
      expect(editingService.updateCallCount, 2);

      // A year alone is saved as a year, after confirming the day is lost.
      await edit('date', 'date', '2025');
      expect(find.text('Use a less exact date?'), findsOneWidget);
      expect(editingService.updateCallCount, 2);
      await tester.tap(
        find.byKey(const ValueKey<String>('release-date-confirm-less-precise')),
      );
      await tester.pumpAndSettle();
      expect(editingService.updateCallCount, 3);
      expect(editingService.lastReleaseDate, DateTime.utc(2025));
      expect(
        editingService.lastReleaseDatePrecision,
        ReleaseDatePrecision.year,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('release-studio-page')),
        findsNothing,
      );
      expect(find.text('Test Album'), findsWidgets);
    });

    testWidgets('the release can move to another artist or project', (
      tester,
    ) async {
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

      await tester.tap(find.text('Edit Release'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('release-studio-owner')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('release-studio-owner-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.text('Second Artist').last);
      await tester.pumpAndSettle();

      expect(editingService.updateCallCount, 1);
      expect(editingService.lastArtistId, 'artist-2');
    });

    testWidgets('a soundtrack can be given a new project of its own', (
      tester,
    ) async {
      final editingService = FakeAlbumProfileEditingService();
      final creation = _FakeArtistCreationService();

      await tester.pumpWidget(
        buildSubject(
          repository: FakeLibraryQueryRepository(
            album: createAlbum(
              title: 'Starstruck',
              artistId: 'artist-1',
              artistName: 'Sterling Knight',
              primaryEditionTitle: 'Standard',
            ),
          ),
          accountRepository: FakeAccountRepository(
            currentUser: const AccountUser(id: 'user-1'),
          ),
          albumProfileEditingService: editingService,
          artistCreationService: creation,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Release'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('release-studio-owner')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('release-studio-owner-new')),
      );
      await tester.pumpAndSettle();

      // The release title is suggested as the project's name.
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('release-studio-new-owner-field')),
      );
      expect(field.controller!.text, 'Starstruck');
      await tester.tap(
        find.byKey(const ValueKey<String>('release-studio-new-owner-save')),
      );
      await tester.pumpAndSettle();

      expect(creation.names, ['Starstruck']);
      expect(creation.userIds, ['user-1']);
      expect(editingService.updateCallCount, 1);
      expect(editingService.lastArtistId, 'artist-new');
      expect(
        find.text('The release now belongs to Starstruck.'),
        findsOneWidget,
      );
    });

    testWidgets('choosing the current owner again keeps it on purpose', (
      tester,
    ) async {
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
      await tester.tap(find.text('Edit Release'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('release-studio-owner')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('release-studio-owner-artist-1')),
      );
      await tester.pumpAndSettle();

      expect(editingService.confirmOwnerCount, 1);
      expect(editingService.updateCallCount, 0);
      expect(find.text('Test Artist is kept as the owner.'), findsOneWidget);
    });

    testWidgets('without artist creation, only existing artists are offered', (
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
          albumProfileEditingService: FakeAlbumProfileEditingService(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Release'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('release-studio-owner')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('release-studio-owner-new')),
        findsNothing,
      );
    });

    testWidgets('an impossible date is refused', (tester) async {
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
      await tester.tap(find.text('Edit Release'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('release-studio-date')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('release-studio-date')),
      );
      await tester.pumpAndSettle();
      // BUG-10: only real dates can be entered, and a year is required.
      await tester.enterText(
        find.byKey(const ValueKey<String>('release-date-year-field')),
        '1850',
      );
      await tester.pump();
      expect(
        find.text('Use a year from 1900 to ${DateTime.now().year + 5}.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey<String>('release-studio-save-date')),
            )
            .onPressed,
        isNull,
      );

      expect(editingService.updateCallCount, 0);
    });

    testWidgets('release date and genre can be cleared', (tester) async {
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
      await tester.tap(find.text('Edit Release'));
      await tester.pumpAndSettle();

      for (final field in ['date', 'genre']) {
        final target = find.byKey(ValueKey<String>('release-studio-$field'));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        if (field == 'date') {
          await tester.tap(
            find.byKey(const ValueKey<String>('release-date-remove')),
          );
          await tester.pump();
        } else {
          await tester.enterText(
            find.byKey(ValueKey<String>('release-studio-$field-field')),
            '',
          );
        }
        final save = find.byKey(ValueKey<String>('release-studio-save-$field'));
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        if (field == 'date') {
          expect(editingService.lastReleaseDate, isNull);
          expect(editingService.lastGenre, 'Pop');
        }
      }

      expect(editingService.updateCallCount, 2);
      expect(editingService.lastGenre, isNull);
    });

    testWidgets('signed-out user can edit release details locally', (
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

      await tester.tap(find.text('Edit Release'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('release-studio-genre')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('release-studio-genre-field')),
        'Ambient',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('release-studio-save-genre')),
      );
      await tester.pumpAndSettle();

      expect(editingService.updateCallCount, 1);
      expect(editingService.lastUserId, isNull);
      expect(editingService.lastAlbumId, 'album-1');
      expect(editingService.lastPrimaryEditionId, 'edition-primary');
      expect(editingService.lastGenre, 'Ambient');
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

      // App Update 1.2: the menu also offers permanent deletion, so it
      // opens; editing itself stays unavailable.
      await tester.tap(
        find.byKey(const ValueKey<String>('album-profile-artwork-menu')),
      );
      await tester.pumpAndSettle();

      final edit = tester.widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text('Edit Release'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );
      expect(edit.enabled, isFalse);
      expect(
        find.byKey(
          const ValueKey<String>('album-profile-delete-permanently-menu-item'),
        ),
        findsOneWidget,
      );
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

        expect(find.text('Edit Release'), findsOneWidget);

        await tester.tap(find.text('Edit Release'));
        await tester.pumpAndSettle();
        await openStudioSection(tester, 'tracklist');

        expect(
          find.byKey(const ValueKey<String>('release-studio-page')),
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
            home: ReleaseStudioPage(
              controller: controller,
              userId: null,
              onChangeArtwork: () async {
                changeArtworkCallCount++;
              },
              onClearArtwork: () async {
                clearArtworkCallCount++;
              },
              initialSection: ReleaseStudioSection.artwork,
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
          home: ReleaseStudioPage(controller: controller, userId: null),
        ),
      );
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('album-studio-search-musicbrainz')),
      );

      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);

      await openStudioSection(tester, 'artwork');

      // REF-18: Cover Art Archive is not offered; the other cover actions
      // stay.
      expect(
        find.byKey(const ValueKey<String>('album-studio-search-cover-art')),
        findsNothing,
      );
      expect(find.textContaining('Cover Art Archive'), findsNothing);
      for (final action in ['change-artwork', 'clear-artwork']) {
        expect(
          find.byKey(ValueKey<String>('album-studio-$action')),
          findsOneWidget,
          reason: action,
        );
      }
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
          home: ReleaseStudioPage(
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

        await tester.tap(find.text('Edit Release'));
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
      await tester.tap(find.text('Edit Release'));
      await tester.pumpAndSettle();
      await openStudioSection(tester, 'tracklist');

      expect(find.text('Standard Studio Song'), findsOneWidget);
      expect(find.text('Deluxe Studio Song'), findsNothing);

      final tabs = find.byKey(
        const ValueKey<String>('release-studio-edition-tabs'),
      );

      expect(tabs, findsOneWidget);

      final deluxe = find.descendant(of: tabs, matching: find.text('Deluxe'));
      await tester.ensureVisible(deluxe);
      await tester.pumpAndSettle();
      await tester.tap(deluxe);
      await tester.pumpAndSettle();
      await revealStudioSection(tester, 'tracklist');

      expect(find.text('Standard Studio Song'), findsNothing);
      expect(find.text('Deluxe Studio Song'), findsOneWidget);
    });

    testWidgets(
      'Album Studio reorder forwards the visual order as one arrangement '
      '(REF-13: numbering is automatic, no switch)',
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
        await tester.tap(find.text('Edit Release'));
        await tester.pumpAndSettle();
        await openStudioSection(tester, 'tracklist');

        expect(
          find.byKey(const ValueKey<String>('album-studio-auto-renumber')),
          findsNothing,
        );

        final listFinder = find.byKey(
          const ValueKey<String>('album-studio-track-list'),
        );

        final list = tester.widget<SliverReorderableList>(listFinder);

        list.onReorderItem!(0, 2);
        await tester.pumpAndSettle();

        expect(service.arrangeCallCount, 1);
        expect(service.reorderCallCount, 0);
        expect(service.lastEditionId, 'edition-standard');
        expect(service.lastOrderedSongIds, ['song-b', 'song-c', 'song-a']);
        expect(service.lastPlacements!.map((p) => p.discNumber).toSet(), {1});
      },
    );

    // Charts 2.0 C4: every song menu opens the one Song Stats page.
    testWidgets('album track menu opens Song Stats', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'stats-song', title: 'Stats Song')],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      final menu = find.byKey(
        const ValueKey<String>('album-track-menu-stats-song'),
      );
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Stats'));
      await tester.pumpAndSettle();

      expect(find.byType(SongStatsPage), findsOneWidget);
      expect(
        tester.widget<SongStatsPage>(find.byType(SongStatsPage)).songId,
        'stats-song',
      );
    });

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

/// Release Studio opens on Shared details; open the selected edition's
/// [section] and scroll its heading to the top, as arriving there would.
Future<void> openStudioSection(WidgetTester tester, String section) async {
  final header = find.byKey(
    ValueKey<String>('release-studio-section-$section'),
  );
  await tester.ensureVisible(header);
  await tester.pumpAndSettle();
  await tester.tap(header);
  await tester.pumpAndSettle();
  await revealStudioSection(tester, section);
}

/// Scrolls an open [section]'s heading to the top of Release Studio.
Future<void> revealStudioSection(WidgetTester tester, String section) async {
  final header = find.byKey(
    ValueKey<String>('release-studio-section-$section'),
  );
  await tester.ensureVisible(header);
  await Scrollable.ensureVisible(tester.element(header));
  await tester.pumpAndSettle();
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
  ArtistCreationService? artistCreationService,
  ThemeData? theme,
  SonusArtworkPalette? artworkPalette,
  TransitionBuilder? appBuilder,
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
      Provider<ArtistCreationService?>.value(value: artistCreationService),
    ],
    child: AccountScope(
      repository: accountRepository,
      child: MaterialApp(
        theme: theme,
        builder: appBuilder,
        home: AlbumProfilePage(
          albumId: 'album-1',
          initialAlbumTitle: 'Test Album',
          artworkPalette: artworkPalette,
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
  List<String> coPrimaryArtists = const [],
  List<String> guestArtists = const [],
  String? versionLabel,
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
    coPrimaryArtists: coPrimaryArtists,
    guestArtists: guestArtists,
    versionLabel: versionLabel,
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

  /// REF-13: Release Studio lays out an edition in one call.
  int arrangeCallCount = 0;
  List<EditionPlacement>? lastPlacements;

  @override
  Future<AlbumEditionArrangeResult> arrangeEdition({
    required String albumEditionId,
    required List<EditionPlacement> placements,
    String? userId,
    DateTime? now,
  }) async {
    arrangeCallCount++;
    lastUserId = userId;
    lastEditionId = albumEditionId;
    lastPlacements = List<EditionPlacement>.from(placements);
    lastOrderedSongIds = [for (final p in placements) p.songId];

    return const AlbumEditionArrangeResult(
      memberships: [],
      changed: true,
      manualNumbersKept: 0,
    );
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
  ReleaseDatePrecision? lastReleaseDatePrecision;

  int confirmOwnerCount = 0;

  @override
  Future<void> confirmOwner({required String albumId, DateTime? now}) async {
    confirmOwnerCount++;
  }

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
    ReleaseDatePrecision? releaseDatePrecision,
    String? artistId,
    DateTime? now,
  }) async {
    updateCallCount++;
    lastReleaseDatePrecision = releaseDatePrecision;

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

class _FakeArtistCreationService implements ArtistCreationService {
  final List<String> names = [];
  final List<String?> userIds = [];

  @override
  Future<Artist> createOrReuse({
    required String? userId,
    required String name,
    DateTime? now,
  }) async {
    names.add(name);
    userIds.add(userId);
    final at = DateTime.utc(2026, 10, 26);
    return Artist(
      id: 'artist-new',
      name: name,
      canonicalName: name.toLowerCase(),
      createdAt: at,
      updatedAt: at,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Disc names kept in memory (REF-13c).
class _MemoryDiscLabels implements AlbumEditionDiscLabelRepository {
  _MemoryDiscLabels(this.labels);

  final Map<int, String> labels;

  @override
  Future<List<AlbumEditionDiscLabel>> getByEditionId(String editionId) async =>
      [
        for (final MapEntry(:key, :value) in labels.entries)
          AlbumEditionDiscLabel(
            albumEditionId: editionId,
            discNumber: key,
            label: value,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
      ];

  @override
  Future<void> save(AlbumEditionDiscLabel label) async =>
      labels[label.discNumber] = label.label;

  @override
  Future<void> delete({
    required String editionId,
    required int discNumber,
  }) async => labels.remove(discNumber);

  @override
  Future<void> keepOnly({
    required String editionId,
    required Set<int> discs,
  }) async => labels.removeWhere((disc, _) => !discs.contains(disc));
}
