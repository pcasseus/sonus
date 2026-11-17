import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart' as media;

import '../../../../library/application/models/library_track.dart';
import '../../../domain/models/playback_repeat_mode.dart';
import '../../../domain/models/playback_state.dart';
import '../../controllers/playback_coordinator.dart';
import 'media_browse_catalog.dart';
import 'media_session_state_mapper.dart';
import 'voice_request_resolver.dart';

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

  /// Media ID prefix of the saved session's current song, the item offered
  /// to Android's resume card. Playing it resumes that session (D-Q9).
  static const String resumePrefix = 'sonus.resume:';

  MediaBrowseCatalog? _catalog;
  Completer<void> _ready = Completer<void>();
  Completer<void> _attached = Completer<void>();

  PlaybackCoordinator? _coordinator;
  Future<void>? _restored;
  StreamSubscription<PlaybackState>? _subscription;
  _Published? _published;

  /// The coordinator commands currently go to, if any.
  PlaybackCoordinator? get coordinator => _coordinator;

  /// Binds to [coordinator] and publishes its current state. Replaces any
  /// earlier binding.
  ///
  /// [restored] completes once the saved queue has been restored (or there
  /// was none). Play and the resume card wait for it while the queue is
  /// empty, so a Bluetooth Play that starts Sonus resumes the saved queue
  /// and position instead of doing nothing (D-Q8).
  void attach(PlaybackCoordinator coordinator, {Future<void>? restored}) {
    unawaited(_subscription?.cancel());
    _coordinator = coordinator;
    _restored = restored;
    _subscription = coordinator.states.listen(_publish);
    if (!_attached.isCompleted) {
      _attached.complete();
    }
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
    _restored = null;
    _failure = null;
    _setQueueTitle(null, const []);
    if (_ready.isCompleted) {
      _ready = Completer<void>();
    }
    if (_attached.isCompleted) {
      _attached = Completer<void>();
    }
    _publishSnapshot(
      MediaSessionStateMapper.map(const PlaybackState(), now: _now()),
    );
  }

  // Commands from Android. Each goes to the coordinator; failures are
  // already reflected in Sonus's playback state, so they are only logged.

  /// Play from the notification, lock screen, a Bluetooth device or a car.
  /// If Sonus was started just for it, the saved queue is restored first.
  @override
  Future<void> play() async {
    final restoredInTime = await _awaitSavedSession();
    await _run('play', (c) => c.play());
    if (!restoredInTime) _playOnceRestored();
  }

  /// A Play that came while the saved session was still being restored,
  /// past the readiness timeout, found nothing queued and did nothing; the
  /// restore then loads the queue paused. The Play is applied once the
  /// queue is there, unless the listener paused or stopped since, or
  /// something already plays (BUG-11 hardening).
  void _playOnceRestored() {
    final restored = _restored;
    if (restored == null) return;
    final asked = _stopOrPauseCount;
    unawaited(
      restored.then<void>((_) async {
        final state = _coordinator?.currentState;
        if (_stopOrPauseCount != asked ||
            state == null ||
            !state.queue.hasCurrentTrack ||
            state.isPlaying) {
          return;
        }
        _log('Play applied once the saved session was restored.');
        await _run('play', (c) => c.play());
      }, onError: (Object _) {}),
    );
  }

  /// Pause and Stop requests so far; a Play waiting for a slow restore is
  /// dropped when one came after it.
  int _stopOrPauseCount = 0;

  @override
  Future<void> pause() {
    _stopOrPauseCount++;
    return _run('pause', (c) => c.pause());
  }

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
      _runInTurn(
        'setShuffleMode',
        (c) => c.setShuffleEnabled(
          shuffleMode != media.AudioServiceShuffleMode.none,
        ),
      );

  @override
  Future<void> setRepeatMode(media.AudioServiceRepeatMode repeatMode) =>
      _runInTurn(
        'setRepeatMode',
        (c) => c.setRepeatMode(switch (repeatMode) {
          media.AudioServiceRepeatMode.none => PlaybackRepeatMode.off,
          media.AudioServiceRepeatMode.one => PlaybackRepeatMode.one,
          media.AudioServiceRepeatMode.all ||
          media.AudioServiceRepeatMode.group => PlaybackRepeatMode.all,
        }),
      );

  /// Shuffle and Repeat from the system player (D-Q1/D-Q12). They go
  /// through the coordinator like the app's own buttons, so a remembered
  /// mode is saved the same way (D-Q13).
  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case MediaSessionStateMapper.shuffleAction:
        await _runInTurn(
          'shuffle',
          (c) => c.setShuffleEnabled(!c.currentState.shuffleEnabled),
        );
      case MediaSessionStateMapper.repeatAction:
        await _runInTurn(
          'repeat',
          (c) => c.setRepeatMode(c.currentState.repeatMode.next),
        );
      default:
        _log('Media command "$name" ignored: unknown custom action.');
    }
  }

  /// The listener dismissed the notification, where Android allows it.
  /// Like End session, the session ends but the queue and position stay,
  /// so Play resumes later (D-Q5/D-Q6). Only the mini-player's paused
  /// swipe clears the queue (D-Q7).
  @override
  Future<void> onNotificationDeleted() => stop();

  /// Swiping Sonus out of Recents changes nothing: music keeps playing, or
  /// stays paused with its notification (D-Q10).
  @override
  Future<void> onTaskRemoved() async {}

  // Browsing for Android Auto and other media browsers. Reads only.

  @override
  Future<List<media.MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    final catalog = await _awaitCatalog('getChildren');
    if (catalog == null) return const [];

    if (parentMediaId == media.AudioService.recentRootId) {
      final resume = await _resumeItem();
      if (resume != null) return [resume];
    }

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
  ]) => _playOrResume('playFromMediaId', mediaId, autoPlay: true);

  @override
  Future<void> prepareFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) => _playOrResume('prepareFromMediaId', mediaId, autoPlay: false);

  @override
  Future<void> playMediaItem(media.MediaItem mediaItem) =>
      _playOrResume('playMediaItem', mediaItem.id, autoPlay: true);

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) =>
      _playSearched('playFromSearch', query, extras, autoPlay: true);

  @override
  Future<void> prepareFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) => _playSearched('prepareFromSearch', query, extras, autoPlay: false);

  /// "Add to queue" from a media controller. Android Auto and the
  /// Assistant do not send it; other controllers may, for a song they
  /// browsed or a queue item. It is added as the app's Add to queue adds it.
  @override
  Future<void> addQueueItem(media.MediaItem mediaItem) => _queueSong(
    'addQueueItem',
    mediaItem.id,
    (coordinator, track) => coordinator.addToQueue(track),
  );

  /// An insert right after the current song is the app's Play next; one at
  /// the end is Add to queue. Sonus has no other insert, so any other
  /// position is refused.
  @override
  Future<void> insertQueueItem(int index, media.MediaItem mediaItem) {
    final current = _coordinator?.currentState.queue;
    final hasCurrent = current != null && current.hasCurrentTrack;

    if (!hasCurrent || index == current.currentIndex + 1) {
      return _queueSong(
        'insertQueueItem',
        mediaItem.id,
        (coordinator, track) => coordinator.playNext(track),
      );
    }

    if (index >= current.tracks.length) {
      return addQueueItem(mediaItem);
    }

    _log('Media command "insertQueueItem" ignored: only Play next is offered.');
    return Future<void>.value();
  }

  /// Error codes for a voice request that fails, as PlaybackStateCompat
  /// defines them. Android Auto shows the message and the Assistant says it.
  /// Nothing matched is not a fault in Sonus; still starting and a library
  /// that cannot be read are.
  static const int notFoundErrorCode = 0; // ERROR_CODE_UNKNOWN_ERROR
  static const int notReadyErrorCode = 1; // ERROR_CODE_APP_ERROR
  static const int libraryUnreadableErrorCode = 1; // ERROR_CODE_APP_ERROR

  /// The library is still loading.
  static const String notReadyMessage =
      'Sonus is still starting. Try again in a moment.';

  /// The library could not be read, so Sonus cannot tell whether the music
  /// asked for is there.
  static const String libraryUnreadableMessage =
      'Sonus couldn\'t access your music library.';

  /// Nothing in the library can be played.
  static const String nothingToPlayMessage = 'Sonus has nothing to play yet.';

  /// The music asked for is not in the library, quoting the request.
  static String notFoundMessage(String spoken) =>
      spoken.isEmpty ? nothingToPlayMessage : 'Sonus couldn\'t find "$spoken".';

  /// What the car says for [notFound].
  static String voiceFailureMessage(VoiceNotFound notFound) =>
      notFound.reason == VoiceNotFoundReason.nothingToPlay
      ? nothingToPlayMessage
      : notFoundMessage(notFound.spoken);

  /// The saved session's current song, as the item Android's resume card
  /// shows, or null when nothing is saved.
  Future<media.MediaItem?> _resumeItem() async {
    await _awaitSavedSession();
    final track = _coordinator?.currentState.queue.currentTrack;
    if (track == null) return null;

    return MediaSessionStateMapper.queueItemFor(
      track,
      carArtworkUri: _carArtworkUri,
    ).copyWith(id: '$resumePrefix${track.songId}');
  }

  Future<void> _playOrResume(
    String command,
    String mediaId, {
    required bool autoPlay,
  }) async {
    if (!mediaId.startsWith(resumePrefix)) {
      return _playBrowsed(command, mediaId, autoPlay: autoPlay);
    }

    // The resume card resumes the saved queue and position. Only when no
    // session is left does it fall back to that song in Recent.
    await _awaitSavedSession();
    if (_coordinator?.currentState.queue.hasCurrentTrack ?? false) {
      if (autoPlay) await _run(command, (c) => c.play());
      return;
    }

    final songId = mediaId.substring(resumePrefix.length);
    await _playBrowsed(
      command,
      MediaBrowsePlayableId(MediaBrowseContainer.recent, songId).mediaId,
      autoPlay: autoPlay,
    );
  }

  Future<void> _playBrowsed(
    String command,
    String mediaId, {
    required bool autoPlay,
  }) async {
    final catalog = await _awaitCatalog(command);
    if (catalog == null) return;

    final MediaBrowseQueue? queue;
    try {
      queue = await catalog.queueFor(mediaId);
    } catch (error, stackTrace) {
      _log(
        'Media command "$command" failed. error=${error.runtimeType}\n'
        '$stackTrace',
        level: 900,
      );
      return;
    }

    if (queue == null) {
      _log('Media command "$command" ignored: the song is unavailable.');
      return;
    }

    await _playQueue(command, queue, autoPlay: autoPlay);
  }

  /// Voice requests so far. Only the newest one plays, so a quick repeat
  /// never lets an older, slower lookup replace what was asked last.
  int _voiceRequests = 0;

  /// A spoken request. When nothing matches, Sonus is not ready, or the
  /// library cannot be read, an error is published for the car or
  /// Assistant to say, and whatever was playing carries on.
  Future<void> _playSearched(
    String command,
    String query,
    Map<String, dynamic>? extras, {
    required bool autoPlay,
  }) async {
    final request = VoiceRequest.fromSearch(query, extras);
    final turn = ++_voiceRequests;
    bool isLatest() => turn == _voiceRequests;

    final catalog = await _awaitCatalog(command);
    if (catalog == null || _coordinator == null) {
      if (catalog != null) {
        _log('Media command "$command" ignored: playback is not ready.');
      }
      if (isLatest()) _reportFailure(notReadyErrorCode, notReadyMessage);
      return;
    }

    final VoiceResolution resolution;
    try {
      resolution = await catalog.resolveVoiceRequest(request);
    } catch (error, stackTrace) {
      _log(
        'Media command "$command" failed. error=${error.runtimeType}\n'
        '$stackTrace',
        level: 900,
      );
      if (isLatest()) {
        _reportFailure(libraryUnreadableErrorCode, libraryUnreadableMessage);
      }
      return;
    }

    if (!isLatest()) {
      _log('Media command "$command" replaced by a newer request.');
      return;
    }

    switch (resolution) {
      case VoiceNotFound(:final reason):
        _log(
          'Media command "$command" found nothing to play. '
          'reason=${reason.name}',
        );
        _reportFailure(notFoundErrorCode, voiceFailureMessage(resolution));
      case VoiceResolved():
        if (resolution is VoiceAmbiguous) {
          _log('Media command "$command" was ambiguous; the best match plays.');
        }
        await _playQueue(command, resolution, autoPlay: autoPlay);
    }
  }

  /// Plays [queue] as the app would, then names it for the car.
  Future<void> _playQueue(
    String command,
    MediaBrowseQueue queue, {
    required bool autoPlay,
  }) async {
    final played = await _run(
      command,
      (coordinator) => coordinator.playTracks(
        queue.tracks,
        startIndex: queue.startIndex,
        autoPlay: autoPlay,
      ),
    );
    if (played) _setQueueTitle(queue.title, queue.tracks);
  }

  /// Adds the song [mediaId] names to the queue with [action].
  Future<void> _queueSong(
    String command,
    String mediaId,
    Future<void> Function(PlaybackCoordinator coordinator, LibraryTrack track)
    action,
  ) async {
    final catalog = await _awaitCatalog(command);
    if (catalog == null) return;

    final LibraryTrack? track;
    try {
      track = await catalog.track(mediaId);
    } catch (error, stackTrace) {
      _log(
        'Media command "$command" failed. error=${error.runtimeType}\n'
        '$stackTrace',
        level: 900,
      );
      return;
    }

    if (track == null) {
      _log('Media command "$command" ignored: the song is unavailable.');
      return;
    }

    await _run(command, (coordinator) => action(coordinator, track!));
  }

  /// Waits, up to the readiness timeout, until both the library catalog
  /// and the player are attached.
  Future<MediaBrowseCatalog?> _awaitCatalog(String command) async {
    if (_catalog == null || _coordinator == null) {
      // A timeout is reported below.
      await _waitWhileWaking(_ready.future);
    }

    final catalog = _catalog;

    if (catalog == null) {
      _log('Media command "$command" ignored: the library is not ready.');
    }

    return catalog;
  }

  /// Waits, up to the readiness timeout, for the player and, while its
  /// queue is empty, for the saved session to be restored.
  /// False when the saved session was still being restored at the
  /// readiness timeout.
  Future<bool> _awaitSavedSession() async {
    if (_coordinator == null) {
      await _waitWhileWaking(_attached.future);
    }

    final restored = _restored;
    final coordinator = _coordinator;

    if (restored == null ||
        coordinator == null ||
        coordinator.currentState.queue.isNotEmpty) {
      return true;
    }

    if (!await _waitWhileWaking(restored)) {
      _log('The saved session was not restored in time.', level: 900);
      return false;
    }
    return true;
  }

  /// Waits up to the readiness timeout for [future], requesting frames
  /// meanwhile so the app can finish starting. False on a timeout.
  Future<bool> _waitWhileWaking(Future<void> future) async {
    final wake = _wakeApp;
    final waking = wake == null
        ? null
        : Timer.periodic(wakeInterval, (_) => wake());
    wake?.call();

    try {
      await future.timeout(_readinessTimeout);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      waking?.cancel();
    }
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
    _stopOrPauseCount++;
    await _run('stop', (c) => c.stop());

    if (_published?.snapshot.state.processingState !=
        media.AudioProcessingState.idle) {
      _publishSnapshot(
        MediaSessionStateMapper.map(const PlaybackState(), now: _now()),
      );
    }
  }

  /// Shuffle and Repeat commands, one at a time: each reads the mode the
  /// one before it set, so a quick double tap toggles twice.
  Future<void> _modeCommands = Future<void>.value();

  Future<void> _runInTurn(
    String command,
    Future<void> Function(PlaybackCoordinator coordinator) action,
  ) {
    final turn = _modeCommands.then((_) => _run(command, action));
    _modeCommands = turn;
    return turn;
  }

  /// Runs [action] on the coordinator. True when it succeeded, which also
  /// clears a failed voice request's error.
  Future<bool> _run(
    String command,
    Future<void> Function(PlaybackCoordinator coordinator) action,
  ) async {
    final coordinator = _coordinator;

    if (coordinator == null) {
      _log('Media command "$command" ignored: playback is not ready.');
      return false;
    }

    try {
      await action(coordinator);
    } catch (error, stackTrace) {
      _log(
        'Media command "$command" failed. error=${error.runtimeType}\n'
        '$stackTrace',
        level: 900,
      );
      return false;
    }

    _clearFailure();
    return true;
  }

  /// A failed voice request's error, shown until the next successful
  /// command or until another song or queue is published.
  ({int code, String message})? _failure;

  /// Publishes a voice request's failure without touching playback.
  ///
  /// While something is queued the error is non-fatal: the state Android
  /// sees keeps playing or paused, with the error code and message added,
  /// which Android Auto shows as a message over the player. With nothing
  /// queued the session reports STATE_ERROR, which the car shows in place
  /// of the player and the Assistant reads out.
  void _reportFailure(int code, String message) {
    _failure = (code: code, message: message);
    _publishSnapshot(
      _published?.snapshot ??
          MediaSessionStateMapper.map(const PlaybackState(), now: _now()),
    );
  }

  void _clearFailure() {
    if (_failure == null) return;
    _failure = null;
    final published = _published;
    if (published != null) _publishSnapshot(published.snapshot);
  }

  /// [snapshot] with the current failure, if any, added.
  MediaSessionSnapshot _withFailure(MediaSessionSnapshot snapshot) {
    final failure = _failure;
    if (failure == null) return snapshot;

    final state = snapshot.state;
    return MediaSessionSnapshot(
      item: snapshot.item,
      queue: snapshot.queue,
      state: media.PlaybackState(
        processingState:
            state.processingState == media.AudioProcessingState.idle
            ? media.AudioProcessingState.error
            : state.processingState,
        playing: state.playing,
        controls: state.controls,
        androidCompactActionIndices: state.androidCompactActionIndices,
        systemActions: state.systemActions,
        updatePosition: state.updatePosition,
        bufferedPosition: state.bufferedPosition,
        speed: state.speed,
        updateTime: state.updateTime,
        errorCode: failure.code,
        errorMessage: failure.message,
        repeatMode: state.repeatMode,
        shuffleMode: state.shuffleMode,
        captioningEnabled: state.captioningEnabled,
        queueIndex: state.queueIndex,
      ),
    );
  }

  /// Songs of the queue [queueTitle] names, so the title is dropped once
  /// the queue is replaced. Adding songs keeps it.
  List<String>? _titledSongIds;

  void _setQueueTitle(String? title, List<LibraryTrack> tracks) {
    _titledSongIds = title == null
        ? null
        : [
            for (final track in tracks)
              if (PlaybackCoordinator.isPlayable(track)) track.songId,
          ];
    if (queueTitle.value != (title ?? '')) queueTitle.add(title ?? '');
  }

  /// Drops the queue title when [queue] no longer holds the titled songs.
  /// An empty queue (a stopped session) keeps it, for a later resume.
  void _checkQueueTitle(List<media.MediaItem> queue) {
    final titled = _titledSongIds;
    if (titled == null || queue.isEmpty) return;

    final remaining = <String, int>{};
    for (final item in queue) {
      remaining[item.id] = (remaining[item.id] ?? 0) + 1;
    }
    for (final id in titled) {
      final left = remaining[id] ?? 0;
      if (left == 0) {
        _setQueueTitle(null, const []);
        return;
      }
      remaining[id] = left - 1;
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
        published.signature == _Signature.of(_withFailure(snapshot)) &&
        !_positionJumped(published.snapshot.state, snapshot.state, now)) {
      return;
    }

    _publishSnapshot(snapshot);
  }

  /// Publishes [snapshot], Sonus's own state; [_published] keeps it as it
  /// is, and the signature describes what Android was sent.
  void _publishSnapshot(MediaSessionSnapshot snapshot, {bool full = false}) {
    final previous = _published;

    // A different song or queue means the listener moved on.
    if (_failure != null &&
        previous != null &&
        (previous.snapshot.item?.id != snapshot.item?.id ||
            _Signature.of(previous.snapshot).queueRows !=
                _Signature.of(snapshot).queueRows)) {
      _failure = null;
    }

    final sent = _withFailure(snapshot);
    _published = _Published(snapshot, _Signature.of(sent));

    final current = _published!.signature;

    // Only push what changed, so Android redraws as little as possible.
    // MediaItem equality only compares ids, so the item's own fields are
    // compared through the signature.
    if (full ||
        previous == null ||
        previous.signature.queueRows != current.queueRows) {
      _checkQueueTitle(snapshot.queue);
      queue.add(snapshot.queue);
    }
    if (full || previous == null || !previous.signature.sameItem(current)) {
      mediaItem.add(snapshot.item);
    }
    playbackState.add(sent.state);

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
    required this.queueRows,
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
      // Ids with the shown title and credit line, so a queued song edited
      // in Track Studio is redrawn in the car's queue too (SN-50 BUG-01).
      queueRows: snapshot.queue
          .map(
            (queued) =>
                '${queued.id}\u0001${queued.title}\u0001${queued.artist}',
          )
          .join('\u0000'),
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
  final String queueRows;
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
      other.queueRows == queueRows &&
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
    queueRows,
    queueIndex,
    repeatMode,
    shuffleMode,
    errorMessage,
  );
}
