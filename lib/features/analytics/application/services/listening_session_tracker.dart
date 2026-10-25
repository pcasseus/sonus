// ignore_for_file: prefer_initializing_formals

import '../../../../core/database/library_mutation_coordinator.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../../../core/identity/entity_id.dart';
import '../../domain/entities/playback_listening_segment.dart';
import '../../domain/entities/playback_session.dart';
import '../../domain/entities/qualified_play.dart';
import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/qualified_play_repository.dart';
import 'listening_qualification_policy.dart';
import 'listening_session_mutation_runner.dart';
import 'listening_session_start.dart';

typedef AnalyticsNow = DateTime Function();
typedef AnalyticsIdGenerator = String Function();

class ListeningSessionTracker {
  ListeningSessionTracker({
    required PlaybackSessionRepository playbackSessions,
    required QualifiedPlayRepository qualifiedPlays,
    required PlaybackListeningSegmentRepository listeningSegments,
    required ListeningSessionMutationRunner mutationRunner,
    ListeningQualificationPolicy qualificationPolicy =
        const ListeningQualificationPolicy(),
    AnalyticsNow? now,
    AnalyticsIdGenerator? playbackSessionIdGenerator,
    AnalyticsIdGenerator? listeningSegmentIdGenerator,
    AnalyticsIdGenerator? qualifiedPlayIdGenerator,
  }) : _playbackSessions = playbackSessions,
       _qualifiedPlays = qualifiedPlays,
       _listeningSegments = listeningSegments,
       _mutationRunner = mutationRunner,
       _qualificationPolicy = qualificationPolicy,
       _now = now ?? DateTime.now,
       _playbackSessionIdGenerator =
           playbackSessionIdGenerator ?? EntityId.playbackSession,
       _listeningSegmentIdGenerator =
           listeningSegmentIdGenerator ?? EntityId.listeningSegment,
       _qualifiedPlayIdGenerator =
           qualifiedPlayIdGenerator ?? EntityId.qualifiedPlay;

  final PlaybackSessionRepository _playbackSessions;
  final QualifiedPlayRepository _qualifiedPlays;
  final PlaybackListeningSegmentRepository _listeningSegments;
  final ListeningSessionMutationRunner _mutationRunner;
  final ListeningQualificationPolicy _qualificationPolicy;

  final AnalyticsNow _now;
  final AnalyticsIdGenerator _playbackSessionIdGenerator;
  final AnalyticsIdGenerator _listeningSegmentIdGenerator;
  final AnalyticsIdGenerator _qualifiedPlayIdGenerator;

  PlaybackSession? _session;
  PlaybackListeningSegment? _listeningSegment;
  DateTime? _playingSince;
  bool _hasQualified = false;

  PlaybackSession? get currentSession => _session;

  PlaybackListeningSegment? get currentListeningSegment => _listeningSegment;

  bool get hasActiveSession => _session != null;

  bool get isPlaying => _playingSince != null;

  bool get hasQualified => _hasQualified;

  /// Forgets the in-memory session without writing anything.
  ///
  /// Rows already committed stay as they are; a session left open in the
  /// database is closed by startup recovery.
  void abandon() {
    _session = null;
    _listeningSegment = null;
    _playingSince = null;
    _hasQualified = false;
  }

  /// A restore that refuses a write may replace the library before this
  /// tracker runs again, so its in-memory state must never be written later.
  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } on LibraryMutationUnavailable {
      abandon();
      rethrow;
    }
  }

  Future<void> attachCurrentSessionToUser(String userId) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    final current = _session;

    if (current == null) {
      return;
    }

    final currentOwner = current.userId;

    if (currentOwner != null && currentOwner != normalizedUserId) {
      throw StateError(
        'Active playback session ${current.id} belongs to a different user.',
      );
    }

    final existingPlay = await _qualifiedPlays.getByPlaybackSessionId(
      current.id,
    );

    final playOwner = existingPlay?.userId;

    if (playOwner != null && playOwner != normalizedUserId) {
      throw StateError(
        'Qualified play ${existingPlay!.id} belongs to a different user.',
      );
    }

    if (existingPlay != null && existingPlay.userId == null) {
      await _write(
        () => _qualifiedPlays.save(
          existingPlay.copyWith(userId: normalizedUserId),
        ),
      );
    }

    if (currentOwner == null) {
      final attached = current.copyWith(userId: normalizedUserId);

      await _write(() => _playbackSessions.save(attached));

      _session = attached;
    }
  }

  Future<PlaybackSession> start(
    ListeningSessionStart start, {
    Duration initialPosition = Duration.zero,
    bool playing = false,
  }) async {
    if (_session != null) {
      throw StateError(
        'Cannot start a listening session while another session is active.',
      );
    }

    final now = _utcNow();

    final session = PlaybackSession(
      id: _playbackSessionIdGenerator(),
      userId: start.userId,
      songId: start.songId,
      artistId: start.artistId,
      albumId: start.albumId,
      albumEditionId: start.albumEditionId,
      songTitle: start.songTitle,
      artistName: start.artistName,
      albumTitle: start.albumTitle,
      albumEditionTitle: start.albumEditionTitle,
      startedAt: now,
      listenedDuration: Duration.zero,
      trackDuration: start.trackDuration,
      finalPosition: initialPosition,
      sourceContext: start.sourceContext,
      createdAt: now,
      updatedAt: now,
    );

    await _write(() => _playbackSessions.create(session));

    _session = session;
    _listeningSegment = null;
    _hasQualified = false;

    if (playing) {
      await _startListeningSegment(now);
      _playingSince = now;
    } else {
      _playingSince = null;
    }

    await _qualifyIfNeeded(now);

    return _session!;
  }

  Future<void> markPlaying({
    Duration? position,
    Duration? trackDuration,
  }) async {
    final current = _requireSession();

    if (_playingSince != null) {
      if (position != null || trackDuration != null) {
        await checkpoint(
          position: position ?? current.finalPosition,
          trackDuration: trackDuration,
        );
      }
      return;
    }

    final now = _utcNow();

    final updated = current.copyWith(
      finalPosition: position ?? current.finalPosition,
      trackDuration: _resolvedTrackDuration(
        current: current.trackDuration,
        incoming: trackDuration,
      ),
      updatedAt: now,
    );

    await _write(() => _playbackSessions.save(updated));

    _session = updated;

    await _startListeningSegment(now);

    _playingSince = now;

    await _qualifyIfNeeded(now);
  }

  Future<void> markPaused({Duration? position, Duration? trackDuration}) async {
    final current = _requireSession();
    final now = _utcNow();

    final updated = _withAccumulatedListening(
      current,
      now: now,
      position: position ?? current.finalPosition,
      trackDuration: trackDuration,
    );

    final updatedSegment = _playingSince != null
        ? _updatedListeningSegment(now, close: true)
        : null;

    if (updatedSegment != null) {
      await _write(
        () => _mutationRunner.run((context) async {
          await context.listeningSegments.save(updatedSegment);
          await context.playbackSessions.save(updated);
        }),
      );
    } else {
      await _write(() => _playbackSessions.save(updated));
    }

    _session = updated;

    if (updatedSegment != null) {
      _listeningSegment = updatedSegment;
    }

    _playingSince = null;

    await _qualifyIfNeeded(now);
  }

  Future<void> checkpoint({
    required Duration position,
    Duration? trackDuration,
  }) async {
    final current = _requireSession();
    final now = _utcNow();

    final updated = _withAccumulatedListening(
      current,
      now: now,
      position: position,
      trackDuration: trackDuration,
    );

    final updatedSegment = _playingSince != null
        ? _updatedListeningSegment(now, close: false)
        : null;

    if (updatedSegment != null) {
      await _write(
        () => _mutationRunner.run((context) async {
          await context.listeningSegments.save(updatedSegment);
          await context.playbackSessions.save(updated);
        }),
      );
    } else {
      await _write(() => _playbackSessions.save(updated));
    }

    _session = updated;

    if (updatedSegment != null) {
      _listeningSegment = updatedSegment;
      _playingSince = now;
    }

    await _qualifyIfNeeded(now);
  }

  Future<PlaybackSession> end({
    required PlaybackSessionEndReason reason,
    required Duration position,
    Duration? trackDuration,
  }) async {
    final current = _requireSession();
    final now = _utcNow();

    final accumulated = _withAccumulatedListening(
      current,
      now: now,
      position: position,
      trackDuration: trackDuration,
    );

    final ended = accumulated.copyWith(
      endedAt: now,
      endReason: reason,
      updatedAt: now,
    );

    final updatedSegment = _playingSince != null
        ? _updatedListeningSegment(now, close: true)
        : null;

    if (updatedSegment != null) {
      await _write(
        () => _mutationRunner.run((context) async {
          await context.listeningSegments.save(updatedSegment);
          await context.playbackSessions.save(ended);
        }),
      );
    } else {
      await _write(() => _playbackSessions.save(ended));
    }

    _session = ended;

    if (updatedSegment != null) {
      _listeningSegment = updatedSegment;
    }

    await _qualifyIfNeeded(now);

    _session = null;
    _listeningSegment = null;
    _playingSince = null;
    _hasQualified = false;

    return ended;
  }

  PlaybackSession _withAccumulatedListening(
    PlaybackSession session, {
    required DateTime now,
    required Duration position,
    Duration? trackDuration,
  }) {
    var listenedDuration = session.listenedDuration;

    final playingSince = _playingSince;

    if (playingSince != null && now.isAfter(playingSince)) {
      listenedDuration += now.difference(playingSince);
    }

    return session.copyWith(
      listenedDuration: listenedDuration,
      trackDuration: _resolvedTrackDuration(
        current: session.trackDuration,
        incoming: trackDuration,
      ),
      finalPosition: position,
      updatedAt: now,
    );
  }

  Future<void> _startListeningSegment(DateTime startedAt) async {
    final existing = _listeningSegment;

    if (existing != null && !existing.isEnded) {
      throw StateError(
        'Cannot start a listening segment while another segment is active.',
      );
    }

    final session = _requireSession();

    final segment = PlaybackListeningSegment(
      id: _listeningSegmentIdGenerator(),
      playbackSessionId: session.id,
      startedAt: startedAt,
      listenedDuration: Duration.zero,
      createdAt: startedAt,
      updatedAt: startedAt,
    );

    await _write(() => _listeningSegments.create(segment));

    _listeningSegment = segment;
  }

  PlaybackListeningSegment _updatedListeningSegment(
    DateTime now, {
    required bool close,
  }) {
    final current = _listeningSegment;

    if (current == null || current.isEnded) {
      throw StateError('Audible playback has no active listening segment.');
    }

    final listenedDuration = now.isAfter(current.startedAt)
        ? now.difference(current.startedAt)
        : Duration.zero;

    return current.copyWith(
      endedAt: close ? now : null,
      listenedDuration: listenedDuration,
      updatedAt: now,
    );
  }

  Duration _resolvedTrackDuration({
    required Duration current,
    required Duration? incoming,
  }) {
    if (incoming == null || incoming <= Duration.zero) {
      return current;
    }

    return incoming;
  }

  Future<void> _qualifyIfNeeded(DateTime qualifiedAt) async {
    final session = _requireSession();

    if (_hasQualified) {
      return;
    }

    final existing = await _qualifiedPlays.getByPlaybackSessionId(session.id);

    if (existing != null) {
      _hasQualified = true;
      return;
    }

    if (!_qualificationPolicy.qualifies(
      listenedDuration: session.listenedDuration,
      trackDuration: session.trackDuration,
    )) {
      return;
    }

    final play = QualifiedPlay(
      id: _qualifiedPlayIdGenerator(),
      playbackSessionId: session.id,
      userId: session.userId,
      songId: session.songId,
      artistId: session.artistId,
      albumId: session.albumId,
      albumEditionId: session.albumEditionId,
      qualifiedAt: qualifiedAt,
      listenedDuration: session.listenedDuration,
      trackDuration: session.trackDuration,
      createdAt: qualifiedAt,
    );

    await _write(() => _qualifiedPlays.create(play));

    _hasQualified = true;
    LibraryChangeSignal.shared.notify(LibraryChangeKind.listeningRecorded);
  }

  PlaybackSession _requireSession() {
    final current = _session;

    if (current == null) {
      throw StateError('No active listening session.');
    }

    return current;
  }

  DateTime _utcNow() => _now().toUtc();
}
