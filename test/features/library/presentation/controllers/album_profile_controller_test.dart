import 'package:sonus_next/features/artwork/application/services/artwork_crop_service.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_crop.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/artwork/application/services/artwork_assignment_service.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_file_picker.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/album_edition_track_ordering_service.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/application/services/song_artist_credit_service.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/domain/repositories/song_artist_credit_repository.dart';
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

    test('edition-aware repository loads primary edition by default', () async {
      final repository = FakeEditionAwareLibraryQueryRepository(
        album: createAlbum(
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
          primaryEditionType: AlbumEditionType.standard,
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
              songId: 'standard-1',
              albumEditionId: 'edition-standard',
              albumEditionTitle: 'Standard',
            ),
            createTrack(
              songId: 'standard-2',
              albumEditionId: 'edition-standard',
              albumEditionTitle: 'Standard',
            ),
          ],
          'edition-deluxe': [
            createTrack(
              songId: 'deluxe-1',
              albumEditionId: 'edition-deluxe',
              albumEditionTitle: 'Deluxe',
              albumEditionType: AlbumEditionType.deluxe,
            ),
          ],
        },
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.editions, hasLength(2));
      expect(controller.selectedEdition?.editionId, 'edition-standard');

      expect(controller.tracks.map((track) => track.songId), [
        'standard-1',
        'standard-2',
      ]);

      expect(controller.editionCount, 2);
      expect(controller.hasMultipleEditions, isTrue);
      expect(controller.editionTitles, ['Standard', 'Deluxe']);

      expect(repository.requestedEditionAlbumId, 'album-1');
      expect(repository.requestedTrackEditionIds, ['edition-standard']);

      // The capability path does not use the legacy whole-album track query.
      expect(repository.requestedTracksAlbumId, isNull);

      controller.dispose();
    });

    group('opening on a known edition', () {
      FakeEditionAwareLibraryQueryRepository twoEditions() =>
          FakeEditionAwareLibraryQueryRepository(
            album: createAlbum(
              primaryEditionId: 'edition-deluxe',
              primaryEditionTitle: 'Deluxe',
              primaryEditionType: AlbumEditionType.deluxe,
            ),
            editions: [
              createLibraryEdition(
                editionId: 'edition-deluxe',
                title: 'Deluxe',
                type: AlbumEditionType.deluxe,
                isPrimary: true,
              ),
              createLibraryEdition(
                editionId: 'edition-standard',
                title: 'Standard',
                type: AlbumEditionType.standard,
              ),
            ],
            editionTracks: {
              'edition-deluxe': [
                createTrack(
                  songId: 'deluxe-1',
                  albumEditionId: 'edition-deluxe',
                  albumEditionTitle: 'Deluxe',
                  albumEditionType: AlbumEditionType.deluxe,
                ),
              ],
              'edition-standard': [
                createTrack(
                  songId: 'standard-1',
                  albumEditionId: 'edition-standard',
                  albumEditionTitle: 'Standard',
                ),
              ],
            },
          );

      test('opens on the linked song edition, not the primary', () async {
        final repository = twoEditions();
        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          initialEditionId: 'edition-standard',
        );

        await controller.load();

        expect(controller.selectedEdition?.editionId, 'edition-standard');
        expect(controller.tracks.map((track) => track.songId), ['standard-1']);
        expect(repository.requestedTrackEditionIds, ['edition-standard']);
        controller.dispose();
      });

      test('an edition from elsewhere falls back to the primary', () async {
        final controller = AlbumProfileController(
          repository: twoEditions(),
          albumId: 'album-1',
          initialEditionId: 'edition-of-another-album',
        );

        await controller.load();

        expect(controller.selectedEdition?.editionId, 'edition-deluxe');
        controller.dispose();
      });

      test('a later choice survives reloads', () async {
        final controller = AlbumProfileController(
          repository: twoEditions(),
          albumId: 'album-1',
          initialEditionId: 'edition-standard',
        );

        await controller.load();
        await controller.selectEdition('edition-deluxe');
        await controller.load();

        expect(controller.selectedEdition?.editionId, 'edition-deluxe');
        controller.dispose();
      });
    });

    test('selectEdition swaps the complete playback context', () async {
      final repository = FakeEditionAwareLibraryQueryRepository(
        album: createAlbum(
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
          primaryEditionType: AlbumEditionType.standard,
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
              songId: 'shared-song',
              albumEditionId: 'edition-standard',
              albumEditionTitle: 'Standard',
              trackNumber: 1,
            ),
          ],
          'edition-deluxe': [
            createTrack(
              songId: 'shared-song',
              albumEditionId: 'edition-deluxe',
              albumEditionTitle: 'Deluxe',
              albumEditionType: AlbumEditionType.deluxe,
              trackNumber: 3,
            ),
            createTrack(
              songId: 'deluxe-bonus',
              albumEditionId: 'edition-deluxe',
              albumEditionTitle: 'Deluxe',
              albumEditionType: AlbumEditionType.deluxe,
              trackNumber: 4,
            ),
          ],
        },
      );

      final engine = FakePlaybackEngine();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();

      final changed = await controller.selectEdition('edition-deluxe');

      expect(changed, isTrue);
      expect(controller.selectedEdition?.editionId, 'edition-deluxe');
      expect(controller.selectedEdition?.type, AlbumEditionType.deluxe);

      expect(controller.tracks.map((track) => track.songId), [
        'shared-song',
        'deluxe-bonus',
      ]);

      expect(controller.tracks.first.trackNumber, 3);

      await controller.playAll();

      expect(engine.loadQueueCallCount, 1);
      expect(engine.lastLoadedTracks!.map((track) => track.songId), [
        'shared-song',
        'deluxe-bonus',
      ]);
      expect(engine.lastStartIndex, 0);
      expect(engine.lastAutoPlay, isTrue);

      controller.dispose();
      await engine.dispose();
    });

    test(
      'refresh preserves the selected edition when it still exists',
      () async {
        final repository = FakeEditionAwareLibraryQueryRepository(
          album: createAlbum(
            primaryEditionId: 'edition-standard',
            primaryEditionTitle: 'Standard',
            primaryEditionType: AlbumEditionType.standard,
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
                songId: 'standard-song',
                albumEditionId: 'edition-standard',
              ),
            ],
            'edition-deluxe': [
              createTrack(
                songId: 'deluxe-song',
                albumEditionId: 'edition-deluxe',
                albumEditionTitle: 'Deluxe',
                albumEditionType: AlbumEditionType.deluxe,
              ),
            ],
          },
        );

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
        );

        await controller.load();
        await controller.selectEdition('edition-deluxe');
        await controller.refresh();

        expect(controller.selectedEdition?.editionId, 'edition-deluxe');
        expect(controller.tracks.single.songId, 'deluxe-song');

        expect(repository.requestedTrackEditionIds, [
          'edition-standard',
          'edition-deluxe',
          'edition-deluxe',
        ]);

        controller.dispose();
      },
    );

    test(
      'Album Studio reorder targets selected edition and preserves selection',
      () async {
        final repository = FakeEditionAwareLibraryQueryRepository(
          album: createAlbum(
            primaryEditionId: 'edition-standard',
            primaryEditionTitle: 'Standard',
            primaryEditionType: AlbumEditionType.standard,
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
                songId: 'standard-song',
                albumEditionId: 'edition-standard',
              ),
            ],
            'edition-deluxe': [
              createTrack(
                songId: 'deluxe-a',
                albumEditionId: 'edition-deluxe',
                albumEditionTitle: 'Deluxe',
                albumEditionType: AlbumEditionType.deluxe,
              ),
              createTrack(
                songId: 'deluxe-b',
                albumEditionId: 'edition-deluxe',
                albumEditionTitle: 'Deluxe',
                albumEditionType: AlbumEditionType.deluxe,
              ),
            ],
          },
        );

        final service = FakeAlbumEditionTrackOrderingService();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          albumEditionTrackOrderingService: service,
        );

        await controller.load();
        await controller.selectEdition('edition-deluxe');

        expect(controller.canEditAlbumStudio(null), isTrue);

        final changed = await controller.reorderSelectedEdition(
          userId: ' user-1 ',
          orderedSongIds: const ['deluxe-b', 'deluxe-a'],
          autoRenumber: true,
        );

        expect(changed, isTrue);
        expect(service.reorderCallCount, 1);
        expect(service.lastUserId, ' user-1 ');
        expect(service.lastEditionId, 'edition-deluxe');
        expect(service.lastOrderedSongIds, ['deluxe-b', 'deluxe-a']);
        expect(service.lastAutoRenumber, isTrue);

        expect(controller.selectedEdition?.editionId, 'edition-deluxe');

        expect(repository.requestedTrackEditionIds, [
          'edition-standard',
          'edition-deluxe',
          'edition-deluxe',
        ]);

        controller.dispose();
      },
    );

    test('Sort by disc & track targets the selected edition', () async {
      final repository = FakeEditionAwareLibraryQueryRepository(
        album: createAlbum(
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
          primaryEditionType: AlbumEditionType.standard,
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
              songId: 'standard-song',
              albumEditionId: 'edition-standard',
            ),
          ],
          'edition-deluxe': [
            createTrack(
              songId: 'deluxe-a',
              albumEditionId: 'edition-deluxe',
              albumEditionTitle: 'Deluxe',
              albumEditionType: AlbumEditionType.deluxe,
            ),
          ],
        },
      );
      final service = FakeAlbumEditionTrackOrderingService();
      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        albumEditionTrackOrderingService: service,
      );

      await controller.load();
      await controller.selectEdition('edition-deluxe');

      final changed = await controller.sortSelectedEditionByDiscAndTrack(
        userId: 'user-1',
      );

      expect(changed, isTrue);
      expect(service.sortCallCount, 1);
      expect(service.lastEditionId, 'edition-deluxe');
      expect(controller.selectedEdition?.editionId, 'edition-deluxe');

      controller.dispose();
    });

    test(
      'Album Studio placement targets selected edition membership',
      () async {
        final repository = FakeEditionAwareLibraryQueryRepository(
          album: createAlbum(
            primaryEditionId: 'edition-standard',
            primaryEditionTitle: 'Standard',
            primaryEditionType: AlbumEditionType.standard,
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
                songId: 'shared-song',
                albumEditionId: 'edition-standard',
              ),
            ],
            'edition-deluxe': [
              createTrack(
                songId: 'shared-song',
                albumEditionId: 'edition-deluxe',
                albumEditionTitle: 'Deluxe',
                albumEditionType: AlbumEditionType.deluxe,
                trackNumber: 5,
                discNumber: 2,
              ),
            ],
          },
        );

        final service = FakeAlbumEditionTrackOrderingService();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          albumEditionTrackOrderingService: service,
        );

        await controller.load();
        await controller.selectEdition('edition-deluxe');

        final track = controller.tracks.single;

        final changed = await controller.updateSelectedEditionTrackPlacement(
          userId: null,
          track: track,
          discNumber: 3,
          trackNumber: 12,
        );

        expect(changed, isTrue);
        expect(service.placementCallCount, 1);
        expect(service.lastEditionId, 'edition-deluxe');
        expect(service.lastSongId, 'shared-song');
        expect(service.lastDiscNumber, 3);
        expect(service.lastTrackNumber, 12);

        expect(controller.selectedEdition?.editionId, 'edition-deluxe');

        controller.dispose();
      },
    );

    test(
      'Album Studio is unavailable without explicit edition capability',
      () async {
        final controller = AlbumProfileController(
          repository: FakeLibraryQueryRepository(
            album: createAlbum(),
            tracks: [createTrack()],
          ),
          albumId: 'album-1',
          albumEditionTrackOrderingService:
              FakeAlbumEditionTrackOrderingService(),
        );

        await controller.load();

        expect(controller.canEditAlbumStudio(null), isFalse);

        expect(
          await controller.reorderSelectedEdition(
            orderedSongIds: const ['song-1'],
          ),
          isFalse,
        );

        controller.dispose();
      },
    );
    test('legacy repository keeps whole-album fallback behavior', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(
            songId: 'standard-song',
            albumEditionId: 'edition-standard',
            albumEditionTitle: 'Standard',
          ),
          createTrack(
            songId: 'deluxe-song',
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

      expect(controller.hasEditionQueryCapability, isFalse);
      expect(controller.editions, isEmpty);
      expect(controller.selectedEdition, isNull);
      expect(controller.tracks, hasLength(2));
      expect(controller.editionCount, 2);
      expect(controller.editionTitles, ['Standard', 'Deluxe']);
      expect(repository.requestedTracksAlbumId, 'album-1');

      expect(await controller.selectEdition('edition-deluxe'), isFalse);

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

    group('SN-45: each edition keeps its own cover', () {
      FakeEditionAwareLibraryQueryRepository editionRepository({
        String? deluxeArtwork,
      }) => FakeEditionAwareLibraryQueryRepository(
        album: createAlbum(
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
          primaryEditionType: AlbumEditionType.standard,
        ),
        editions: [
          createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
            artworkPath: '/art/standard.jpg',
          ),
          createLibraryEdition(
            editionId: 'edition-deluxe',
            title: 'Deluxe',
            type: AlbumEditionType.deluxe,
            artworkPath: deluxeArtwork,
          ),
        ],
        editionTracks: {
          'edition-standard': [createTrack(songId: 'a')],
          'edition-deluxe': [createTrack(songId: 'a')],
        },
      );

      test('switching editions switches the cover', () async {
        final controller = AlbumProfileController(
          repository: editionRepository(deluxeArtwork: '/art/deluxe.jpg'),
          albumId: 'album-1',
        );
        addTearDown(controller.dispose);
        await controller.load();

        expect(controller.artworkPath, '/art/standard.jpg');

        await controller.selectEdition('edition-deluxe');
        expect(controller.artworkPath, '/art/deluxe.jpg');
        expect(controller.selectedEditionHasOwnArtwork, isTrue);

        await controller.selectEdition('edition-standard');
        expect(controller.artworkPath, '/art/standard.jpg');
      });

      test('an edition without a cover shows the primary cover', () async {
        final controller = AlbumProfileController(
          repository: editionRepository(),
          albumId: 'album-1',
        );
        addTearDown(controller.dispose);
        await controller.load();
        await controller.selectEdition('edition-deluxe');

        expect(controller.selectedEditionHasOwnArtwork, isFalse);
        expect(controller.artworkPath, '/art/standard.jpg');
      });

      test('changing artwork on Deluxe leaves Standard alone', () async {
        final service = FakeEditionArtworkAssignmentService();
        final controller = AlbumProfileController(
          repository: editionRepository(),
          albumId: 'album-1',
          artworkAssignmentService: service,
          artworkFilePicker: FakeArtworkFilePicker(result: '/new.jpg'),
        );
        addTearDown(controller.dispose);
        await controller.load();
        await controller.selectEdition('edition-deluxe');

        expect(await controller.changeArtwork(), isTrue);
        expect(service.assigned, [('edition-deluxe', '/new.jpg')]);

        expect(await controller.clearArtwork(), isTrue);
        expect(service.cleared, ['edition-deluxe']);
      });

      test('a crop is applied to the edition on screen', () async {
        final crops = FakeArtworkCropService();
        final controller = AlbumProfileController(
          repository: editionRepository(deluxeArtwork: '/art/deluxe.jpg'),
          albumId: 'album-1',
          artworkAssignmentService: FakeEditionArtworkAssignmentService(),
          artworkFilePicker: FakeArtworkFilePicker(result: '/new.jpg'),
          artworkCropService: crops,
        );
        addTearDown(controller.dispose);
        await controller.load();
        await controller.selectEdition('edition-deluxe');

        expect(controller.canCropArtwork, isTrue);
        final rect = CropRect(left: 0, top: 0, width: 1, height: 1);
        expect(
          await controller.applyArtworkCrop(sourcePath: '/new.jpg', rect: rect),
          isTrue,
        );
        expect(crops.applied, [
          (ArtworkCropTarget.albumEdition, 'edition-deluxe', '/new.jpg', rect),
        ]);

        await controller.resetArtworkCrop();
        expect(crops.resets, ['edition-deluxe']);
      });

      test('an edition without its own cover has nothing to move', () async {
        final crops = FakeArtworkCropService();
        final controller = AlbumProfileController(
          repository: editionRepository(),
          albumId: 'album-1',
          artworkAssignmentService: FakeEditionArtworkAssignmentService(),
          artworkFilePicker: FakeArtworkFilePicker(result: '/new.jpg'),
          artworkCropService: crops,
        );
        addTearDown(controller.dispose);
        await controller.load();
        await controller.selectEdition('edition-deluxe');

        expect(await controller.artworkRepositionSource(), isNull);
        expect(crops.repositionRequests, isEmpty);
      });

      test('the primary edition is edited when it is on screen', () async {
        final service = FakeEditionArtworkAssignmentService();
        final controller = AlbumProfileController(
          repository: editionRepository(),
          albumId: 'album-1',
          artworkAssignmentService: service,
          artworkFilePicker: FakeArtworkFilePicker(result: '/new.jpg'),
        );
        addTearDown(controller.dispose);
        await controller.load();

        await controller.changeArtwork();
        expect(service.assigned, [('edition-standard', '/new.jpg')]);
      });
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
      expect(editableController.canEditTrack(null), isTrue);
      expect(editableController.canEditTrack(''), isTrue);
      expect(editableController.canEditTrack('   '), isTrue);

      expect(missingServiceController.canEditTrack('user-1'), isFalse);
      expect(missingServiceController.canEditTrack(null), isFalse);

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

    test(
      'updateTrackWithCredits forwards structured credits and refreshes album profile',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(
              songId: 'song-structured-edit',
              title: 'Original Title',
            ),
          ],
        );
        final service = FakeTrackProfileEditingService();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          trackProfileEditingService: service,
        );

        await controller.load();

        expect(repository.albumRequestCount, 1);

        final changed = await controller.updateTrackWithCredits(
          userId: 'user-1',
          track: controller.tracks.single,
          title: 'Structured Title',
          trackNumber: 7,
          discNumber: 3,
          additionalCredits: const [
            SongArtistCreditInput(
              creditedName: 'Co Primary Artist',
              role: SongArtistCreditRole.coPrimary,
              artistId: 'artist-co-primary',
            ),
            SongArtistCreditInput(
              creditedName: 'Guest Artist',
              role: SongArtistCreditRole.guest,
            ),
          ],
          isSingle: true,
        );

        expect(changed, isTrue);
        expect(service.structuredUpdateCallCount, 1);
        expect(service.lastUserId, 'user-1');
        expect(service.lastSongId, 'song-structured-edit');

        final credits = service.lastAdditionalCredits!;
        expect(credits, hasLength(2));
        expect(credits[0].creditedName, 'Co Primary Artist');
        expect(credits[0].role, SongArtistCreditRole.coPrimary);
        expect(credits[0].artistId, 'artist-co-primary');
        expect(credits[1].creditedName, 'Guest Artist');
        expect(credits[1].role, SongArtistCreditRole.guest);
        expect(credits[1].artistId, isNull);

        expect(repository.albumRequestCount, 2);

        controller.dispose();
      },
    );
    test(
      'getTrackAdditionalCredits excludes primary and returns structured credits in position order',
      () async {
        final now = DateTime.utc(2026, 1, 1);

        final creditRepository = FakeSongArtistCreditRepository(
          credits: [
            SongArtistCredit(
              id: 'credit-primary',
              songId: 'song-credit-read',
              artistId: 'artist-primary',
              creditedName: 'Primary Artist',
              canonicalCreditedName: 'primary artist',
              role: SongArtistCreditRole.primary,
              position: 0,
              createdAt: now,
              updatedAt: now,
            ),
            SongArtistCredit(
              id: 'credit-coprimary',
              songId: 'song-credit-read',
              artistId: 'artist-coprimary',
              creditedName: 'Co Primary Artist',
              canonicalCreditedName: 'co primary artist',
              role: SongArtistCreditRole.coPrimary,
              position: 3,
              createdAt: now,
              updatedAt: now,
            ),
            SongArtistCredit(
              id: 'credit-guest',
              songId: 'song-credit-read',
              creditedName: 'Guest Artist',
              canonicalCreditedName: 'guest artist',
              role: SongArtistCreditRole.guest,
              position: 1,
              createdAt: now,
              updatedAt: now,
            ),
            SongArtistCredit(
              id: 'credit-featured',
              songId: 'song-credit-read',
              creditedName: 'Featured Artist',
              canonicalCreditedName: 'featured artist',
              role: SongArtistCreditRole.featured,
              position: 2,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );

        final controller = AlbumProfileController(
          repository: FakeLibraryQueryRepository(
            album: createAlbum(),
            tracks: const [],
          ),
          albumId: 'album-1',
          songArtistCreditRepository: creditRepository,
        );

        final credits = await controller.getTrackAdditionalCredits(
          'song-credit-read',
        );

        expect(credits, hasLength(3));

        expect(credits.map((credit) => credit.role).toList(), [
          SongArtistCreditRole.guest,
          SongArtistCreditRole.featured,
          SongArtistCreditRole.coPrimary,
        ]);

        expect(credits.map((credit) => credit.creditedName).toList(), [
          'Guest Artist',
          'Featured Artist',
          'Co Primary Artist',
        ]);

        expect(credits[0].artistId, isNull);
        expect(credits[1].artistId, isNull);
        expect(credits[2].artistId, 'artist-coprimary');

        controller.dispose();
      },
    );
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

    test(
      'updateTrack rejects missing service but allows anonymous owner',
      () async {
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

        final anonymousController = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
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
      expect(editableController.canEditAlbumProfile(null), isTrue);
      expect(editableController.canEditAlbumProfile(''), isTrue);
      expect(editableController.canEditAlbumProfile('   '), isTrue);

      final missingServiceController = AlbumProfileController(
        repository: editableRepository,
        albumId: 'album-1',
      );

      await missingServiceController.load();

      expect(missingServiceController.canEditAlbumProfile('user-1'), isFalse);
      expect(missingServiceController.canEditAlbumProfile(null), isFalse);

      final missingEditionRepository = FakeLibraryQueryRepository(
        album: createAlbum(),
      );

      final missingEditionController = AlbumProfileController(
        repository: missingEditionRepository,
        albumId: 'album-1',
        albumProfileEditingService: FakeAlbumProfileEditingService(),
      );

      await missingEditionController.load();

      expect(missingEditionController.canEditAlbumProfile(null), isFalse);

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

    test('updateProfile allows anonymous owner', () async {
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
        userId: null,
        title: 'Renamed Album',
        editionTitle: 'Deluxe',
        editionType: AlbumEditionType.deluxe,
        releaseDate: null,
        genre: null,
      );

      expect(updated, isTrue);
      expect(service.updateCallCount, 1);
      expect(service.lastUserId, isNull);
      expect(service.lastAlbumId, 'album-1');
      expect(service.lastPrimaryEditionId, 'edition-primary');

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
      expect(controller.canSetTrackBlocked(null), isTrue);
      expect(controller.canSetTrackBlocked(''), isTrue);
      expect(controller.canSetTrackBlocked('   '), isTrue);
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

    test(
      'setTrackBlocked rejects missing service but allows anonymous local mutation',
      () async {
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
          isTrue,
        );

        expect(service.setBlockedCallCount, 1);
        expect(service.lastUserId, isNull);
        expect(service.lastSongId, blankUserController.tracks.single.songId);
        expect(service.lastIsBlocked, isTrue);

        missingServiceController.dispose();
        blankUserController.dispose();
      },
    );
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

  String? requestedEditionAlbumId;
  final List<String> requestedTrackEditionIds = [];

  @override
  Future<List<LibraryAlbumEdition>> getAlbumEditions(String albumId) async {
    requestedEditionAlbumId = albumId;
    return editions;
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumEditionId(String editionId) async {
    requestedTrackEditionIds.add(editionId);
    return editionTracks[editionId] ?? const [];
  }
}

class FakeAlbumEditionTrackOrderingService
    extends AlbumEditionTrackOrderingService {
  FakeAlbumEditionTrackOrderingService()
    : super(mutationRunner: UnusedSyncMutationRunner());

  int reorderCallCount = 0;
  int placementCallCount = 0;
  int sortCallCount = 0;

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
  Future<AlbumEditionReorderResult> sortByDiscAndTrack({
    required String albumEditionId,
    String? userId,
    DateTime? now,
  }) async {
    sortCallCount++;
    lastUserId = userId;
    lastEditionId = albumEditionId;

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

class FakeSongArtistCreditRepository implements SongArtistCreditRepository {
  FakeSongArtistCreditRepository({this.credits = const []});

  List<SongArtistCredit> credits;

  @override
  Future<void> create(SongArtistCredit credit) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(SongArtistCredit credit) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteBySongId(String songId) {
    throw UnimplementedError();
  }

  @override
  Future<SongArtistCredit?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<SongArtistCredit>> getBySongId(String songId) async {
    return credits.where((credit) => credit.songId == songId).toList();
  }

  @override
  Future<List<SongArtistCredit>> getByArtistId(String artistId) {
    throw UnimplementedError();
  }

  @override
  Future<List<SongArtistCredit>> getUnlinkedByCanonicalName(
    String canonicalName,
  ) {
    throw UnimplementedError();
  }
}

class FakeTrackProfileEditingService extends TrackProfileEditingService {
  FakeTrackProfileEditingService()
    : super(mutationRunner: UnusedSyncMutationRunner());

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
    String? placementEditionId,
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
    String? placementEditionId,
    DateTime? now,
  }) async {
    structuredUpdateCallCount++;
    lastAdditionalCredits = List<SongArtistCreditInput>.from(additionalCredits);

    return updateTrack(
      userId: userId,
      songId: songId,
      title: title,
      trackNumber: trackNumber,
      discNumber: discNumber,
      featuredArtists: const [],
      isSingle: isSingle,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: albumEditionId,
      now: now,
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

class FakeEditionArtworkAssignmentService implements ArtworkAssignmentService {
  final List<(String, String)> assigned = [];
  final List<String> cleared = [];

  @override
  Future<ArtworkAsset> assignAlbumEdition({
    required String albumEditionId,
    required String filePath,
    DateTime? now,
  }) async {
    assigned.add((albumEditionId, filePath));
    final timestamp = now ?? DateTime.utc(2026, 1, 1);
    return ArtworkAsset(
      id: 'artwork-$albumEditionId',
      filePath: filePath,
      normalizedPath: filePath.toLowerCase(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  @override
  Future<void> clearAlbumEdition(String albumEditionId, {DateTime? now}) async {
    cleared.add(albumEditionId);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeArtworkCropService implements ArtworkCropService {
  final List<(ArtworkCropTarget, String, String, CropRect)> applied = [];
  final List<String> resets = [];
  final List<String> repositionRequests = [];

  @override
  Future<void> apply({
    required ArtworkCropTarget target,
    required String targetId,
    required String sourcePath,
    required CropRect rect,
    String? userId,
  }) async {
    applied.add((target, targetId, sourcePath, rect));
  }

  @override
  Future<bool> reset({
    required ArtworkCropTarget target,
    required String targetId,
    required String? currentArtworkId,
    String? userId,
  }) async {
    resets.add(targetId);
    return true;
  }

  @override
  Future<ArtworkCropSource?> repositionSource({
    required ArtworkCropTarget target,
    required String targetId,
    required String? currentArtworkId,
    required String? currentArtworkPath,
  }) async {
    repositionRequests.add(targetId);
    return null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
