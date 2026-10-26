import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart' as media;

import '../../../domain/models/playback_repeat_mode.dart';
import '../../../domain/models/playback_state.dart';
import '../../controllers/playback_coordinator.dart';
import 'media_browse_catalog.dart';
import 'media_session_state_mapper.dart';

typedef MediaSessionClock = DateTime Function();
typedef MediaSessionLogger = void Function(String message, {int level});
typedef ForegroundRelease = Future<void> Function();

/// Asks Flutter for a frame even while it has no screen.
typedef AppWakeUp = void Function();

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
    this._carArtworkUri,
    this._wakeApp,
    Duration? readinessTimeout,
  }) : _now = now ?? DateTime.now,
       _log = log ?? _developerLog,
       _readinessTimeout = readinessTimeout ?? const Duration(seconds: 10);

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

  /// Artwork URIs car hosts can open (see ArtworkContentUris).
  final CarArtworkUri? _carArtworkUri;

  /// Artwork URIs car hosts can open, for the browse catalog.
  CarArtworkUri? get carArtworkUri => _carArtworkUri;

  /// How long a car request waits for the app to finish starting. Android
  /// Auto can start Sonus with no screen, and its first requests may
  /// arrive before the library and player are ready.
  final Duration _readinessTimeout;

  /// Android Auto can start Sonus with no activity. Flutter then pauses
  /// frames, and the app's scopes, which finish loading through rebuilds,
  /// never finish. While a car request waits, frames are requested so
  /// startup completes. See [_awaitCatalog].
  final AppWakeUp? _wakeApp;

  /// How often frames are requested while a car request waits.
  static const Duration wakeInterval = Duration(milliseconds: 100);

  MediaBrowseCatalog? _catalog;
  Completer<void> _ready = Completer<void>();

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
    _completeReadiness();
    // Publish everything for the new coordinator, while keeping what was
    // published before, so a playing session that a reload replaces with
    // an idle one still ends properly.
    _publishSnapshot(
      MediaSessionStateMapper.map(
        coordinator.currentState,
        now: _now(),
        artworkExists: _artworkExists,
        carArtworkUri: _carArtworkUri,
      ),
      full: true,
    );
  }

  /// The browsable library the car sees. Replaces any earlier one.
  void attachCatalog(MediaBrowseCatalog catalog) {
    _catalog = catalog;
    _completeReadiness();
  }

  /// Removes [catalog] unless a newer one has already replaced it.
  void detachCatalog(MediaBrowseCatalog catalog) {
    if (identical(_catalog, catalog)) {
      _catalog = null;
    }
  }

  /// The catalog currently answering browse requests, if any.
  MediaBrowseCatalog? get catalog => _catalog;

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
    if (_ready.isCompleted) {
      _ready = Completer<void>();
    }
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

  // Browsing for Android Auto and other media browsers. Reads only.

  @override
  Future<List<media.MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    final catalog = await _awaitCatalog('getChildren');
    if (catalog == null) return const [];

    try {
      return await catalog.children(parentMediaId);
    } catch (error, stackTrace) {
      _log(
        'Browse request failed. error=${error.runtimeType}\n$stackTrace',
        level: 900,
      );
      return const [];
    }
  }

  @override
  Future<media.MediaItem?> getMediaItem(String mediaId) async {
    final catalog = await _awaitCatalog('getMediaItem');
    if (catalog == null) return null;

    try {
      return await catalog.item(mediaId);
    } catch (error, stackTrace) {
      _log(
        'Media item lookup failed. error=${error.runtimeType}\n$stackTrace',
        level: 900,
      );
      return null;
    }
  }

  @override
  Future<List<media.MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    final catalog = await _awaitCatalog('search');
    if (catalog == null) return const [];

    try {
      return await catalog.search(query);
    } catch (error, stackTrace) {
      _log(
        'Search failed. error=${error.runtimeType}\n$stackTrace',
        level: 900,
      );
      return const [];
    }
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) => _playBrowsed('playFromMediaId', mediaId, autoPlay: true);

  @override
  Future<void> prepareFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) => _playBrowsed('prepareFromMediaId', mediaId, autoPlay: false);

  @override
  Future<void> playMediaItem(media.MediaItem mediaItem) =>
      _playBrowsed('playMediaItem', mediaItem.id, autoPlay: true);

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) =>
      _playSearched('playFromSearch', query, extras, autoPlay: true);

  @override
  Future<void> prepareFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) => _playSearched('prepareFromSearch', query, extras, autoPlay: false);

  /// Android's keys for a structured voice request (MediaStore).
  static const String searchArtistKey = 'android.intent.extra.artist';
  static const String searchAlbumKey = 'android.intent.extra.album';

  Future<void> _playBrowsed(
    String command,
    String mediaId, {
    required bool autoPlay,
  }) async {
    final catalog = await _awaitCatalog(command);
    if (catalog == null) return;

    await _run(command, (coordinator) async {
      final queue = await catalog.queueFor(mediaId);

      if (queue == null) {
        _log('Media command "$command" ignored: the song is unavailable.');
        return;
      }

      await coordinator.playTracks(
        queue.tracks,
        startIndex: queue.startIndex,
        autoPlay: autoPlay,
      );
    });
  }

  Future<void> _playSearched(
    String command,
    String query,
    Map<String, dynamic>? extras, {
    required bool autoPlay,
  }) async {
    final catalog = await _awaitCatalog(command);
    if (catalog == null) return;

    await _run(command, (coordinator) async {
      final artist = extras?[searchArtistKey];
      final album = extras?[searchAlbumKey];
      final queue = await catalog.queueForSearch(
        query,
        artist: artist is String ? artist : null,
        album: album is String ? album : null,
      );

      if (queue == null) {
        _log('Media command "$command" found nothing to play.');
        return;
      }

      await coordinator.playTracks(
        queue.tracks,
        startIndex: queue.startIndex,
        autoPlay: autoPlay,
      );
    });
  }

  /// Waits, up to the readiness timeout, until both the library catalog
  /// and the player are attached.
  Future<MediaBrowseCatalog?> _awaitCatalog(String command) async {
    if (_catalog == null || _coordinator == null) {
      final wake = _wakeApp;
      final waking = wake == null
          ? null
          : Timer.periodic(wakeInterval, (_) => wake());
      wake?.call();

      try {
        await _ready.future.timeout(_readinessTimeout);
      } on TimeoutException {
        // Reported below.
      } finally {
        waking?.cancel();
      }
    }

    final catalog = _catalog;

    if (catalog == null) {
      _log('Media command "$command" ignored: the library is not ready.');
    }

    return catalog;
  }

  void _completeReadiness() {
    if (_catalog != null && _coordinator != null && !_ready.isCompleted) {
      _ready.complete();
    }
  }

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
      carArtworkUri: _carArtworkUri,
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
