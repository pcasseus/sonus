import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/controllers/playback_display_refresher.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';

import '../../data/engines/simulated_just_audio_player.dart';

LibraryTrack _track(
  String songId, {
  List<String> featuredArtists = const [],
  String? versionLabel,
  String editionTitle = 'Night Album',
  AlbumEditionType editionType = AlbumEditionType.standard,
}) {
  return LibraryTrack(
    songId: songId,
    title: 'Song $songId',
    artistId: 'artist_ada',
    artistName: 'Ada Vale',
    albumId: 'album_1',
    albumTitle: 'Night Album',
    albumEditionId: 'edition_1',
    albumEditionTitle: editionTitle,
    albumEditionType: editionType,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: featuredArtists,
    versionLabel: versionLabel,
    dateAdded: DateTime.utc(2026, 10, 1),
    isAvailable: true,
    filePath: 'C:/Music/$songId.mp3',
  );
}

void main() {
  late SimulatedJustAudioPlayer player;
  late JustAudioPlaybackEngine engine;
  late PlaybackCoordinator coordinator;
  late LibraryChangeSignal signal;
  late List<LibraryTrack> library;
  late int loads;
  late PlaybackDisplayRefresher refresher;

  setUp(() {
    player = SimulatedJustAudioPlayer();
    engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );
    coordinator = PlaybackCoordinator(engine: engine);
    signal = LibraryChangeSignal();
    library = [
      _track('a', featuredArtists: const ['Ben Moor']),
      _track('b'),
    ];
    loads = 0;
    refresher = PlaybackDisplayRefresher(
      coordinator: coordinator,
      loadTracks: () async {
        loads++;
        return library;
      },
      changes: signal,
      settle: Duration.zero,
    );
  });

  tearDown(() async {
    refresher.dispose();
    await engine.dispose();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  test('an edited queued song shows its new credit in place, without '
      'restarting playback (SN-50 BUG-01)', () async {
    await coordinator.playTracks(library, startIndex: 0);
    await settle();
    player.advanceTo(const Duration(seconds: 42));
    await settle();

    final before = coordinator.currentState;
    expect(before.queue.currentTrack!.displayArtist, 'Ada Vale Ft. Ben Moor');

    library = [
      _track('a', featuredArtists: const ['Cy Lark'], versionLabel: 'Live'),
      _track('b', featuredArtists: const ['Dee Rune']),
    ];
    signal.notify(LibraryChangeKind.libraryEdited);
    await settle();

    final after = coordinator.currentState;
    final current = after.queue.currentTrack!;

    expect(current.displayArtist, 'Ada Vale Ft. Cy Lark');
    expect(current.displayTitle, 'Song a (Live)');
    expect(current.title, 'Song a');
    expect(current.artistName, 'Ada Vale');
    expect(after.queue.trackAt(1)!.displayArtist, 'Ada Vale Ft. Dee Rune');
    expect(after.queue.currentIndex, before.queue.currentIndex);
    expect(after.position, const Duration(seconds: 42));
    expect(after.status, PlaybackStatus.playing);
    expect(after.transitionCause, before.transitionCause);
  });

  test('a renamed Other edition shows its new name while playing, without '
      'changing what history records (SN-50 BUG-03)', () async {
    library = [
      _track(
        'a',
        editionTitle: 'Night Album (Remixes)',
        editionType: AlbumEditionType.other,
      ),
    ];
    await coordinator.playTracks(library, startIndex: 0);
    await settle();
    player.advanceTo(const Duration(seconds: 12));
    await settle();

    expect(
      coordinator.currentState.queue.currentTrack!.displayAlbum,
      'Night Album (Remixes)',
    );

    library = [
      _track(
        'a',
        editionTitle: 'Night Album (Club Mixes)',
        editionType: AlbumEditionType.other,
      ),
    ];
    signal.notify(LibraryChangeKind.libraryEdited);
    await settle();

    final after = coordinator.currentState;
    final current = after.queue.currentTrack!;
    expect(current.displayAlbum, 'Night Album (Club Mixes)');
    // History fields keep what playback started with.
    expect(current.albumTitle, 'Night Album');
    expect(current.albumEditionTitle, 'Night Album (Remixes)');
    expect(after.position, const Duration(seconds: 12));
    expect(after.status, PlaybackStatus.playing);
  });

  test('listening changes and an empty queue read nothing', () async {
    signal.notify(LibraryChangeKind.libraryEdited);
    await settle();
    expect(loads, 0);

    await coordinator.playTracks(library);
    await settle();
    signal.notify(LibraryChangeKind.listeningRecorded);
    await settle();
    expect(loads, 0);
  });

  test('an unchanged song leaves the playback state alone', () async {
    await coordinator.playTracks(library);
    await settle();

    expect(coordinator.refreshTrackDisplay(library), isFalse);
  });

  test('a failed read is logged and leaves the queue as it was', () async {
    final failing = PlaybackDisplayRefresher(
      coordinator: coordinator,
      loadTracks: () async => throw StateError('database closed'),
      changes: signal,
      settle: Duration.zero,
    );
    addTearDown(failing.dispose);

    await coordinator.playTracks(library);
    await settle();
    await failing.refresh();

    expect(
      coordinator.currentState.queue.currentTrack!.displayArtist,
      'Ada Vale Ft. Ben Moor',
    );
  });
}
