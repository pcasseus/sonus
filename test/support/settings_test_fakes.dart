// Shared fakes for Settings tests: library summaries, account, playback
// modes, appearance and the app-info channel. Test-only.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/import/domain/entities/import_source.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/settings/application/controllers/appearance_controller.dart';
import 'package:sonus_next/features/settings/data/app_info_service.dart';
import 'package:sonus_next/features/settings/data/appearance_preferences_store.dart';

LibraryTrack settingsTrack(
  String id, {
  bool available = true,
  bool blocked = false,
}) {
  return LibraryTrack(
    songId: id,
    title: 'Song $id',
    artistId: 'artist-1',
    artistName: 'Artist',
    albumId: 'album-1',
    albumTitle: 'Album',
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 10, 1),
    isAvailable: available,
    isSongBlocked: blocked,
    filePath: available ? 'C:/Music/$id.mp3' : null,
  );
}

class FakeLibrary implements LibraryQueryRepository {
  FakeLibrary({
    required this.tracks,
    this.albumCount = 0,
    this.artistCount = 0,
  });

  final List<LibraryTrack> tracks;
  final int albumCount;
  final int artistCount;
  Completer<void>? gate;
  bool fail = false;
  int trackLoads = 0;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    trackLoads++;
    await gate?.future;
    if (fail) throw StateError('database unavailable');
    return tracks;
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async => [
    for (var i = 0; i < albumCount; i++)
      LibraryAlbum(
        albumId: 'album-$i',
        title: 'Album $i',
        artistId: 'artist-1',
        artistName: 'Artist',
        trackCount: 1,
        dateAdded: DateTime.utc(2026, 10, 1),
      ),
  ];

  @override
  Future<List<LibraryArtist>> getArtists() async => [
    for (var i = 0; i < artistCount; i++)
      LibraryArtist(
        artistId: 'artist-$i',
        name: 'Artist $i',
        albumCount: 1,
        songCount: 1,
        dateAdded: DateTime.utc(2026, 10, 1),
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeImports implements ImportWorkflowService {
  FakeImports({required this.sourceCount});

  final int sourceCount;

  @override
  Future<List<ImportSource>> getSources() async => [
    for (var i = 0; i < sourceCount; i++)
      ImportSource(
        id: 'source-$i',
        rootPath: 'content://music/$i',
        normalizedRootPath: 'content://music/$i',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReviews implements ImportReviewService {
  FakeReviews({required this.pending});

  int pending;

  @override
  Future<int> countUnresolved() async => pending;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsAccountRepository implements AccountRepository {
  FakeSettingsAccountRepository({this.currentUser});

  @override
  AccountUser? currentUser;

  final StreamController<AccountUser?> _auth =
      StreamController<AccountUser?>.broadcast();

  @override
  Stream<AccountUser?> watchAuthState() => _auth.stream;

  @override
  Future<AccountUser?> signInWithGoogle() async => currentUser;

  @override
  Future<void> signOut() async {
    currentUser = null;
  }
}

const settingsTestUser = AccountUser(
  id: 'user-1',
  email: 'person@example.com',
  displayName: 'Person Example',
  avatarUrl: null,
);

/// A playback engine that only models shuffle and repeat.
class FakeModeEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    _state = _state.copyWith(shuffleEnabled: enabled);
    _states.add(_state);
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    _state = _state.copyWith(repeatMode: mode);
    _states.add(_state);
  }

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An appearance controller over in-memory storage, already loaded.
Future<AppearanceController> loadedAppearanceController() async {
  final storage = <String, String>{};
  final controller = AppearanceController(
    store: AppearancePreferencesStore.forTesting(
      getString: (key) async => storage[key],
      setString: (key, value) async => storage[key] = value,
    ),
  );
  await controller.load();
  return controller;
}

/// Answers the app-info channel with [info], or fails like a missing
/// platform implementation when [info] is null.
void stubAppInfoChannel(WidgetTester tester, Map<String, Object?>? info) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel(AppInfoService.channelName),
    (call) async {
      if (info == null) throw MissingPluginException();
      return info;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(AppInfoService.channelName),
      null,
    ),
  );
}
