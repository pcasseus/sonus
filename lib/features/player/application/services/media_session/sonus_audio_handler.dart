import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart' as media;

import '../../../domain/models/playback_repeat_mode.dart';
import '../../../domain/models/playback_state.dart';
import '../../controllers/playback_coordinator.dart';
import 'media_session_state_mapper.dart';

typedef MediaSessionClock = DateTime Function();
typedef MediaSessionLogger = void Function(String message, {int level});
typedef ForegroundRelease = Future<void> Function();

/// Bridges Android's media session to Sonus's existing playback authority.
///
/// It owns no player, no queue and writes no analytics. Every command from
/// the notification, lock screen, Bluetooth or headset calls the same
/// [PlaybackCoordinator] the app uses, so listening history sees exactly
/// the state changes an in-app tap would produce.
///
/// The handler lives for the whole process (Android binds to it once),
/// while the coordinator is recreated whenever the app reloads after a
/// backup restore. [attach] and [detach] re-bind it safely.
class SonusAudioHandler extends media.BaseAudioHandler {
  SonusAudioHandler({
    this._artworkExists,
    MediaSessionClock? now,
    MediaSessionLogger? log,
    this._releaseForeground,
  }) : _now = now ?? DateTime.now,
       _log = log ?? _developerLog;

  /// A position change larger than this, compared with where the session
  /// expects playback to be, is treated as a seek and published at once.
  /// Ordinary progress is extrapolated by Android from the last update.
  static const Duration positionTolerance = Duration(milliseconds: 1500);

  final ArtworkExists? _artworkExists;
  final MediaSessionClock _now;
  final MediaSessionLogger _log;

  /// Takes the media service out of the foreground once a session ends.
  ///
  /// audio_service stops the service when the session goes idle, but the
  /// app's own connection to it keeps the service alive while an activity
  /// exists, and Android will not remove a foreground notification. See
  /// SonusForegroundRelease.kt.
  final ForegroundRelease? _releaseForeground;

  PlaybackCoordinator? _coordinator;
  StreamSubscription<PlaybackState>? _subscription;
  _Published? _published;

  /// The coordinator commands currently go to, if any.
  PlaybackCoordinator? get coordinator => _coordinator;

  /// Binds to [coordinator] and publishes its current state. Replaces any
  /// earlier binding.
  void attach(PlaybackCoordinator coordinator) {
    unawaited(_subscription?.cancel());
    _coordinator = coordinator;
    _subscription = coordinator.states.listen(_publish);
    // Publish everything for the new coordinator, while keeping what was
    // published before, so a playing session that a reload replaces with
    // an idle one still ends properly.
    _publishSnapshot(
      MediaSessionStateMapper.map(
        coordinator.currentState,
        now: _now(),
        artworkExists: _artworkExists,
      ),
      full: true,
    );
  }

  /// Unbinds from [coordinator] and clears the session. Does nothing if a
  /// newer coordinator has already attached: during a reload the new
  /// playback scope mounts before the old one is disposed.
  void detach(PlaybackCoordinator coordinator) {
    if (!identical(_coordinator, coordinator)) {
      return;
    }

    unawaited(_subscription?.cancel());
    _subscription = null;
    _coordinator = null;
    _publishSnapshot(
      MediaSessionStateMapper.map(const PlaybackState(), now: _now()),
    );
  }

  // Commands from Android. Each goes to the coordinator; failures are
  // already reflected in Sonus's playback state, so they are only logged.

  @override
  Future<void> play() => _run('play', (c) => c.play());

  @override
  Future<void> pause() => _run('pause', (c) => c.pause());

  @override
  Future<void> seek(Duration position) => _run('seek', (c) => c.seek(position));

  @override
  Future<void> skipToNext() => _run('skipToNext', (c) => c.skipNext());

  @override
  Future<void> skipToPrevious() =>
      _run('skipToPrevious', (c) => c.skipPrevious());

  @override
  Future<void> skipToQueueItem(int index) =>
      _run('skipToQueueItem', (c) => c.skipToIndex(index));

  @override
  Future<void> setShuffleMode(media.AudioServiceShuffleMode shuffleMode) =>
      _run(
        'setShuffleMode',
        (c) => c.setShuffleEnabled(
          shuffleMode != media.AudioServiceShuffleMode.none,
        ),
      );

  @override
  Future<void> setRepeatMode(media.AudioServiceRepeatMode repeatMode) => _run(
    'setRepeatMode',
    (c) => c.setRepeatMode(switch (repeatMode) {
      media.AudioServiceRepeatMode.none => PlaybackRepeatMode.off,
      media.AudioServiceRepeatMode.one => PlaybackRepeatMode.one,
      media.AudioServiceRepeatMode.all ||
      media.AudioServiceRepeatMode.group => PlaybackRepeatMode.all,
    }),
  );

  /// An explicit Stop ends playback (the queue is kept) and, because Sonus
  /// then reports idle, removes the notification and stops the service.
  ///
  /// The session is cleared here too, rather than through
  /// [media.BaseAudioHandler.stop], which assumes a state was already
  /// published.
  @override
  Future<void> stop() async {
    await _run('stop', (c) => c.stop());

    if (_published?.snapshot.state.processingState !=
        media.AudioProcessingState.idle) {
      _publishSnapshot(
        MediaSessionStateMapper.map(const PlaybackState(), now: _now()),
      );
    }
  }

  Future<void> _run(
    String command,
    Future<void> Function(PlaybackCoordinator coordinator) action,
  ) async {
    final coordinator = _coordinator;

    if (coordinator == null) {
      _log('Media command "$command" ignored: playback is not ready.');
      return;
    }

    try {
      await action(coordinator);
    } catch (error, stackTrace) {
      _log(
        'Media command "$command" failed. error=${error.runtimeType}\n'
        '$stackTrace',
        level: 900,
      );
    }
  }

  void _publish(PlaybackState state) {
    final now = _now();
    final snapshot = MediaSessionStateMapper.map(
      state,
      now: now,
      previousPlaying: _published?.snapshot.state.playing ?? false,
      artworkExists: _artworkExists,
    );
    final published = _published;

    if (published != null &&
        published.signature == _Signature.of(snapshot) &&
        !_positionJumped(published.snapshot.state, snapshot.state, now)) {
      return;
    }

    _publishSnapshot(snapshot);
  }

  void _publishSnapshot(MediaSessionSnapshot snapshot, {bool full = false}) {
    final previous = _published;
    _published = _Published(snapshot, _Signature.of(snapshot));

    final current = _published!.signature;

    // Only push what changed, so Android redraws as little as possible.
    // MediaItem equality only compares ids, so the item's own fields are
    // compared through the signature.
    if (full ||
        previous == null ||
        previous.signature.queueIds != current.queueIds) {
      queue.add(snapshot.queue);
    }
    if (full || previous == null || !previous.signature.sameItem(current)) {
      mediaItem.add(snapshot.item);
    }
    playbackState.add(snapshot.state);

    if (previous != null &&
        previous.signature.processingState != media.AudioProcessingState.idle &&
        current.processingState == media.AudioProcessingState.idle) {
      _releaseNotification();
    }
  }

  void _releaseNotification() {
    final release = _releaseForeground;

    if (release == null) {
      return;
    }

    unawaited(
      release().catchError((Object error, StackTrace stackTrace) {
        _log(
          'Playback notification could not be released. '
          'error=${error.runtimeType}\n$stackTrace',
          level: 900,
        );
      }),
    );
  }

  /// Whether [next]'s position differs from where [last] says playback
  /// should be by now.
  static bool _positionJumped(
    media.PlaybackState last,
    media.PlaybackState next,
    DateTime now,
  ) {
    final elapsed = last.playing
        ? now.difference(last.updateTime) * last.speed
        : Duration.zero;
    final expected = last.updatePosition + elapsed;
    return (next.updatePosition - expected).abs() > positionTolerance;
  }

  static void _developerLog(String message, {int level = 800}) {
    developer.log(message, name: 'sonus.media_session', level: level);
  }
}

class _Published {
  const _Published(this.snapshot, this.signature);

  final MediaSessionSnapshot snapshot;
  final _Signature signature;
}

/// Everything about a snapshot except its position, which is published
/// separately only when it jumps.
class _Signature {
  const _Signature({
    required this.processingState,
    required this.playing,
    required this.itemId,
    required this.title,
    required this.artist,
    required this.album,
    required this.artUri,
    required this.duration,
    required this.queueIds,
    required this.queueIndex,
    required this.repeatMode,
    required this.shuffleMode,
    required this.errorMessage,
  });

  factory _Signature.of(MediaSessionSnapshot snapshot) {
    final state = snapshot.state;
    final item = snapshot.item;

    return _Signature(
      processingState: state.processingState,
      playing: state.playing,
      itemId: item?.id,
      title: item?.title,
      artist: item?.artist,
      album: item?.album,
      artUri: item?.artUri,
      duration: item?.duration,
      queueIds: snapshot.queue.map((queued) => queued.id).join('\u0000'),
      queueIndex: state.queueIndex,
      repeatMode: state.repeatMode,
      shuffleMode: state.shuffleMode,
      errorMessage: state.errorMessage,
    );
  }

  /// Whether both describe the same media item, including its artwork and
  /// duration.
  bool sameItem(_Signature other) =>
      other.itemId == itemId &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.artUri == artUri &&
      other.duration == duration;

  final media.AudioProcessingState processingState;
  final bool playing;
  final String? itemId;
  final String? title;
  final String? artist;
  final String? album;
  final Uri? artUri;
  final Duration? duration;
  final String queueIds;
  final int? queueIndex;
  final media.AudioServiceRepeatMode repeatMode;
  final media.AudioServiceShuffleMode shuffleMode;
  final String? errorMessage;

  @override
  bool operator ==(Object other) =>
      other is _Signature &&
      other.processingState == processingState &&
      other.playing == playing &&
      sameItem(other) &&
      other.queueIds == queueIds &&
      other.queueIndex == queueIndex &&
      other.repeatMode == repeatMode &&
      other.shuffleMode == shuffleMode &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(
    processingState,
    playing,
    itemId,
    title,
    artist,
    album,
    artUri,
    duration,
    queueIds,
    queueIndex,
    repeatMode,
    shuffleMode,
    errorMessage,
  );
}
