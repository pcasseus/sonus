import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/state/dispose_safe_notifier.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/controllers/library_artists_controller.dart';
import 'package:sonus_next/features/library/presentation/controllers/library_tracks_controller.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/playlists/application/models/playlist_summary.dart';
import 'package:sonus_next/features/playlists/application/services/playlist_service.dart';
import 'package:sonus_next/features/playlists/presentation/controllers/playlists_controller.dart';

/// App Update 1.1 device acceptance: Library, Tracks and Playlists
/// controllers disposed while a load is in flight (their tab page left the
/// tree) no longer throw "used after being disposed" when it finishes.
class _Notifier extends ChangeNotifier with DisposeSafeNotifier {}

/// A library whose reads wait for [gate].
class _GatedLibrary implements LibraryQueryRepository {
  final Completer<void> gate = Completer<void>();

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    await gate.future;
    return const [];
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    await gate.future;
    return const [];
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    await gate.future;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Coordinator implements PlaybackCoordinator {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedPlaylists implements PlaylistService {
  final Completer<void> gate = Completer<void>();

  @override
  Future<List<PlaylistSummary>> getPlaylists() async {
    await gate.future;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('DisposeSafeNotifier', () {
    test('notifies listeners while alive', () {
      final notifier = _Notifier();
      var calls = 0;
      notifier
        ..addListener(() => calls++)
        ..notifyListeners();
      expect(calls, 1);
      expect(notifier.isDisposed, isFalse);
      notifier.dispose();
    });

    test('ignores a notification after dispose', () {
      final notifier = _Notifier()..dispose();
      expect(notifier.isDisposed, isTrue);
      expect(notifier.notifyListeners, returnsNormally);
    });

    test('a plain ChangeNotifier would assert (the device error)', () {
      final plain = ChangeNotifier()..dispose();
      expect(plain.notifyListeners, throwsFlutterError);
    });
  });

  group('controllers disposed during a load', () {
    test('LibraryTracksController', () async {
      final library = _GatedLibrary();
      final controller = LibraryTracksController(
        repository: library,
        playbackCoordinator: _Coordinator(),
      );
      final loading = controller.load();
      controller.dispose();
      library.gate.complete();
      await expectLater(loading, completes);
    });

    test('LibraryArtistsController', () async {
      final library = _GatedLibrary();
      final controller = LibraryArtistsController(repository: library);
      final loading = controller.load();
      controller.dispose();
      library.gate.complete();
      await expectLater(loading, completes);
    });

    test('PlaylistsController', () async {
      final service = _GatedPlaylists();
      final controller = PlaylistsController(service: service);
      final loading = controller.load();
      controller.dispose();
      service.gate.complete();
      await expectLater(loading, completes);
    });

    test('a controller still alive gets its data and notifies', () async {
      final library = _GatedLibrary();
      final controller = LibraryArtistsController(repository: library);
      var calls = 0;
      controller.addListener(() => calls++);
      final loading = controller.load();
      library.gate.complete();
      await loading;
      expect(controller.isLoading, isFalse);
      expect(calls, 2, reason: 'loading started, then finished');
      controller.dispose();
    });
  });
}
