import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/artwork/application/services/artwork_assignment_service.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_file_picker.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/controllers/album_profile_controller.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

void main() {
  group('AlbumProfileController', () {
    test('loads album and tracks', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1', title: 'First Song'),
          createTrack(songId: 'song-2', title: 'Second Song'),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.album?.albumId, 'album-1');
      expect(controller.album?.title, 'Test Album');
      expect(controller.tracks, hasLength(2));
      expect(repository.requestedAlbumId, 'album-1');
      expect(repository.requestedTracksAlbumId, 'album-1');
      expect(controller.isLoading, isFalse);
      expect(controller.hasError, isFalse);
      expect(controller.isNotFound, isFalse);

      controller.dispose();
    });

    test('derives total album runtime from tracks', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1', durationSeconds: 185),
          createTrack(songId: 'song-2', durationSeconds: 240),
          createTrack(songId: 'song-3', durationSeconds: 95),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.totalDurationSeconds, 520);
      expect(controller.totalDuration, const Duration(minutes: 8, seconds: 40));

      controller.dispose();
    });

    test('negative track durations do not reduce album runtime', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1', durationSeconds: 180),
          createTrack(songId: 'song-2', durationSeconds: -40),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.totalDurationSeconds, 180);

      controller.dispose();
    });

    test('derives playable and unavailable track counts', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1'),
          createTrack(songId: 'song-2'),
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.playableTrackCount, 2);
      expect(controller.unavailableTrackCount, 1);
      expect(controller.hasUnavailableTracks, isTrue);

      controller.dispose();
    });

    test(
      'reports no unavailable tracks when every track is playable',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(songId: 'song-1'),
            createTrack(songId: 'song-2'),
          ],
        );

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
        );

        await controller.load();

        expect(controller.playableTrackCount, 2);
        expect(controller.unavailableTrackCount, 0);
        expect(controller.hasUnavailableTracks, isFalse);

        controller.dispose();
      },
    );

    test('blocked available tracks are not counted as unavailable', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'blocked-song', isSongBlocked: true)],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.playableTrackCount, 0);
      expect(controller.unavailableTrackCount, 0);
      expect(controller.hasUnavailableTracks, isFalse);
      expect(controller.hasPlayableTracks, isFalse);

      controller.dispose();
    });

    test('derives distinct album editions in track order', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(
            songId: 'song-1',
            albumEditionId: 'edition-standard',
            albumEditionTitle: 'Standard',
            albumEditionType: AlbumEditionType.standard,
          ),
          createTrack(
            songId: 'song-2',
            albumEditionId: 'edition-standard',
            albumEditionTitle: 'Standard',
            albumEditionType: AlbumEditionType.standard,
          ),
          createTrack(
            songId: 'song-3',
            albumEditionId: 'edition-deluxe',
            albumEditionTitle: 'Deluxe',
            albumEditionType: AlbumEditionType.deluxe,
          ),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.editionCount, 2);
      expect(controller.hasMultipleEditions, isTrue);
      expect(controller.editionTitles, ['Standard', 'Deluxe']);

      controller.dispose();
    });

    test('single edition album is not reported as multi-edition', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1'),
          createTrack(songId: 'song-2'),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.editionCount, 1);
      expect(controller.hasMultipleEditions, isFalse);
      expect(controller.editionTitles, ['Standard']);

      controller.dispose();
    });

    test('reports not found when album does not exist', () async {
      final repository = FakeLibraryQueryRepository();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'missing-album',
      );

      await controller.load();

      expect(controller.album, isNull);
      expect(controller.tracks, isEmpty);
      expect(controller.isNotFound, isTrue);
      expect(controller.hasError, isFalse);

      controller.dispose();
    });

    test('captures loading errors', () async {
      final repository = FakeLibraryQueryRepository(
        albumError: StateError('failed'),
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.album, isNull);
      expect(controller.tracks, isEmpty);
      expect(controller.hasError, isTrue);
      expect(controller.error, isA<StateError>());
      expect(controller.isLoading, isFalse);

      controller.dispose();
    });

    test('refresh reloads album and tracks', () async {
      var requestCount = 0;

      final repository = FakeLibraryQueryRepository(
        albumLoader: (albumId) async {
          requestCount++;

          return createAlbum(
            title: requestCount == 1 ? 'First Title' : 'Updated Title',
          );
        },
        tracks: [createTrack()],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.album?.title, 'First Title');

      await controller.refresh();

      expect(controller.album?.title, 'Updated Title');
      expect(requestCount, 2);

      controller.dispose();
    });

    test('reports whether track artwork can be edited', () {
      final repository = FakeLibraryQueryRepository(album: createAlbum());

      final service = FakeTrackArtworkAssignmentService();
      final picker = FakeArtworkFilePicker(result: r'C:\Artwork\Song.jpg');

      final editableController = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        artworkAssignmentService: service,
        artworkFilePicker: picker,
      );

      final missingPickerController = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        artworkAssignmentService: service,
      );

      final missingServiceController = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        artworkFilePicker: picker,
      );

      expect(editableController.canEditTrackArtwork, isTrue);
      expect(missingPickerController.canEditTrackArtwork, isFalse);
      expect(missingServiceController.canEditTrackArtwork, isFalse);

      editableController.dispose();
      missingPickerController.dispose();
      missingServiceController.dispose();
    });

    test(
      'changeTrackArtwork assigns selected song artwork and refreshes',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [createTrack(songId: 'song-artwork')],
        );

        final service = FakeTrackArtworkAssignmentService();
        final picker = FakeArtworkFilePicker(result: r'C:\Artwork\Song.jpg');

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          artworkAssignmentService: service,
          artworkFilePicker: picker,
        );

        await controller.load();

        expect(repository.albumRequestCount, 1);

        final changed = await controller.changeTrackArtwork(
          controller.tracks.single,
        );

        expect(changed, isTrue);
        expect(picker.callCount, 1);
        expect(service.assignSongCallCount, 1);
        expect(service.assignedSongId, 'song-artwork');
        expect(service.assignedFilePath, r'C:\Artwork\Song.jpg');
        expect(repository.albumRequestCount, 2);

        controller.dispose();
      },
    );

    test(
      'cancelled track artwork selection does not assign or refresh',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [createTrack(songId: 'song-artwork')],
        );

        final service = FakeTrackArtworkAssignmentService();
        final picker = FakeArtworkFilePicker(result: null);

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          artworkAssignmentService: service,
          artworkFilePicker: picker,
        );

        await controller.load();

        final changed = await controller.changeTrackArtwork(
          controller.tracks.single,
        );

        expect(changed, isFalse);
        expect(picker.callCount, 1);
        expect(service.assignSongCallCount, 0);
        expect(repository.albumRequestCount, 1);

        controller.dispose();
      },
    );

    test(
      'clearTrackArtwork clears selected song artwork and refreshes',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [createTrack(songId: 'song-artwork')],
        );

        final service = FakeTrackArtworkAssignmentService();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          artworkAssignmentService: service,
          artworkFilePicker: FakeArtworkFilePicker(result: null),
        );

        await controller.load();

        final changed = await controller.clearTrackArtwork(
          controller.tracks.single,
        );

        expect(changed, isTrue);
        expect(service.clearSongCallCount, 1);
        expect(service.clearedSongId, 'song-artwork');
        expect(repository.albumRequestCount, 2);

        controller.dispose();
      },
    );

    test('unavailable album track can still have artwork changed', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      final service = FakeTrackArtworkAssignmentService();
      final picker = FakeArtworkFilePicker(result: r'C:\Artwork\Missing.jpg');

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        artworkAssignmentService: service,
        artworkFilePicker: picker,
      );

      await controller.load();

      final track = controller.tracks.single;

      expect(controller.isTrackPlayable(track), isFalse);
      expect(controller.canEditTrackArtwork, isTrue);

      final changed = await controller.changeTrackArtwork(track);

      expect(changed, isTrue);
      expect(service.assignedSongId, 'missing-song');

      controller.dispose();
    });

    test('reports whether album track metadata editing is available', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack()],
      );
      final service = FakeTrackProfileEditingService();

      final editableController = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        trackProfileEditingService: service,
      );

      final missingServiceController = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      expect(editableController.canEditTrack('user-1'), isTrue);
      expect(editableController.canEditTrack('  user-1  '), isTrue);
      expect(editableController.canEditTrack(null), isFalse);
      expect(editableController.canEditTrack(''), isFalse);
      expect(editableController.canEditTrack('   '), isFalse);
      expect(missingServiceController.canEditTrack('user-1'), isFalse);

      editableController.dispose();
      missingServiceController.dispose();
    });

    test('updateTrack forwards metadata and refreshes album profile', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'song-edit', title: 'Original Title')],
      );
      final service = FakeTrackProfileEditingService();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        trackProfileEditingService: service,
      );

      await controller.load();

      expect(repository.albumRequestCount, 1);

      final changed = await controller.updateTrack(
        userId: 'user-1',
        track: controller.tracks.single,
        title: 'Edited Title',
        trackNumber: 7,
        discNumber: 3,
        featuredArtists: const ['Feature One', 'Feature Two'],
        isSingle: true,
      );

      expect(changed, isTrue);
      expect(service.updateCallCount, 1);
      expect(service.lastUserId, 'user-1');
      expect(service.lastSongId, 'song-edit');
      expect(service.lastTitle, 'Edited Title');
      expect(service.lastTrackNumber, 7);
      expect(service.lastDiscNumber, 3);
      expect(service.lastFeaturedArtists, ['Feature One', 'Feature Two']);
      expect(service.lastIsSingle, isTrue);
      expect(repository.albumRequestCount, 2);

      controller.dispose();
    });

    test('unavailable album track can still have metadata edited', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'missing-edit', filePath: '', isAvailable: false),
        ],
      );
      final service = FakeTrackProfileEditingService();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        trackProfileEditingService: service,
      );

      await controller.load();

      final track = controller.tracks.single;

      expect(controller.isTrackPlayable(track), isFalse);
      expect(controller.canEditTrack('user-1'), isTrue);

      final changed = await controller.updateTrack(
        userId: 'user-1',
        track: track,
        title: 'Edited Missing Song',
        trackNumber: 2,
        discNumber: 1,
        featuredArtists: const ['Guest'],
        isSingle: false,
      );

      expect(changed, isTrue);
      expect(service.updateCallCount, 1);
      expect(service.lastSongId, 'missing-edit');

      controller.dispose();
    });

    test('updateTrack rejects unavailable editing capability', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'song-edit')],
      );

      final missingServiceController = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await missingServiceController.load();

      final missingServiceResult = await missingServiceController.updateTrack(
        userId: 'user-1',
        track: missingServiceController.tracks.single,
        title: 'Edited',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
      );

      expect(missingServiceResult, isFalse);

      final service = FakeTrackProfileEditingService();

      final blankUserController = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        trackProfileEditingService: service,
      );

      await blankUserController.load();

      final blankUserResult = await blankUserController.updateTrack(
        userId: '   ',
        track: blankUserController.tracks.single,
        title: 'Edited',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
      );

      expect(blankUserResult, isFalse);
      expect(service.updateCallCount, 0);

      missingServiceController.dispose();
      blankUserController.dispose();
    });
    test('reports whether album profile editing is available', () async {
      final editableRepository = FakeLibraryQueryRepository(
        album: createAlbum(
          primaryEditionId: 'edition-1',
          primaryEditionTitle: 'Standard',
          primaryEditionType: AlbumEditionType.standard,
        ),
      );

      final editableController = AlbumProfileController(
        repository: editableRepository,
        albumId: 'album-1',
        albumProfileEditingService: FakeAlbumProfileEditingService(),
      );

      await editableController.load();

      expect(editableController.canEditAlbumProfile('user-1'), isTrue);
      expect(editableController.canEditAlbumProfile('  user-1  '), isTrue);
      expect(editableController.canEditAlbumProfile(null), isFalse);
      expect(editableController.canEditAlbumProfile(''), isFalse);
      expect(editableController.canEditAlbumProfile('   '), isFalse);

      final missingServiceController = AlbumProfileController(
        repository: editableRepository,
        albumId: 'album-1',
      );

      await missingServiceController.load();

      expect(missingServiceController.canEditAlbumProfile('user-1'), isFalse);

      final missingEditionRepository = FakeLibraryQueryRepository(
        album: createAlbum(),
      );

      final missingEditionController = AlbumProfileController(
        repository: missingEditionRepository,
        albumId: 'album-1',
        albumProfileEditingService: FakeAlbumProfileEditingService(),
      );

      await missingEditionController.load();

      expect(missingEditionController.canEditAlbumProfile('user-1'), isFalse);

      editableController.dispose();
      missingServiceController.dispose();
      missingEditionController.dispose();
    });

    test(
      'updateProfile forwards mutation and refreshes album profile',
      () async {
        var requestCount = 0;

        final repository = FakeLibraryQueryRepository(
          albumLoader: (albumId) async {
            requestCount++;

            return createAlbum(
              title: requestCount == 1 ? 'Original Album' : 'Renamed Album',
              primaryEditionId: 'edition-primary',
              primaryEditionTitle: requestCount == 1 ? 'Standard' : 'Deluxe',
              primaryEditionType: requestCount == 1
                  ? AlbumEditionType.standard
                  : AlbumEditionType.deluxe,
              releaseDate: requestCount == 1
                  ? DateTime.utc(2024, 1, 5)
                  : DateTime.utc(2025, 6, 20),
              genre: requestCount == 1 ? 'Pop' : 'Alternative',
            );
          },
        );

        final service = FakeAlbumProfileEditingService();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          albumProfileEditingService: service,
        );

        await controller.load();

        expect(repository.albumRequestCount, 1);
        expect(controller.album?.title, 'Original Album');

        final releaseDate = DateTime.utc(2025, 6, 20);

        final updated = await controller.updateProfile(
          userId: 'user-1',
          title: 'Renamed Album',
          editionTitle: 'Deluxe',
          editionType: AlbumEditionType.deluxe,
          releaseDate: releaseDate,
          genre: 'Alternative',
          artistId: 'artist-2',
        );

        expect(updated, isTrue);
        expect(service.updateCallCount, 1);
        expect(service.lastUserId, 'user-1');
        expect(service.lastAlbumId, 'album-1');
        expect(service.lastPrimaryEditionId, 'edition-primary');
        expect(service.lastTitle, 'Renamed Album');
        expect(service.lastEditionTitle, 'Deluxe');
        expect(service.lastEditionType, AlbumEditionType.deluxe);
        expect(service.lastReleaseDate, releaseDate);
        expect(service.lastGenre, 'Alternative');
        expect(service.lastArtistId, 'artist-2');

        expect(repository.albumRequestCount, 2);
        expect(controller.album?.title, 'Renamed Album');
        expect(controller.album?.primaryEditionTitle, 'Deluxe');
        expect(controller.album?.primaryEditionType, AlbumEditionType.deluxe);
        expect(controller.album?.releaseDate, releaseDate);
        expect(controller.album?.genre, 'Alternative');

        controller.dispose();
      },
    );

    test(
      'updateProfile does nothing when editing service is unavailable',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(
            primaryEditionId: 'edition-primary',
            primaryEditionTitle: 'Standard',
            primaryEditionType: AlbumEditionType.standard,
          ),
        );

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
        );

        await controller.load();

        final updated = await controller.updateProfile(
          userId: 'user-1',
          title: 'Renamed Album',
          editionTitle: 'Deluxe',
          editionType: AlbumEditionType.deluxe,
          releaseDate: null,
          genre: null,
        );

        expect(updated, isFalse);
        expect(repository.albumRequestCount, 1);

        controller.dispose();
      },
    );

    test('updateProfile does nothing when user id is blank', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(
          primaryEditionId: 'edition-primary',
          primaryEditionTitle: 'Standard',
          primaryEditionType: AlbumEditionType.standard,
        ),
      );

      final service = FakeAlbumProfileEditingService();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        albumProfileEditingService: service,
      );

      await controller.load();

      final updated = await controller.updateProfile(
        userId: '   ',
        title: 'Renamed Album',
        editionTitle: 'Deluxe',
        editionType: AlbumEditionType.deluxe,
        releaseDate: null,
        genre: null,
      );

      expect(updated, isFalse);
      expect(service.updateCallCount, 0);
      expect(repository.albumRequestCount, 1);

      controller.dispose();
    });

    test(
      'updateProfile does nothing when primary edition is unavailable',
      () async {
        final repository = FakeLibraryQueryRepository(album: createAlbum());
        final service = FakeAlbumProfileEditingService();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          albumProfileEditingService: service,
        );

        await controller.load();

        final updated = await controller.updateProfile(
          userId: 'user-1',
          title: 'Renamed Album',
          editionTitle: 'Deluxe',
          editionType: AlbumEditionType.deluxe,
          releaseDate: null,
          genre: null,
        );

        expect(updated, isFalse);
        expect(service.updateCallCount, 0);
        expect(repository.albumRequestCount, 1);

        controller.dispose();
      },
    );

    test(
      'playTrack loads the current album context from the selected song',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(songId: 'song-1'),
            createTrack(songId: 'song-2'),
            createTrack(songId: 'song-3'),
          ],
        );

        final engine = FakePlaybackEngine();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        );

        await controller.load();
        await controller.playTrack(controller.tracks[1]);

        expect(engine.loadQueueCallCount, 1);
        expect(engine.lastLoadedTracks!.map((track) => track.songId), [
          'song-1',
          'song-2',
          'song-3',
        ]);
        expect(engine.lastStartIndex, 1);
        expect(engine.lastAutoPlay, isTrue);

        controller.dispose();
        await engine.dispose();
      },
    );

    test(
      'playTrack remaps the selected album song after unavailable tracks are filtered',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(
              songId: 'missing-song',
              filePath: '',
              isAvailable: false,
            ),
            createTrack(songId: 'song-1'),
            createTrack(songId: 'song-2'),
          ],
        );

        final engine = FakePlaybackEngine();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        );

        await controller.load();
        await controller.playTrack(controller.tracks[2]);

        expect(engine.loadQueueCallCount, 1);
        expect(engine.lastLoadedTracks!.map((track) => track.songId), [
          'song-1',
          'song-2',
        ]);
        expect(engine.lastStartIndex, 1);
        expect(engine.lastAutoPlay, isTrue);

        controller.dispose();
        await engine.dispose();
      },
    );
    test('playTrack ignores unavailable track', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      final engine = FakePlaybackEngine();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();

      await controller.playTrack(controller.tracks.single);

      expect(engine.loadQueueCallCount, 0);

      controller.dispose();
      await engine.dispose();
    });

    test(
      'playAll starts from first playable track when shuffle is off',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(
              songId: 'missing-song',
              filePath: '',
              isAvailable: false,
            ),
            createTrack(songId: 'song-2'),
            createTrack(songId: 'song-3'),
          ],
        );

        final engine = FakePlaybackEngine();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        );

        await controller.load();

        await controller.playAll();

        expect(engine.loadQueueCallCount, 1);

        expect(engine.lastLoadedTracks!.map((track) => track.songId), [
          'song-2',
          'song-3',
        ]);

        expect(engine.lastStartIndex, 0);
        expect(engine.lastAutoPlay, isTrue);

        controller.dispose();
        await engine.dispose();
      },
    );

    test('playAll starts from shuffled playable track', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1'),
          createTrack(songId: 'song-2'),
          createTrack(songId: 'song-3'),
        ],
      );

      final engine = FakePlaybackEngine();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
        random: const FixedRandom(2),
      );

      await controller.load();

      await controller.setShuffleEnabled(true);
      await controller.playAll();

      expect(controller.isShuffleEnabled, isTrue);
      expect(engine.loadQueueCallCount, 1);

      expect(engine.lastLoadedTracks!.map((track) => track.songId), [
        'song-1',
        'song-2',
        'song-3',
      ]);

      expect(engine.lastStartIndex, 2);
      expect(engine.lastAutoPlay, isTrue);

      controller.dispose();
      await engine.dispose();
    });

    test(
      'setShuffleEnabled updates playback engine and controller state',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [createTrack()],
        );

        final engine = FakePlaybackEngine();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        );

        await controller.load();

        await controller.setShuffleEnabled(true);

        expect(controller.isShuffleEnabled, isTrue);
        expect(engine.lastShuffleEnabled, isTrue);

        await controller.setShuffleEnabled(false);

        expect(controller.isShuffleEnabled, isFalse);
        expect(engine.lastShuffleEnabled, isFalse);

        controller.dispose();
        await engine.dispose();
      },
    );

    test('toggleShuffle flips shuffle state', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack()],
      );

      final engine = FakePlaybackEngine();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();

      await controller.toggleShuffle();

      expect(controller.isShuffleEnabled, isTrue);

      await controller.toggleShuffle();

      expect(controller.isShuffleEnabled, isFalse);

      controller.dispose();
      await engine.dispose();
    });

    test('playNext inserts playable track after current track', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'song-2')],
      );

      final engine = FakePlaybackEngine();
      final coordinator = PlaybackCoordinator(engine: engine);

      await coordinator.playTrack(
        createTrack(songId: 'current-song', title: 'Current Song'),
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: coordinator,
      );

      await controller.load();

      await controller.playNext(controller.tracks.single);

      expect(engine.lastInsertedTrack?.songId, 'song-2');
      expect(engine.lastInsertedIndex, 1);

      controller.dispose();
      await engine.dispose();
    });

    test('addToQueue appends playable track', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'song-2')],
      );

      final engine = FakePlaybackEngine();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();

      await controller.addToQueue(controller.tracks.single);

      expect(engine.lastAppendedTrack?.songId, 'song-2');

      controller.dispose();
      await engine.dispose();
    });

    test('reports whether tracks are playable', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'playable-song'),
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.hasPlayableTracks, isTrue);
      expect(controller.isTrackPlayable(controller.tracks.first), isTrue);
      expect(controller.isTrackPlayable(controller.tracks.last), isFalse);

      controller.dispose();
    });

    test(
      'hasPlayableTracks is false when every track is unavailable',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(songId: 'missing-1', filePath: '', isAvailable: false),
            createTrack(songId: 'missing-2', filePath: '', isAvailable: false),
          ],
        );

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
        );

        await controller.load();

        expect(controller.hasPlayableTracks, isFalse);

        controller.dispose();
      },
    );

    test(
      'playback actions do nothing when playback coordinator is absent',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [createTrack()],
        );

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
        );

        await controller.load();

        await controller.playTrack(controller.tracks.single);
        await controller.playAll();
        await controller.playNext(controller.tracks.single);
        await controller.addToQueue(controller.tracks.single);
        await controller.toggleShuffle();

        expect(controller.isShuffleEnabled, isFalse);

        controller.dispose();
      },
    );

    test('reports whether album song blocking is available', () {
      final repository = FakeLibraryQueryRepository(album: createAlbum());
      final service = FakeSongBlockService();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        songBlockService: service,
      );

      final missingServiceController = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      expect(controller.canSetTrackBlocked('user-1'), isTrue);
      expect(controller.canSetTrackBlocked('  user-1  '), isTrue);
      expect(controller.canSetTrackBlocked(null), isFalse);
      expect(controller.canSetTrackBlocked(''), isFalse);
      expect(controller.canSetTrackBlocked('   '), isFalse);
      expect(missingServiceController.canSetTrackBlocked('user-1'), isFalse);

      controller.dispose();
      missingServiceController.dispose();
    });

    test(
      'setTrackBlocked forwards mutation and refreshes album profile',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [createTrack(songId: 'song-block')],
        );

        final service = FakeSongBlockService();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          songBlockService: service,
        );

        await controller.load();

        expect(repository.albumRequestCount, 1);

        final changed = await controller.setTrackBlocked(
          userId: 'user-1',
          track: controller.tracks.single,
          isBlocked: true,
        );

        expect(changed, isTrue);
        expect(service.setBlockedCallCount, 1);
        expect(service.lastUserId, 'user-1');
        expect(service.lastSongId, 'song-block');
        expect(service.lastIsBlocked, isTrue);
        expect(repository.albumRequestCount, 2);

        controller.dispose();
      },
    );

    test('setTrackBlocked rejects missing service or blank user id', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'song-block')],
      );

      final missingServiceController = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await missingServiceController.load();

      expect(
        await missingServiceController.setTrackBlocked(
          userId: 'user-1',
          track: missingServiceController.tracks.single,
          isBlocked: true,
        ),
        isFalse,
      );

      final service = FakeSongBlockService();

      final blankUserController = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        songBlockService: service,
      );

      await blankUserController.load();

      expect(
        await blankUserController.setTrackBlocked(
          userId: '   ',
          track: blankUserController.tracks.single,
          isBlocked: true,
        ),
        isFalse,
      );

      expect(service.setBlockedCallCount, 0);

      missingServiceController.dispose();
      blankUserController.dispose();
    });
  });
}

LibraryAlbum createAlbum({
  String albumId = 'album-1',
  String title = 'Test Album',
  String artistId = 'artist-1',
  String? primaryEditionId,
  String? primaryEditionTitle,
  AlbumEditionType? primaryEditionType,
  DateTime? releaseDate,
  String? genre,
}) {
  return LibraryAlbum(
    albumId: albumId,
    title: title,
    artistId: artistId,
    artistName: 'Test Artist',
    primaryEditionId: primaryEditionId,
    primaryEditionTitle: primaryEditionTitle,
    primaryEditionType: primaryEditionType,
    releaseDate: releaseDate,
    genre: genre,
    trackCount: 3,
    dateAdded: DateTime(2026, 1, 1),
  );
}

LibraryTrack createTrack({
  String songId = 'song-1',
  String title = 'Test Song',
  String artistId = 'artist-1',
  String albumId = 'album-1',
  String albumEditionId = 'edition-1',
  String albumEditionTitle = 'Standard',
  AlbumEditionType albumEditionType = AlbumEditionType.standard,
  int trackNumber = 1,
  int discNumber = 1,
  int durationSeconds = 180,
  String? filePath,
  bool isAvailable = true,
  bool isSongBlocked = false,
  bool isArtistBlacklisted = false,
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: artistId,
    artistName: 'Test Artist',
    albumId: albumId,
    albumTitle: 'Test Album',
    albumEditionId: albumEditionId,
    albumEditionTitle: albumEditionTitle,
    albumEditionType: albumEditionType,
    trackNumber: trackNumber,
    discNumber: discNumber,
    durationSeconds: durationSeconds,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026, 1, 1),
    filePath: filePath ?? 'C:/Music/$songId.mp3',
    isAvailable: isAvailable,
    isSongBlocked: isSongBlocked,
    isArtistBlacklisted: isArtistBlacklisted,
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

  String? requestedAlbumId;
  String? requestedTracksAlbumId;

  int albumRequestCount = 0;

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    requestedAlbumId = albumId;
    albumRequestCount++;

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
    requestedTracksAlbumId = albumId;

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
    return const [];
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

class FakeTrackProfileEditingService extends TrackProfileEditingService {
  FakeTrackProfileEditingService()
    : super(mutationRunner: UnusedSyncMutationRunner());

  int updateCallCount = 0;

  String? lastUserId;
  String? lastSongId;
  String? lastTitle;
  int? lastTrackNumber;
  int? lastDiscNumber;
  List<String>? lastFeaturedArtists;
  bool? lastIsSingle;

  @override
  Future<TrackProfileEditResult> updateTrack({
    required String userId,
    required String songId,
    required String title,
    required int trackNumber,
    int discNumber = 1,
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

    final timestamp = now ?? DateTime.utc(2026, 1, 1);

    return TrackProfileEditResult(
      song: Song(
        id: songId,
        artistId: 'artist-1',
        albumId: 'album-1',
        albumEditionId: 'edition-1',
        title: title,
        canonicalTitle: title.trim().toLowerCase(),
        trackNumber: trackNumber,
        discNumber: discNumber,
        durationSeconds: 180,
        isSingle: isSingle,
        featuredArtists: List<String>.from(featuredArtists),
        artworkId: null,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      changed: true,
    );
  }
}

class FakeAlbumProfileEditingService extends AlbumProfileEditingService {
  FakeAlbumProfileEditingService()
    : super(mutationRunner: UnusedSyncMutationRunner());

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

    final timestamp = now ?? DateTime.utc(2026, 1, 1);

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

  PlaybackTrack? lastInsertedTrack;
  int? lastInsertedIndex;

  PlaybackTrack? lastAppendedTrack;

  int loadQueueCallCount = 0;
  int stopCallCount = 0;

  @override
  Stream<PlaybackState> get states => _statesController.stream;

  @override
  PlaybackState get currentState => _currentState;

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

    final queue = tracks.isEmpty
        ? const PlaybackQueue()
        : PlaybackQueue(
            tracks: List<PlaybackTrack>.unmodifiable(tracks),
            currentIndex: startIndex,
          );

    _currentState = PlaybackState(
      queue: queue,
      status: autoPlay ? PlaybackStatus.playing : PlaybackStatus.ready,
      shuffleEnabled: _currentState.shuffleEnabled,
    );
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    lastShuffleEnabled = enabled;

    _currentState = _currentState.copyWith(shuffleEnabled: enabled);
  }

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {
    lastInsertedTrack = track;
    lastInsertedIndex = index;

    _currentState = _currentState.copyWith(
      queue: _currentState.queue.insertTrack(track, index: index),
    );
  }

  @override
  Future<void> appendTrack(PlaybackTrack track) async {
    lastAppendedTrack = track;

    _currentState = _currentState.copyWith(
      queue: _currentState.queue.appendTrack(track),
    );
  }

  @override
  Future<void> play() async {
    _currentState = _currentState.copyWith(status: PlaybackStatus.playing);
  }

  @override
  Future<void> pause() async {
    _currentState = _currentState.copyWith(status: PlaybackStatus.paused);
  }

  @override
  Future<void> seek(Duration position) async {
    _currentState = _currentState.copyWith(position: position);
  }

  @override
  Future<void> skipNext() async {
    if (!_currentState.queue.hasNext) {
      return;
    }

    _currentState = _currentState.copyWith(
      queue: _currentState.queue.moveNext(),
    );
  }

  @override
  Future<void> skipPrevious() async {
    if (!_currentState.queue.hasPrevious) {
      return;
    }

    _currentState = _currentState.copyWith(
      queue: _currentState.queue.movePrevious(),
    );
  }

  @override
  Future<void> skipToIndex(int index) async {
    _currentState = _currentState.copyWith(
      queue: _currentState.queue.moveTo(index),
    );
  }

  @override
  Future<void> removeTrackAt(int index) async {
    _currentState = _currentState.copyWith(
      queue: _currentState.queue.removeTrackAt(index),
    );
  }

  @override
  Future<void> moveTrack({required int oldIndex, required int newIndex}) async {
    _currentState = _currentState.copyWith(
      queue: _currentState.queue.moveTrack(
        oldIndex: oldIndex,
        newIndex: newIndex,
      ),
    );
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    _currentState = _currentState.copyWith(repeatMode: mode);
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    _currentState = const PlaybackState();
  }

  @override
  Future<void> dispose() async {
    await _statesController.close();
  }
}

class FixedRandom implements Random {
  const FixedRandom(this.value);

  final int value;

  @override
  int nextInt(int max) {
    if (max <= 0) {
      throw ArgumentError.value(max, 'max');
    }

    return value % max;
  }

  @override
  bool nextBool() {
    return value.isEven;
  }

  @override
  double nextDouble() {
    return 0.5;
  }
}

class FakeArtworkFilePicker implements ArtworkFilePicker {
  FakeArtworkFilePicker({required this.result});

  final String? result;

  int callCount = 0;

  @override
  Future<String?> pickArtworkFile() async {
    callCount++;
    return result;
  }
}

class FakeTrackArtworkAssignmentService implements ArtworkAssignmentService {
  int assignSongCallCount = 0;
  int clearSongCallCount = 0;

  String? assignedSongId;
  String? assignedFilePath;
  String? clearedSongId;

  @override
  Future<ArtworkAsset> assignSong({
    required String songId,
    required String filePath,
    DateTime? now,
  }) async {
    assignSongCallCount++;
    assignedSongId = songId;
    assignedFilePath = filePath;

    final timestamp = now ?? DateTime.utc(2026, 1, 1);

    return ArtworkAsset(
      id: 'artwork-song',
      filePath: filePath,
      normalizedPath: filePath.toLowerCase().replaceAll('\\', '/'),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  @override
  Future<void> clearSong(String songId, {DateTime? now}) async {
    clearSongCallCount++;
    clearedSongId = songId;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
