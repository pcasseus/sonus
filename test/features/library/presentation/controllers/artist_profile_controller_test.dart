import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/artwork/application/services/artwork_assignment_service.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_file_picker.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/artwork/domain/repositories/artwork_asset_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/artist_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';
import 'package:sonus_next/features/library/presentation/controllers/artist_profile_controller.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

void main() {
  group('ArtistProfileController', () {
    test('loads artist, albums, and tracks', () async {
      final artist = createArtist();
      final album = createAlbum();
      final track = createTrack();

      final repository = FakeLibraryQueryRepository(
        artist: artist,
        albums: [album],
        tracks: [track],
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: artist.artistId,
      );

      await controller.load();

      expect(controller.artist, same(artist));
      expect(controller.albums, [album]);
      expect(controller.tracks, [track]);
      expect(controller.isLoading, isFalse);
      expect(controller.hasError, isFalse);
      expect(controller.isNotFound, isFalse);

      expect(repository.requestedArtistId, artist.artistId);
      expect(repository.requestedAlbumsArtistId, artist.artistId);
      expect(repository.requestedTracksArtistId, artist.artistId);

      controller.dispose();
    });

    test(
      'loads featured tracks separately from primary artist tracks',
      () async {
        final artist = createArtist(name: 'Featured Artist');

        final primaryTrack = createTrack(
          songId: 'primary-song',
          artistId: artist.artistId,
        );

        final featuredTrack = createTrack(
          songId: 'featured-song',
          artistId: 'other-artist',
          featuredArtists: const ['featured artist'],
        );

        final unrelatedTrack = createTrack(
          songId: 'unrelated-song',
          artistId: 'other-artist',
          featuredArtists: const ['Someone Else'],
        );

        final repository = FakeLibraryQueryRepository(
          artist: artist,
          tracks: [primaryTrack],
          allTracks: [primaryTrack, featuredTrack, unrelatedTrack],
        );

        final controller = ArtistProfileController(
          repository: repository,
          artistId: artist.artistId,
        );

        await controller.load();

        expect(controller.tracks, [primaryTrack]);
        expect(controller.featuredTracks, [featuredTrack]);

        controller.dispose();
      },
    );

    test('reports artist not found without loading albums or tracks', () async {
      final repository = FakeLibraryQueryRepository(artist: null);

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'missing-artist',
      );

      await controller.load();

      expect(controller.artist, isNull);
      expect(controller.albums, isEmpty);
      expect(controller.tracks, isEmpty);
      expect(controller.isNotFound, isTrue);
      expect(controller.hasError, isFalse);

      expect(repository.requestedArtistId, 'missing-artist');
      expect(repository.requestedAlbumsArtistId, isNull);
      expect(repository.requestedTracksArtistId, isNull);

      controller.dispose();
    });

    test('captures repository failure', () async {
      final repository = FakeLibraryQueryRepository(
        artistError: StateError('artist failed'),
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await controller.load();

      expect(controller.artist, isNull);
      expect(controller.hasError, isTrue);
      expect(controller.error, isA<StateError>());
      expect(controller.isLoading, isFalse);
      expect(controller.isNotFound, isFalse);

      controller.dispose();
    });

    test('refresh reloads profile data', () async {
      var artistName = 'Original Artist';

      final repository = FakeLibraryQueryRepository(
        artistLoader: (_) async {
          return createArtist(name: artistName);
        },
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await controller.load();

      expect(controller.artist?.name, 'Original Artist');

      artistName = 'Updated Artist';

      await controller.refresh();

      expect(controller.artist?.name, 'Updated Artist');

      expect(repository.artistRequestCount, 2);

      controller.dispose();
    });

    test(
      'changeHeaderArtwork assigns selected artwork and refreshes',
      () async {
        final queryRepository = FakeLibraryQueryRepository(
          artist: createArtist(),
        );

        final artistRepository = FakeArtistRepository(
          artists: [createDomainArtist()],
        );

        final artworkRepository = FakeArtworkAssetRepository();

        final picker = FakeArtworkFilePicker(result: r'C:\Artwork\Header.jpg');

        final controller = ArtistProfileController(
          repository: queryRepository,
          artistId: 'artist-1',
          artworkAssignmentService: createArtworkAssignmentService(
            artworkRepository: artworkRepository,
            artistRepository: artistRepository,
          ),
          artworkFilePicker: picker,
        );

        await controller.load();

        final changed = await controller.changeHeaderArtwork();

        expect(changed, isTrue);
        expect(picker.callCount, 1);

        expect(
          artistRepository.artists['artist-1']!.headerArtworkId,
          isNotNull,
        );

        expect(queryRepository.artistRequestCount, 2);

        controller.dispose();
      },
    );

    test('clearHeaderArtwork clears artwork and refreshes', () async {
      final queryRepository = FakeLibraryQueryRepository(
        artist: createArtist(),
      );

      final artistRepository = FakeArtistRepository(
        artists: [createDomainArtist(headerArtworkId: 'artwork-header')],
      );

      final controller = ArtistProfileController(
        repository: queryRepository,
        artistId: 'artist-1',
        artworkAssignmentService: createArtworkAssignmentService(
          artistRepository: artistRepository,
        ),
      );

      await controller.load();

      final changed = await controller.clearHeaderArtwork();

      expect(changed, isTrue);

      expect(artistRepository.artists['artist-1']!.headerArtworkId, isNull);

      expect(queryRepository.artistRequestCount, 2);

      controller.dispose();
    });

    test(
      'changeTopArtistsArtwork assigns selected artwork and refreshes',
      () async {
        final queryRepository = FakeLibraryQueryRepository(
          artist: createArtist(),
        );

        final artistRepository = FakeArtistRepository(
          artists: [createDomainArtist()],
        );

        final artworkRepository = FakeArtworkAssetRepository();

        final picker = FakeArtworkFilePicker(
          result: r'C:\Artwork\Top Artists.jpg',
        );

        final controller = ArtistProfileController(
          repository: queryRepository,
          artistId: 'artist-1',
          artworkAssignmentService: createArtworkAssignmentService(
            artworkRepository: artworkRepository,
            artistRepository: artistRepository,
          ),
          artworkFilePicker: picker,
        );

        await controller.load();

        final changed = await controller.changeTopArtistsArtwork();

        expect(changed, isTrue);
        expect(picker.callCount, 1);

        expect(
          artistRepository.artists['artist-1']!.topArtistsArtworkId,
          isNotNull,
        );

        expect(queryRepository.artistRequestCount, 2);

        controller.dispose();
      },
    );

    test('clearTopArtistsArtwork clears artwork and refreshes', () async {
      final queryRepository = FakeLibraryQueryRepository(
        artist: createArtist(),
      );

      final artistRepository = FakeArtistRepository(
        artists: [createDomainArtist(topArtistsArtworkId: 'artwork-top')],
      );

      final controller = ArtistProfileController(
        repository: queryRepository,
        artistId: 'artist-1',
        artworkAssignmentService: createArtworkAssignmentService(
          artistRepository: artistRepository,
        ),
      );

      await controller.load();

      final changed = await controller.clearTopArtistsArtwork();

      expect(changed, isTrue);

      expect(artistRepository.artists['artist-1']!.topArtistsArtworkId, isNull);

      expect(queryRepository.artistRequestCount, 2);

      controller.dispose();
    });

    test('cancelled artwork selection does not assign or refresh', () async {
      final queryRepository = FakeLibraryQueryRepository(
        artist: createArtist(),
      );

      final artistRepository = FakeArtistRepository(
        artists: [createDomainArtist()],
      );

      final artworkRepository = FakeArtworkAssetRepository();

      final picker = FakeArtworkFilePicker(result: null);

      final controller = ArtistProfileController(
        repository: queryRepository,
        artistId: 'artist-1',
        artworkAssignmentService: createArtworkAssignmentService(
          artworkRepository: artworkRepository,
          artistRepository: artistRepository,
        ),
        artworkFilePicker: picker,
      );

      await controller.load();

      final changed = await controller.changeHeaderArtwork();

      expect(changed, isFalse);
      expect(picker.callCount, 1);
      expect(artworkRepository.createdAssets, isEmpty);
      expect(artistRepository.savedArtists, isEmpty);
      expect(queryRepository.artistRequestCount, 1);

      controller.dispose();
    });

    test('reports whether track artwork can be edited', () {
      final repository = FakeLibraryQueryRepository(artist: createArtist());

      final service = FakeTrackArtworkAssignmentService();

      final picker = FakeArtworkFilePicker(result: r'C:\Artwork\Song.jpg');

      final editableController = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        artworkAssignmentService: service,
        artworkFilePicker: picker,
      );

      final missingPickerController = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        artworkAssignmentService: service,
      );

      final missingServiceController = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
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
          artist: createArtist(),
          tracks: [createTrack(songId: 'song-artwork')],
        );

        final service = FakeTrackArtworkAssignmentService();

        final picker = FakeArtworkFilePicker(result: r'C:\Artwork\Song.jpg');

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          artworkAssignmentService: service,
          artworkFilePicker: picker,
        );

        await controller.load();

        expect(repository.artistRequestCount, 1);

        final changed = await controller.changeTrackArtwork(
          controller.tracks.single,
        );

        expect(changed, isTrue);
        expect(picker.callCount, 1);
        expect(service.assignSongCallCount, 1);
        expect(service.assignedSongId, 'song-artwork');

        expect(service.assignedFilePath, r'C:\Artwork\Song.jpg');

        expect(repository.artistRequestCount, 2);

        controller.dispose();
      },
    );

    test(
      'cancelled track artwork selection does not assign or refresh',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [createTrack(songId: 'song-artwork')],
        );

        final service = FakeTrackArtworkAssignmentService();

        final picker = FakeArtworkFilePicker(result: null);

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
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
        expect(repository.artistRequestCount, 1);

        controller.dispose();
      },
    );

    test(
      'clearTrackArtwork clears selected song artwork and refreshes',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [createTrack(songId: 'song-artwork')],
        );

        final service = FakeTrackArtworkAssignmentService();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
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
        expect(repository.artistRequestCount, 2);

        controller.dispose();
      },
    );

    test('unavailable artist track can still have artwork changed', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      final service = FakeTrackArtworkAssignmentService();

      final picker = FakeArtworkFilePicker(result: r'C:\Artwork\Missing.jpg');

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
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

    test('reports whether artist track metadata editing is available', () {
      final repository = FakeLibraryQueryRepository();
      final service = FakeTrackProfileEditingService();

      final editableController = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        trackProfileEditingService: service,
      );

      final missingServiceController = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      expect(editableController.canEditTrack('user-1'), isTrue);
      expect(editableController.canEditTrack('  user-1  '), isTrue);
      expect(editableController.canEditTrack(null), isTrue);
      expect(editableController.canEditTrack(''), isTrue);
      expect(editableController.canEditTrack('   '), isTrue);
      expect(missingServiceController.canEditTrack('user-1'), isFalse);
      expect(missingServiceController.canEditTrack(null), isFalse);

      editableController.dispose();
      missingServiceController.dispose();
    });

    test(
      'updateTrack forwards metadata and refreshes artist profile',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [createTrack(songId: 'song-edit', title: 'Original Title')],
        );
        final service = FakeTrackProfileEditingService();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          trackProfileEditingService: service,
        );

        await controller.load();

        expect(repository.artistRequestCount, 1);

        final changed = await controller.updateTrack(
          userId: 'user-1',
          track: controller.tracks.single,
          title: 'Edited Title',
          trackNumber: 7,
          discNumber: 4,
          featuredArtists: const ['Feature One', 'Feature Two'],
          isSingle: true,
        );

        expect(changed, isTrue);
        expect(service.updateCallCount, 1);
        expect(service.lastUserId, 'user-1');
        expect(service.lastSongId, 'song-edit');
        expect(service.lastTitle, 'Edited Title');
        expect(service.lastTrackNumber, 7);
        expect(service.lastDiscNumber, 4);
        expect(service.lastFeaturedArtists, ['Feature One', 'Feature Two']);
        expect(service.lastIsSingle, isTrue);
        expect(repository.artistRequestCount, 2);

        controller.dispose();
      },
    );

    test('unavailable artist track can still have metadata edited', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [
          createTrack(songId: 'missing-edit', filePath: '', isAvailable: false),
        ],
      );
      final service = FakeTrackProfileEditingService();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
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

    test(
      'updateTrack rejects missing service but allows anonymous owner',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [createTrack(songId: 'song-edit')],
        );

        final missingServiceController = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
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

        final anonymousController = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          trackProfileEditingService: service,
        );

        await anonymousController.load();

        final anonymousResult = await anonymousController.updateTrack(
          userId: null,
          track: anonymousController.tracks.single,
          title: 'Edited',
          trackNumber: 1,
          discNumber: 1,
          featuredArtists: const [],
          isSingle: false,
        );

        expect(anonymousResult, isTrue);
        expect(service.updateCallCount, 1);
        expect(service.lastUserId, isNull);
        expect(service.lastSongId, 'song-edit');

        missingServiceController.dispose();
        anonymousController.dispose();
      },
    );

    test('reports whether artist profile editing is available', () {
      final repository = FakeLibraryQueryRepository();

      final editableController = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        artistProfileEditingService: FakeArtistProfileEditingService(),
      );

      final missingServiceController = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      expect(editableController.canEditArtist('user-1'), isTrue);
      expect(editableController.canEditArtist('  user-1  '), isTrue);
      expect(editableController.canEditArtist(null), isTrue);
      expect(editableController.canEditArtist(''), isTrue);
      expect(editableController.canEditArtist('   '), isTrue);

      expect(missingServiceController.canEditArtist('user-1'), isFalse);
      expect(missingServiceController.canEditArtist(null), isFalse);

      editableController.dispose();
      missingServiceController.dispose();
    });

    test('reports whether loaded artist can be removed', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        albums: [createAlbum()],
        tracks: [createTrack()],
      );

      final service = FakeArtistProfileEditingService();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        artistProfileEditingService: service,
      );

      expect(controller.canRemoveArtist('user-1'), isFalse);
      expect(controller.canRemoveArtist(null), isFalse);

      await controller.load();

      expect(controller.canRemoveArtist('user-1'), isTrue);
      expect(controller.canRemoveArtist('  user-1  '), isTrue);
      expect(controller.canRemoveArtist(null), isTrue);
      expect(controller.canRemoveArtist(''), isTrue);
      expect(controller.canRemoveArtist('   '), isTrue);

      controller.dispose();
    });

    test('removeArtist forwards permanent artist identity', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(artistId: 'artist-remove'),
      );

      final service = FakeArtistProfileEditingService();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-remove',
        artistProfileEditingService: service,
      );

      await controller.load();

      final removed = await controller.removeArtist(userId: 'user-1');

      expect(removed, isTrue);
      expect(service.removeCallCount, 1);
      expect(service.lastRemoveUserId, 'user-1');
      expect(service.lastRemoveArtistId, 'artist-remove');

      controller.dispose();
    });

    test(
      'removeArtist rejects unavailable state but allows anonymous owner',
      () async {
        final repository = FakeLibraryQueryRepository(artist: createArtist());

        final missingServiceController = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
        );

        await missingServiceController.load();

        expect(
          await missingServiceController.removeArtist(userId: 'user-1'),
          isFalse,
        );

        missingServiceController.dispose();

        final service = FakeArtistProfileEditingService();

        final anonymousController = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          artistProfileEditingService: service,
        );

        await anonymousController.load();

        expect(await anonymousController.removeArtist(userId: null), isTrue);

        expect(service.removeCallCount, 1);
        expect(service.lastRemoveUserId, isNull);
        expect(service.lastRemoveArtistId, 'artist-1');

        anonymousController.dispose();

        final notLoadedController = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          artistProfileEditingService: service,
        );

        expect(await notLoadedController.removeArtist(userId: null), isFalse);

        expect(service.removeCallCount, 1);

        notLoadedController.dispose();
      },
    );

    test(
      'renameArtist forwards mutation and refreshes artist profile',
      () async {
        final repository = FakeLibraryQueryRepository(artist: createArtist());

        final service = FakeArtistProfileEditingService();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          artistProfileEditingService: service,
        );

        await controller.load();

        expect(repository.artistRequestCount, 1);

        final renamed = await controller.renameArtist(
          userId: 'user-1',
          name: 'Renamed Artist',
        );

        expect(renamed, isTrue);
        expect(service.renameCallCount, 1);
        expect(service.lastUserId, 'user-1');
        expect(service.lastArtistId, 'artist-1');
        expect(service.lastName, 'Renamed Artist');
        expect(repository.artistRequestCount, 2);

        controller.dispose();
      },
    );

    test(
      'renameArtist rejects missing service but allows anonymous owner',
      () async {
        final repository = FakeLibraryQueryRepository(artist: createArtist());

        final missingServiceController = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
        );

        await missingServiceController.load();

        final missingServiceResult = await missingServiceController
            .renameArtist(userId: 'user-1', name: 'Renamed Artist');

        expect(missingServiceResult, isFalse);

        missingServiceController.dispose();

        final service = FakeArtistProfileEditingService();

        final anonymousController = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          artistProfileEditingService: service,
        );

        await anonymousController.load();

        final anonymousResult = await anonymousController.renameArtist(
          userId: null,
          name: 'Renamed Artist',
        );

        expect(anonymousResult, isTrue);
        expect(service.renameCallCount, 1);
        expect(service.lastUserId, isNull);
        expect(service.lastArtistId, 'artist-1');
        expect(service.lastName, 'Renamed Artist');

        anonymousController.dispose();
      },
    );

    test('reports whether artist has playable tracks', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
          createTrack(songId: 'playable-song'),
        ],
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await controller.load();

      expect(controller.hasPlayableTracks, isTrue);

      expect(controller.isTrackPlayable(controller.tracks.first), isFalse);

      expect(controller.isTrackPlayable(controller.tracks.last), isTrue);

      controller.dispose();
    });

    test(
      'playTrack loads the current artist context from the selected song',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [
            createTrack(songId: 'song-1'),
            createTrack(songId: 'song-2'),
            createTrack(songId: 'song-3'),
          ],
        );

        final engine = FakePlaybackEngine();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
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

        await engine.dispose();
        controller.dispose();
      },
    );

    test(
      'playTrack remaps the selected artist song after unavailable tracks are filtered',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
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

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
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

        await engine.dispose();
        controller.dispose();
      },
    );
    test('playTrack ignores unavailable tracks', () async {
      final repository = FakeLibraryQueryRepository();

      final engine = FakePlaybackEngine();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      final unavailableTrack = createTrack(
        songId: 'missing-song',
        filePath: '',
        isAvailable: false,
      );

      await controller.playTrack(unavailableTrack);

      expect(engine.loadQueueCallCount, 0);

      await engine.dispose();
      controller.dispose();
    });

    test(
      'playAll starts from first playable track when shuffle is off',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [
            createTrack(
              songId: 'missing-song',
              filePath: '',
              isAvailable: false,
            ),
            createTrack(songId: 'playable-1'),
            createTrack(songId: 'playable-2'),
          ],
        );

        final engine = FakePlaybackEngine();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        );

        await controller.load();
        await controller.playAll();

        expect(engine.loadQueueCallCount, 1);

        expect(engine.lastLoadedTracks!.map((track) => track.songId), [
          'playable-1',
          'playable-2',
        ]);

        expect(engine.lastStartIndex, 0);
        expect(engine.lastAutoPlay, isTrue);

        await engine.dispose();
        controller.dispose();
      },
    );

    test(
      'playAll chooses among playable tracks when shuffle is enabled',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [
            createTrack(songId: 'playable-1'),
            createTrack(
              songId: 'missing-song',
              filePath: '',
              isAvailable: false,
            ),
            createTrack(songId: 'playable-2'),
          ],
        );

        final engine = FakePlaybackEngine();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
          random: const FixedRandom(1),
        );

        await controller.load();
        await controller.setShuffleEnabled(true);
        await controller.playAll();

        expect(controller.isShuffleEnabled, isTrue);
        expect(engine.lastShuffleEnabled, isTrue);

        expect(engine.lastLoadedTracks!.map((track) => track.songId), [
          'playable-1',
          'playable-2',
        ]);

        expect(engine.lastStartIndex, 1);

        await engine.dispose();
        controller.dispose();
      },
    );

    test('playAll does nothing when no artist tracks are playable', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [
          createTrack(songId: 'missing-1', filePath: '', isAvailable: false),
          createTrack(songId: 'missing-2', filePath: '', isAvailable: false),
        ],
      );

      final engine = FakePlaybackEngine();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();
      await controller.playAll();

      expect(controller.hasPlayableTracks, isFalse);
      expect(engine.loadQueueCallCount, 0);
      expect(engine.stopCallCount, 0);

      await engine.dispose();
      controller.dispose();
    });

    test(
      'toggleShuffle updates playback engine and controller state',
      () async {
        final repository = FakeLibraryQueryRepository();

        final engine = FakePlaybackEngine();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        );

        expect(controller.isShuffleEnabled, isFalse);

        await controller.toggleShuffle();

        expect(controller.isShuffleEnabled, isTrue);
        expect(engine.lastShuffleEnabled, isTrue);

        await controller.toggleShuffle();

        expect(controller.isShuffleEnabled, isFalse);
        expect(engine.lastShuffleEnabled, isFalse);

        await engine.dispose();
        controller.dispose();
      },
    );

    test('addToQueue appends a playable track', () async {
      final repository = FakeLibraryQueryRepository();

      final engine = FakePlaybackEngine();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      final selectedTrack = createTrack(
        songId: 'queue-song',
        title: 'Queue Me',
      );

      await controller.addToQueue(selectedTrack);

      expect(engine.lastAppendedTrack, isNotNull);
      expect(engine.lastAppendedTrack!.songId, 'queue-song');

      await engine.dispose();
      controller.dispose();
    });

    test('playNext inserts a playable track after the current track', () async {
      final repository = FakeLibraryQueryRepository();

      final engine = FakePlaybackEngine();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      final currentTrack = createTrack(
        songId: 'current-song',
        title: 'Current Song',
      );

      final nextTrack = createTrack(songId: 'next-song', title: 'Next Song');

      await controller.playTrack(currentTrack);
      await controller.playNext(nextTrack);

      expect(engine.lastInsertedTrack, isNotNull);
      expect(engine.lastInsertedTrack!.songId, 'next-song');
      expect(engine.lastInsertedIndex, 1);

      await engine.dispose();
      controller.dispose();
    });

    test('playback actions do nothing without playback coordinator', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [createTrack(songId: 'song-1')],
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await controller.load();

      await controller.playTrack(controller.tracks.single);

      await controller.playAll();

      await controller.playNext(controller.tracks.single);

      await controller.addToQueue(controller.tracks.single);

      await controller.toggleShuffle();

      expect(controller.isShuffleEnabled, isFalse);

      controller.dispose();
    });

    test('reports whether song blocking is available', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [createTrack()],
      );
      final songBlockService = FakeSongBlockService();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        songBlockService: songBlockService,
      );

      await controller.load();

      expect(controller.canSetTrackBlocked('user-1'), isTrue);
      expect(controller.canSetTrackBlocked('  user-1  '), isTrue);
      expect(controller.canSetTrackBlocked(null), isTrue);
      expect(controller.canSetTrackBlocked(''), isTrue);
      expect(controller.canSetTrackBlocked('   '), isTrue);

      final missingServicesController = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await missingServicesController.load();
      expect(missingServicesController.canSetTrackBlocked('user-1'), isFalse);

      controller.dispose();
      missingServicesController.dispose();
    });

    test(
      'setTrackBlocked forwards mutation and refreshes artist profile',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [createTrack(songId: 'song-block')],
        );

        final service = FakeSongBlockService();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          songBlockService: service,
        );

        await controller.load();

        expect(repository.artistRequestCount, 1);

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
        expect(repository.artistRequestCount, 2);

        controller.dispose();
      },
    );

    test(
      'blocking mutations allow anonymous users but reject missing services',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [createTrack()],
        );

        final missingServicesController = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
        );

        await missingServicesController.load();

        expect(
          await missingServicesController.setTrackBlocked(
            userId: 'user-1',
            track: missingServicesController.tracks.single,
            isBlocked: true,
          ),
          isFalse,
        );
        final songBlockService = FakeSongBlockService();

        final blankUserController = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          songBlockService: songBlockService,
        );

        await blankUserController.load();

        expect(
          await blankUserController.setTrackBlocked(
            userId: '   ',
            track: blankUserController.tracks.single,
            isBlocked: true,
          ),
          isTrue,
        );
        expect(songBlockService.setBlockedCallCount, 1);
        expect(songBlockService.lastUserId, isNull);
        expect(
          songBlockService.lastSongId,
          blankUserController.tracks.single.songId,
        );
        expect(songBlockService.lastIsBlocked, isTrue);

        missingServicesController.dispose();
        blankUserController.dispose();
      },
    );
  });
}

LibraryArtist createArtist({
  String artistId = 'artist-1',
  String name = 'Test Artist',
}) {
  return LibraryArtist(
    artistId: artistId,
    name: name,
    albumCount: 1,
    songCount: 1,
    dateAdded: DateTime(2026, 1, 1),
  );
}

LibraryAlbum createAlbum({
  String albumId = 'album-1',
  String artistId = 'artist-1',
}) {
  return LibraryAlbum(
    albumId: albumId,
    title: 'Test Album',
    artistId: artistId,
    artistName: 'Test Artist',
    trackCount: 1,
    dateAdded: DateTime(2026, 1, 1),
  );
}

LibraryTrack createTrack({
  String songId = 'song-1',
  String title = 'Test Song',
  String artistId = 'artist-1',
  String? filePath,
  bool isAvailable = true,
  List<String> featuredArtists = const [],
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: artistId,
    artistName: 'Test Artist',
    albumId: 'album-1',
    albumTitle: 'Test Album',
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.values.first,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: featuredArtists,
    dateAdded: DateTime(2026, 1, 1),
    filePath: filePath ?? 'C:/Music/$songId.mp3',
    isAvailable: isAvailable,
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

  final LibraryArtist? artist;
  final List<LibraryAlbum> albums;
  final List<LibraryTrack> tracks;
  final List<LibraryTrack> allTracks;
  final Object? artistError;

  final Future<LibraryArtist?> Function(String artistId)? artistLoader;

  String? requestedArtistId;
  String? requestedAlbumsArtistId;
  String? requestedTracksArtistId;

  int artistRequestCount = 0;

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    requestedArtistId = artistId;
    artistRequestCount++;

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
    requestedAlbumsArtistId = artistId;

    return albums;
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    requestedTracksArtistId = artistId;

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
    required String? userId,
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

class FakeArtistProfileEditingService extends ArtistProfileEditingService {
  FakeArtistProfileEditingService()
    : super(mutationRunner: UnusedSyncMutationRunner());

  int renameCallCount = 0;
  int removeCallCount = 0;

  String? lastUserId;
  String? lastArtistId;
  String? lastName;

  String? lastRemoveUserId;
  String? lastRemoveArtistId;

  @override
  Future<void> removeArtist({
    required String? userId,
    required String artistId,
  }) async {
    removeCallCount++;
    lastRemoveUserId = userId;
    lastRemoveArtistId = artistId;
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

    final timestamp = now ?? DateTime.utc(2026, 1, 1);

    return Artist(
      id: artistId,
      name: name.trim(),
      canonicalName: name.trim().toLowerCase(),
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

ArtworkAssignmentService createArtworkAssignmentService({
  FakeArtworkAssetRepository? artworkRepository,
  FakeArtistRepository? artistRepository,
}) {
  return ArtworkAssignmentService(
    artworkAssetRepository: artworkRepository ?? FakeArtworkAssetRepository(),
    artistRepository: artistRepository ?? FakeArtistRepository(),
    albumEditionRepository: FakeAlbumEditionRepository(),
    songRepository: FakeSongRepository(),
  );
}

Artist createDomainArtist({
  String? headerArtworkId,
  String? topArtistsArtworkId,
}) {
  return Artist(
    id: 'artist-1',
    name: 'Test Artist',
    canonicalName: 'test artist',
    headerArtworkId: headerArtworkId,
    topArtistsArtworkId: topArtistsArtworkId,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
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

class FakeArtworkAssetRepository implements ArtworkAssetRepository {
  final Map<String, ArtworkAsset> assets = {};

  final List<ArtworkAsset> createdAssets = [];

  @override
  Future<void> create(ArtworkAsset artworkAsset) async {
    createdAssets.add(artworkAsset);

    assets[artworkAsset.normalizedPath] = artworkAsset;
  }

  @override
  Future<void> save(ArtworkAsset artworkAsset) async {
    assets[artworkAsset.normalizedPath] = artworkAsset;
  }

  @override
  Future<ArtworkAsset?> getById(String id) async {
    for (final asset in assets.values) {
      if (asset.id == id) {
        return asset;
      }
    }

    return null;
  }

  @override
  Future<ArtworkAsset?> getByNormalizedPath(String normalizedPath) async {
    return assets[normalizedPath];
  }

  @override
  Future<List<ArtworkAsset>> getAll() async {
    return List.unmodifiable(assets.values);
  }
}

class FakeArtistRepository implements ArtistRepository {
  FakeArtistRepository({List<Artist> artists = const []})
    : artists = {for (final artist in artists) artist.id: artist};

  final Map<String, Artist> artists;

  final List<Artist> savedArtists = [];

  @override
  Future<void> create(Artist artist) async {
    artists[artist.id] = artist;
  }

  @override
  Future<void> save(Artist artist) async {
    savedArtists.add(artist);

    artists[artist.id] = artist;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Artist?> getById(String id) async {
    return artists[id];
  }

  @override
  Future<List<Artist>> getAll() async {
    return List.unmodifiable(artists.values);
  }
}

class FakeAlbumEditionRepository implements AlbumEditionRepository {
  @override
  Future<void> create(AlbumEdition edition) async {}

  @override
  Future<void> save(AlbumEdition edition) async {}

  @override
  Future<AlbumEdition?> getById(String id) async {
    return null;
  }

  @override
  Future<List<AlbumEdition>> getAll() async {
    return const [];
  }

  @override
  Future<List<AlbumEdition>> getByAlbumId(String albumId) async {
    return const [];
  }
}

class FakeSongRepository implements SongRepository {
  @override
  Future<void> create(Song song) async {}

  @override
  Future<void> save(Song song) async {}

  @override
  Future<Song?> getById(String id) async {
    return null;
  }

  @override
  Future<List<Song>> getAll() async {
    return const [];
  }

  @override
  Future<List<Song>> getByArtistId(String artistId) async {
    return const [];
  }

  @override
  Future<List<Song>> getByAlbumId(String albumId) async {
    return const [];
  }

  @override
  Future<List<Song>> getByEditionId(String albumEditionId) async {
    return const [];
  }

  @override
  Future<List<Song>> getRecentlyAdded(int limit) async {
    return const [];
  }
}
