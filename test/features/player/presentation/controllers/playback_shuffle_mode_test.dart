// App Update 1.2 patches, Checkpoint 2 (BUG-06): a page's Shuffle control
// is the player's shuffle mode, wherever it was last changed.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_shuffle_mode.dart';

import '../../data/engines/simulated_just_audio_player.dart';

class _Page extends ChangeNotifier with PlaybackShuffleMode {
  _Page(this.shufflePlayback) {
    watchPlaybackShuffle();
    // As its page does.
    addListener(_heard);
  }

  static void _heard() {}

  @override
  final PlaybackCoordinator? shufflePlayback;

  int notifications = 0;

  @override
  void notifyListeners() {
    notifications++;
    super.notifyListeners();
  }
}

PlaybackTrack _track(String id) => PlaybackTrack(
  songId: id,
  title: 'Song $id',
  artistId: 'artist',
  artistName: 'Artist',
  albumId: 'album',
  albumTitle: 'Album',
  filePath: '/music/$id.mp3',
  duration: const Duration(minutes: 3),
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late JustAudioPlaybackEngine engine;
  late PlaybackCoordinator playback;

  setUp(() async {
    engine = JustAudioPlaybackEngine(
      audioPlayer: SimulatedJustAudioPlayer(modelShuffle: true),
      configureAudioSession: () async {},
    );
    playback = PlaybackCoordinator(engine: engine);
    await engine.loadQueue([
      for (var i = 0; i < 6; i++) _track('s$i'),
    ], autoPlay: true);
    await _settle();
  });

  tearDown(() => engine.dispose());

  test('a page opened while shuffle is on shows it on', () async {
    await playback.setShuffleEnabled(true);

    final page = _Page(playback);
    addTearDown(page.dispose);

    expect(page.isShuffleEnabled, isTrue);
  });

  test('shuffle changed elsewhere reaches an open page', () async {
    final page = _Page(playback);
    addTearDown(page.dispose);
    expect(page.isShuffleEnabled, isFalse);

    await playback.setShuffleEnabled(true);
    await _settle();
    expect(page.isShuffleEnabled, isTrue);
    expect(page.notifications, 1);

    await playback.setShuffleEnabled(false);
    await _settle();
    expect(page.isShuffleEnabled, isFalse);
    expect(page.notifications, 2);
  });

  test('a page acts on the current mode: turning on a shuffle that is '
      'already on keeps the cycle, and the toggle turns it off', () async {
    final page = _Page(playback);
    addTearDown(page.dispose);

    // Turned on from Now Playing; two songs play.
    await playback.setShuffleEnabled(true);
    await playback.skipNext();
    await playback.skipNext();
    await _settle();
    final order = playback.shuffleOrder;

    await page.setShuffleEnabled(true);
    await _settle();
    expect(playback.shuffleOrder, order);

    await page.toggleShuffle();
    await _settle();
    expect(playback.currentState.shuffleEnabled, isFalse);
    expect(page.isShuffleEnabled, isFalse);
  });

  test(
    'a page without a player shows shuffle off and ignores changes',
    () async {
      final page = _Page(null);
      addTearDown(page.dispose);

      await page.setShuffleEnabled(true);

      expect(page.isShuffleEnabled, isFalse);
      expect(page.notifications, 0);
    },
  );

  test('a closed page is not notified', () async {
    final page = _Page(playback);
    page.dispose();

    await playback.setShuffleEnabled(true);
    await _settle();

    expect(page.notifications, 0);
  });
}
