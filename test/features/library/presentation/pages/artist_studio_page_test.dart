import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/artist_merge_service.dart';
import 'package:sonus_next/features/library/application/services/artist_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/presentation/controllers/artist_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_studio_page.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

void main() {
  group('ArtistStudioPage', () {
    testWidgets('shows artist identity and relationship counts', (
      tester,
    ) async {
      final primaryTrack = createTrack(
        songId: 'primary-song',
        title: 'Primary Song',
      );

      final collaborationTrack = createTrack(
        songId: 'feature-song',
        title: 'Feature Song',
        artistId: 'other-artist',
        featuredArtists: const ['Test Artist'],
      );

      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        albums: [createAlbum()],
        tracks: [primaryTrack],
        allTracks: [primaryTrack, collaborationTrack],
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await controller.load();

      await tester.pumpWidget(
        buildSubject(controller: controller, repository: repository),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('artist-studio-page')),
        findsOneWidget,
      );
      expect(find.text('Artist Studio'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);

      expect(
        find.byKey(
          const ValueKey<String>('artist-studio-relationship-summary'),
        ),
        findsOneWidget,
      );

      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Primary songs'), findsOneWidget);
      expect(find.text('Collaborations'), findsOneWidget);

      expect(find.text('1'), findsNWidgets(3));

      controller.dispose();
    });

    testWidgets('renames artist and refreshes Studio heading', (tester) async {
      final repository = FakeLibraryQueryRepository(artist: createArtist());

      final editingService = FakeArtistProfileEditingService(
        onRename: ({required artistId, required name, required userId}) async {
          repository.artist = createArtist(
            artistId: artistId,
            name: name.trim(),
          );
        },
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        artistProfileEditingService: editingService,
      );

      await controller.load();

      await tester.pumpWidget(
        buildSubject(
          controller: controller,
          repository: repository,
          userId: 'user-1',
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-studio-edit-name')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('artist-studio-name-dialog')),
        findsOneWidget,
      );

      final field = find.byKey(
        const ValueKey<String>('artist-studio-name-field'),
      );

      expect(field, findsOneWidget);

      await tester.enterText(field, 'Renamed Artist');

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-studio-name-save')),
      );

      await tester.pumpAndSettle();

      expect(editingService.renameCallCount, 1);
      expect(editingService.lastUserId, 'user-1');
      expect(editingService.lastArtistId, 'artist-1');
      expect(editingService.lastName, 'Renamed Artist');

      expect(find.text('Renamed Artist'), findsOneWidget);
      expect(find.text('Artist name updated.'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('rename collision points user toward artist merge', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(artist: createArtist());

      final editingService = FakeArtistProfileEditingService(
        onRename: ({required artistId, required name, required userId}) async {
          throw ArtistNameCollisionException(
            artistId: artistId,
            conflictingArtistId: 'artist-existing',
            name: name,
          );
        },
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        artistProfileEditingService: editingService,
      );

      await controller.load();

      await tester.pumpWidget(
        buildSubject(controller: controller, repository: repository),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-studio-edit-name')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('artist-studio-name-field')),
        'Existing Artist',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-studio-name-save')),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('artist-studio-rename-collision-message'),
        ),
        findsOneWidget,
      );

      expect(
        find.text(
          'Another artist already owns this identity. '
          'Use Merge artist to consolidate them.',
        ),
        findsOneWidget,
      );

      controller.dispose();
    });

    testWidgets('merge action is disabled when merge service is unavailable', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(artist: createArtist());

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await controller.load();

      await tester.pumpWidget(
        buildSubject(controller: controller, repository: repository),
      );

      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('artist-studio-merge-artist')),
      );

      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);

      controller.dispose();
    });

    testWidgets(
      'merge flow selects another artist and can cancel confirmation',
      (tester) async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          artists: [
            createArtist(),
            createArtist(artistId: 'artist-target', name: 'Target Artist'),
          ],
        );

        final runner = CountingUnusedSyncMutationRunner();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
        );

        await controller.load();

        await tester.pumpWidget(
          buildSubject(
            controller: controller,
            repository: repository,
            mergeService: ArtistMergeService(mutationRunner: runner),
          ),
        );

        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('artist-studio-merge-artist')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const ValueKey<String>('artist-studio-merge-target-dialog'),
          ),
          findsOneWidget,
        );

        expect(find.text('Target Artist'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey<String>('artist-studio-merge-target-artist-1'),
          ),
          findsNothing,
        );

        await tester.tap(
          find.byKey(
            const ValueKey<String>('artist-studio-merge-target-artist-target'),
          ),
        );

        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const ValueKey<String>('artist-studio-merge-confirmation'),
          ),
          findsOneWidget,
        );

        expect(find.text('Merge Test Artist?'), findsOneWidget);

        expect(
          find.text(
            'Albums, songs, collaboration links, and historical artist '
            'references will move to Target Artist. '
            'The Test Artist identity will then be removed.',
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(runner.callCount, 0);

        expect(
          find.byKey(const ValueKey<String>('artist-studio-page')),
          findsOneWidget,
        );

        controller.dispose();
      },
    );
  });
}

Widget buildSubject({
  required ArtistProfileController controller,
  required LibraryQueryRepository repository,
  String? userId,
  ArtistMergeService? mergeService,
}) {
  return MaterialApp(
    home: ArtistStudioPage(
      controller: controller,
      repository: repository,
      userId: userId,
      mergeService: mergeService,
    ),
  );
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
  List<String> featuredArtists = const [],
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: artistId,
    artistName: artistId == 'artist-1' ? 'Test Artist' : 'Other Artist',
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
    filePath: '/music/$songId.mp3',
    isAvailable: true,
  );
}

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  FakeLibraryQueryRepository({
    this.artist,
    this.albums = const [],
    this.tracks = const [],
    this.allTracks = const [],
    this.artists = const [],
  });

  LibraryArtist? artist;
  final List<LibraryAlbum> albums;
  final List<LibraryTrack> tracks;
  final List<LibraryTrack> allTracks;
  final List<LibraryArtist> artists;

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
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
    return albums;
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
    return artists;
  }
}

typedef FakeArtistRenameCallback =
    Future<void> Function({
      required String? userId,
      required String artistId,
      required String name,
    });

class FakeArtistProfileEditingService extends ArtistProfileEditingService {
  FakeArtistProfileEditingService({this.onRename})
    : super(mutationRunner: CountingUnusedSyncMutationRunner());

  final FakeArtistRenameCallback? onRename;

  int renameCallCount = 0;
  String? lastUserId;
  String? lastArtistId;
  String? lastName;

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

class CountingUnusedSyncMutationRunner implements SyncMutationRunner {
  int callCount = 0;

  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    callCount++;

    throw StateError('Sync mutation runner should not be used by this test.');
  }
}
