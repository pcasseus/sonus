import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/settings/application/controllers/library_overview_controller.dart';
import 'package:sonus_next/features/settings/application/services/library_overview_service.dart';

import '../../../../support/settings_test_fakes.dart';

void main() {
  group('LibraryOverviewService', () {
    test('summarises the library from the existing services', () async {
      final service = LibraryOverviewService(
        library: FakeLibrary(
          tracks: [
            settingsTrack('ok'),
            settingsTrack('missing', available: false),
            settingsTrack('blocked', blocked: true),
          ],
          albumCount: 2,
          artistCount: 4,
        ),
        imports: FakeImports(sourceCount: 3),
        reviews: FakeReviews(pending: 5),
      );

      final overview = await service.load();

      expect(overview.songCount, 3);
      expect(overview.albumCount, 2);
      expect(overview.artistCount, 4);
      expect(overview.unavailableSongs.map((t) => t.songId), ['missing']);
      expect(overview.blacklistedSongCount, 1);
      expect(overview.importSourceCount, 3);
      expect(overview.pendingReviewCount, 5);
    });

    test('import counts are unknown until imports are ready', () async {
      final overview = await LibraryOverviewService(
        library: FakeLibrary(tracks: const []),
      ).load();

      expect(overview.importSourceCount, isNull);
      expect(overview.pendingReviewCount, isNull);
    });
  });

  group('LibraryOverviewController', () {
    test('loads, reporting progress', () async {
      final controller = LibraryOverviewController(
        service: LibraryOverviewService(
          library: FakeLibrary(tracks: [settingsTrack('ok')]),
        ),
      );
      addTearDown(controller.dispose);

      final loading = controller.load();
      expect(controller.isLoading, isTrue);
      await loading;

      expect(controller.isLoading, isFalse);
      expect(controller.hasError, isFalse);
      expect(controller.overview!.songCount, 1);
    });

    test('a refresh during a load reuses the running load', () async {
      final library = FakeLibrary(tracks: const [])..gate = Completer<void>();
      final controller = LibraryOverviewController(
        service: LibraryOverviewService(library: library),
      );
      addTearDown(controller.dispose);

      final first = controller.load();
      final second = controller.load();
      library.gate!.complete();
      await Future.wait([first, second]);

      expect(library.trackLoads, 1);
    });

    test('a failure is reported and can be retried', () async {
      final library = FakeLibrary(tracks: const [])..fail = true;
      final controller = LibraryOverviewController(
        service: LibraryOverviewService(library: library),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.hasError, isTrue);
      expect(controller.overview, isNull);

      library.fail = false;
      await controller.load();
      expect(controller.hasError, isFalse);
      expect(controller.overview, isNotNull);
    });
  });
}
