import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/home/application/models/home_snapshot.dart';
import 'package:sonus_next/features/home/application/services/home_data_service.dart';
import 'package:sonus_next/features/home/presentation/controllers/home_controller.dart';

void main() {
  final referenceLocal = DateTime(2026, 9, 28, 12);

  test('loads and exposes a home snapshot', () async {
    const snapshot = HomeSnapshot(
      recentlyAddedTracks: [],
      recentlyAddedAlbums: [],
      weeklyPopularTracks: [],
      weeklyTopArtists: [],
    );

    final service = _FakeHomeDataService(snapshot: snapshot);

    final controller = HomeController(
      service: service,
      now: () => referenceLocal,
    );

    await controller.load();

    expect(controller.snapshot, same(snapshot));
    expect(controller.hasData, isTrue);
    expect(controller.isLoading, isFalse);
    expect(controller.hasError, isFalse);
    expect(controller.isEmpty, isTrue);

    expect(service.callCount, 1);
    expect(service.lastReferenceLocal, referenceLocal);
  });

  test('captures service failures', () async {
    final service = _FakeHomeDataService(error: StateError('Home failed'));

    final controller = HomeController(
      service: service,
      now: () => referenceLocal,
    );

    await controller.load();

    expect(controller.snapshot, isNull);
    expect(controller.isLoading, isFalse);
    expect(controller.hasError, isTrue);
    expect(controller.error, isA<StateError>());
  });

  test('load ignores a second request while already loading', () async {
    final completer = Completer<HomeSnapshot>();

    final service = _FakeHomeDataService(pendingResult: completer.future);

    final controller = HomeController(
      service: service,
      now: () => referenceLocal,
    );

    final firstLoad = controller.load();

    expect(controller.isLoading, isTrue);

    await controller.load();

    expect(service.callCount, 1);

    completer.complete(
      const HomeSnapshot(
        recentlyAddedTracks: [],
        recentlyAddedAlbums: [],
        weeklyPopularTracks: [],
        weeklyTopArtists: [],
      ),
    );

    await firstLoad;

    expect(controller.isLoading, isFalse);
    expect(controller.hasData, isTrue);
  });

  test('refresh replaces the previous snapshot', () async {
    const firstSnapshot = HomeSnapshot(
      recentlyAddedTracks: [],
      recentlyAddedAlbums: [],
      weeklyPopularTracks: [],
      weeklyTopArtists: [],
    );

    const secondSnapshot = HomeSnapshot(
      recentlyAddedTracks: [],
      recentlyAddedAlbums: [],
      weeklyPopularTracks: [],
      weeklyTopArtists: [],
    );

    final service = _FakeHomeDataService(snapshot: firstSnapshot);

    final controller = HomeController(
      service: service,
      now: () => referenceLocal,
    );

    await controller.load();

    expect(controller.snapshot, same(firstSnapshot));

    service.snapshot = secondSnapshot;

    await controller.refresh();

    expect(controller.snapshot, same(secondSnapshot));
    expect(service.callCount, 2);
  });

  test('refresh preserves existing data when refresh fails', () async {
    const snapshot = HomeSnapshot(
      recentlyAddedTracks: [],
      recentlyAddedAlbums: [],
      weeklyPopularTracks: [],
      weeklyTopArtists: [],
    );

    final service = _FakeHomeDataService(snapshot: snapshot);

    final controller = HomeController(
      service: service,
      now: () => referenceLocal,
    );

    await controller.load();

    service.error = StateError('Refresh failed');

    await controller.refresh();

    expect(controller.snapshot, same(snapshot));
    expect(controller.hasError, isTrue);
    expect(controller.error, isA<StateError>());
  });
}

class _FakeHomeDataService implements HomeDataService {
  _FakeHomeDataService({
    this.snapshot = const HomeSnapshot(
      recentlyAddedTracks: [],
      recentlyAddedAlbums: [],
      weeklyPopularTracks: [],
      weeklyTopArtists: [],
    ),
    this.error,
    this.pendingResult,
  });

  HomeSnapshot snapshot;
  Object? error;
  Future<HomeSnapshot>? pendingResult;

  int callCount = 0;
  DateTime? lastReferenceLocal;

  @override
  int get sectionLimit => 6;

  @override
  Future<HomeSnapshot> load({required DateTime referenceLocal}) async {
    callCount++;
    lastReferenceLocal = referenceLocal;

    final pendingResult = this.pendingResult;

    if (pendingResult != null) {
      return pendingResult;
    }

    final error = this.error;

    if (error != null) {
      throw error;
    }

    return snapshot;
  }
}
