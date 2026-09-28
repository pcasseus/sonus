import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/home/presentation/controllers/home_controller.dart';
import 'package:sonus_next/features/home/presentation/scopes/home_scope.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';

void main() {
  testWidgets('creates and auto-loads HomeController when dependencies exist', (
    tester,
  ) async {
    HomeController? controller;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryQueryRepository?>.value(
            value: _FakeLibraryQueryRepository(),
          ),
          Provider<QualifiedPlayRepository?>.value(
            value: _FakeQualifiedPlayRepository(),
          ),
        ],
        child: HomeScope(
          now: () => DateTime(2026, 9, 28, 12),
          child: Builder(
            builder: (context) {
              controller = context.watch<HomeController?>();
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(controller, isNotNull);
    expect(controller!.isLoading, isFalse);
    expect(controller!.hasError, isFalse);
    expect(controller!.hasData, isTrue);
    expect(controller!.snapshot, isNotNull);
    expect(controller!.snapshot!.isEmpty, isTrue);
  });

  testWidgets('exposes no HomeController until all dependencies exist', (
    tester,
  ) async {
    HomeController? controller;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryQueryRepository?>.value(
            value: _FakeLibraryQueryRepository(),
          ),
          Provider<QualifiedPlayRepository?>.value(value: null),
        ],
        child: HomeScope(
          child: Builder(
            builder: (context) {
              controller = context.watch<HomeController?>();
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(controller, isNull);
  });
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => const [];

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async =>
      const [];

  @override
  Future<LibraryTrack?> getTrackById(String songId) async => null;

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => const [];

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async =>
      const [];

  @override
  Future<List<LibraryAlbum>> getAlbums() async => const [];

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async =>
      const [];

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async => null;

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async =>
      const [];

  @override
  Future<List<LibraryArtist>> getArtists() async => const [];

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async => null;
}

class _FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  @override
  Future<void> create(QualifiedPlay play) async {}

  @override
  Future<void> save(QualifiedPlay play) async {}

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

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async => const [];
}
