import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/controllers/library_artists_controller.dart';

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  List<LibraryArtist> artists = const [];
  Object? artistsError;

  @override
  Future<List<LibraryArtist>> getArtists() async {
    final error = artistsError;

    if (error != null) {
      throw error;
    }

    return artists;
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async => null;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => const [];

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async =>
      const [];

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async => null;

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async =>
      const [];

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => const [];

  @override
  Future<LibraryTrack?> getTrackById(String songId) async => null;

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async =>
      const [];

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => const [];

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async =>
      const [];
}

void main() {
  test('loads artists from repository', () async {
    final repository = FakeLibraryQueryRepository()
      ..artists = [
        LibraryArtist(
          artistId: 'artist-1',
          name: 'Artist One',
          albumCount: 2,
          songCount: 10,
          dateAdded: DateTime.utc(2026, 9, 11),
        ),
      ];

    final controller = LibraryArtistsController(repository: repository);

    await controller.load();

    expect(controller.isLoading, isFalse);
    expect(controller.hasError, isFalse);
    expect(controller.artists, hasLength(1));
    expect(controller.artists.single.name, 'Artist One');
  });

  test('reports an empty artist library', () async {
    final repository = FakeLibraryQueryRepository();

    final controller = LibraryArtistsController(repository: repository);

    await controller.load();

    expect(controller.isEmpty, isTrue);
    expect(controller.artists, isEmpty);
  });

  test('captures repository failures', () async {
    final repository = FakeLibraryQueryRepository()
      ..artistsError = StateError('Query failed');

    final controller = LibraryArtistsController(repository: repository);

    await controller.load();

    expect(controller.isLoading, isFalse);
    expect(controller.hasError, isTrue);
    expect(controller.error, isA<StateError>());
  });
}
