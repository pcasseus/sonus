import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/home/presentation/controllers/home_controller.dart';
import 'package:sonus_next/features/home/presentation/scopes/home_scope.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';

void main() {
  testWidgets('creates and auto-loads HomeController when dependencies exist', (
    tester,
  ) async {
    HomeController? controller;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryQueryRepository?>.value(
            value: _FakeLibraryQueryRepository(),
          ),
          Provider<QualifiedPlayRepository?>.value(
            value: _FakeQualifiedPlayRepository(),
          ),
          Provider<PlaybackSessionRepository?>.value(
            value: _FakePlaybackSessionRepository(),
          ),
          Provider<PlaybackListeningSegmentRepository?>.value(
            value: _FakePlaybackListeningSegmentRepository(),
          ),
        ],
        child: HomeScope(
          now: () => DateTime(2026, 9, 28, 12),
          child: Builder(
            builder: (context) {
              controller = context.watch<HomeController?>();
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(controller, isNotNull);
    expect(controller!.isLoading, isFalse);
    expect(controller!.hasError, isFalse);
    expect(controller!.hasData, isTrue);
    expect(controller!.snapshot, isNotNull);
    expect(controller!.snapshot!.isEmpty, isTrue);
  });

  // Data-1: Home reloads by itself after listening or library changes.
  testWidgets('reloads after a library or listening change', (tester) async {
    final plays = _FakeQualifiedPlayRepository();
    final signal = LibraryChangeSignal();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryQueryRepository?>.value(
            value: _FakeLibraryQueryRepository(),
          ),
          Provider<QualifiedPlayRepository?>.value(value: plays),
          Provider<PlaybackSessionRepository?>.value(
            value: _FakePlaybackSessionRepository(),
          ),
          Provider<PlaybackListeningSegmentRepository?>.value(
            value: _FakePlaybackListeningSegmentRepository(),
          ),
        ],
        child: HomeScope(
          now: () => DateTime(2026, 9, 28, 12),
          changes: signal,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final loadsAfterOpening = plays.getAllCalls;

    signal.notify(LibraryChangeKind.listeningRecorded);
    signal.notify(LibraryChangeKind.listeningRecorded);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(plays.getAllCalls, greaterThan(loadsAfterOpening));
    final oneReload = plays.getAllCalls;

    await tester.pumpWidget(const SizedBox());
    signal.notify(LibraryChangeKind.listeningRecorded);
    await tester.pump(const Duration(milliseconds: 400));

    expect(plays.getAllCalls, oneReload, reason: 'nothing after dispose');
  });

  testWidgets('exposes no HomeController until all dependencies exist', (
    tester,
  ) async {
    HomeController? controller;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryQueryRepository?>.value(
            value: _FakeLibraryQueryRepository(),
          ),
          Provider<QualifiedPlayRepository?>.value(value: null),
          Provider<PlaybackSessionRepository?>.value(
            value: _FakePlaybackSessionRepository(),
          ),
          Provider<PlaybackListeningSegmentRepository?>.value(
            value: _FakePlaybackListeningSegmentRepository(),
          ),
        ],
        child: HomeScope(
          child: Builder(
            builder: (context) {
              controller = context.watch<HomeController?>();
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(controller, isNull);
  });
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => const [];

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async =>
      const [];

  @override
  Future<LibraryTrack?> getTrackById(String songId) async => null;

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => const [];

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async =>
      const [];

  @override
  Future<List<LibraryAlbum>> getAlbums() async => const [];

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async =>
      const [];

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async => null;

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async =>
      const [];

  @override
  Future<List<LibraryArtist>> getArtists() async => const [];

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async => null;
}

class _FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  @override
  Future<void> create(QualifiedPlay play) async {}

  @override
  Future<void> save(QualifiedPlay play) async {}

  @override
  Future<QualifiedPlay?> getById(String id) async => null;

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(
    String playbackSessionId,
  ) async => null;

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) async => const [];

  int getAllCalls = 0;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    getAllCalls++;
    return const [];
  }
}

class _FakePlaybackSessionRepository implements PlaybackSessionRepository {
  final List<PlaybackSession> _sessions = [];

  @override
  Future<void> create(PlaybackSession session) async {
    _sessions.add(session);
  }

  @override
  Future<void> save(PlaybackSession session) async {
    final index = _sessions.indexWhere((value) => value.id == session.id);

    if (index < 0) {
      throw StateError('Playback session not found: ${session.id}');
    }

    _sessions[index] = session;
  }

  @override
  Future<PlaybackSession?> getById(String id) async {
    for (final session in _sessions) {
      if (session.id == id) {
        return session;
      }
    }

    return null;
  }

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getOpen() async {
    return _sessions
        .where((session) => !session.isEnded)
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    return _sessions
        .where((session) {
          final startedAt = session.startedAt.toUtc();

          if (startedAtOrAfter != null &&
              startedAt.isBefore(startedAtOrAfter.toUtc())) {
            return false;
          }

          if (startedBefore != null &&
              !startedAt.isBefore(startedBefore.toUtc())) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async {
    final sessions = await getAll(
      startedAtOrAfter: startedAtOrAfter,
      startedBefore: startedBefore,
    );

    return sessions.take(limit).toList(growable: false);
  }
}

class _FakePlaybackListeningSegmentRepository
    implements PlaybackListeningSegmentRepository {
  final List<PlaybackListeningSegment> _segments = [];

  @override
  Future<void> create(PlaybackListeningSegment segment) async {
    _segments.add(segment);
  }

  @override
  Future<void> save(PlaybackListeningSegment segment) async {
    final index = _segments.indexWhere((value) => value.id == segment.id);

    if (index < 0) {
      throw StateError('Listening segment not found: ${segment.id}');
    }

    _segments[index] = segment;
  }

  @override
  Future<PlaybackListeningSegment?> getById(String id) async {
    for (final segment in _segments) {
      if (segment.id == id) {
        return segment;
      }
    }

    return null;
  }

  @override
  Future<PlaybackListeningSegment?> getOpenForSession(
    String playbackSessionId,
  ) async {
    for (final segment in _segments) {
      if (segment.playbackSessionId == playbackSessionId && !segment.isEnded) {
        return segment;
      }
    }

    return null;
  }

  @override
  Future<List<PlaybackListeningSegment>> getForSession(
    String playbackSessionId,
  ) async {
    return _segments
        .where((segment) => segment.playbackSessionId == playbackSessionId)
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackListeningSegment>> getAll({
    DateTime? startedBefore,
  }) async {
    return _segments
        .where((segment) {
          if (startedBefore == null) {
            return true;
          }

          return segment.startedAt.toUtc().isBefore(startedBefore.toUtc());
        })
        .toList(growable: false);
  }
}
