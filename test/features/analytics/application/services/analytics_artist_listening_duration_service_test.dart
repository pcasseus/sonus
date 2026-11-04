import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_artist_listening_duration_service.dart';
import 'package:sonus_next/features/analytics/application/services/listening_artist_attribution.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';

PlaybackSession session(String id, String artistId, DateTime startedAt) =>
    PlaybackSession(
      id: id,
      songId: 'song-$id',
      artistId: artistId,
      albumId: 'album-$artistId',
      albumEditionId: 'edition-$artistId',
      songTitle: 'Song',
      artistName: artistId,
      albumTitle: 'Album',
      albumEditionTitle: 'Standard',
      startedAt: startedAt,
      listenedDuration: Duration.zero,
      trackDuration: const Duration(minutes: 3),
      finalPosition: Duration.zero,
      createdAt: startedAt,
      updatedAt: startedAt,
    );

PlaybackListeningSegment segment(
  String id,
  String sessionId,
  DateTime startedAt,
  Duration length,
) => PlaybackListeningSegment(
  id: id,
  playbackSessionId: sessionId,
  startedAt: startedAt,
  endedAt: startedAt.add(length),
  listenedDuration: length,
  createdAt: startedAt,
  updatedAt: startedAt,
);

void main() {
  final start = DateTime.utc(2026, 3, 1, 10);

  test('sessions are read at once, not one query per session', () async {
    final sessions = _Sessions([
      session('s1', 'ada', start),
      session('s2', 'ada', start.add(const Duration(hours: 1))),
      session('s3', 'ben', start.add(const Duration(hours: 2))),
    ]);
    final totals = await AnalyticsArtistListeningDurationService(
      playbackSessions: sessions,
      listeningSegments: _Segments([
        segment('a', 's1', start, const Duration(minutes: 3)),
        // Two segments of one session, as after a pause.
        segment(
          'b',
          's2',
          start.add(const Duration(hours: 1)),
          const Duration(minutes: 1),
        ),
        segment(
          'c',
          's2',
          start.add(const Duration(hours: 1, minutes: 2)),
          const Duration(minutes: 1),
        ),
        segment(
          'd',
          's3',
          start.add(const Duration(hours: 2)),
          const Duration(seconds: 30),
        ),
      ]),
    ).load(period: AnalyticsPeriod.lifetime, referenceLocal: start);

    expect(totals, {
      'ada': const Duration(minutes: 5),
      'ben': const Duration(seconds: 30),
    });
    expect(sessions.getAllCalls, 1);
    expect(sessions.getByIdCalls, 0);
  });

  test('a session the batch did not return is still looked up', () async {
    final sessions = _Sessions(
      [session('s1', 'ada', start)],
      // Found by id only, as if missing from the batch read.
      hiddenFromGetAll: {'s2': session('s2', 'ben', start)},
    );
    final totals = await AnalyticsArtistListeningDurationService(
      playbackSessions: sessions,
      listeningSegments: _Segments([
        segment('a', 's1', start, const Duration(minutes: 1)),
        segment('b', 's2', start, const Duration(minutes: 2)),
        segment('c', 's2', start, const Duration(minutes: 2)),
        // Its session no longer exists: left out, as before.
        segment('d', 'gone', start, const Duration(minutes: 9)),
      ]),
    ).load(period: AnalyticsPeriod.lifetime, referenceLocal: start);

    expect(totals, {
      'ada': const Duration(minutes: 1),
      'ben': const Duration(minutes: 4),
    });
    expect(sessions.getByIdCalls, 2, reason: 's2 once (cached), gone once');
  });

  test('a bounded period counts only the time inside it', () async {
    // The week (Sunday to Saturday) containing Wednesday 2026-03-04; a
    // session that started the Saturday before still counts for the part
    // played inside the week.
    final reference = DateTime(2026, 3, 4, 12);
    final weekStart = DateTime(2026, 3, 1).toUtc();
    final before = weekStart.subtract(const Duration(minutes: 2));
    final totals = await AnalyticsArtistListeningDurationService(
      playbackSessions: _Sessions([session('s1', 'ada', before)]),
      listeningSegments: _Segments([
        segment('a', 's1', before, const Duration(minutes: 5)),
      ]),
    ).load(period: AnalyticsPeriod.week, referenceLocal: reference);

    expect(totals, {'ada': const Duration(minutes: 3)});
  });

  test('attribution decides which artist the time counts for', () async {
    final totals = await AnalyticsArtistListeningDurationService(
      playbackSessions: _Sessions([session('s1', 'cast', start)]),
      listeningSegments: _Segments([
        segment('a', 's1', start, const Duration(minutes: 2)),
      ]),
      artistAttribution: const _CountFor('soundtrack'),
    ).load(period: AnalyticsPeriod.lifetime, referenceLocal: start);

    expect(totals, {'soundtrack': const Duration(minutes: 2)});
  });
}

class _CountFor implements ListeningArtistAttribution {
  const _CountFor(this.artistId);

  final String artistId;

  @override
  Future<ArtistAttributor> load() async => ArtistAttributor((_, _) => artistId);
}

class _Sessions implements PlaybackSessionRepository {
  _Sessions(
    List<PlaybackSession> sessions, {
    Map<String, PlaybackSession> hiddenFromGetAll = const {},
  }) : _listed = {for (final s in sessions) s.id: s},
       _hidden = hiddenFromGetAll;

  final Map<String, PlaybackSession> _listed;
  final Map<String, PlaybackSession> _hidden;
  int getAllCalls = 0;
  int getByIdCalls = 0;

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    getAllCalls++;
    return [
      for (final s in _listed.values)
        if (startedBefore == null || s.startedAt.isBefore(startedBefore)) s,
    ];
  }

  @override
  Future<PlaybackSession?> getById(String id) async {
    getByIdCalls++;
    return _listed[id] ?? _hidden[id];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected query: ${invocation.memberName}');
}

class _Segments implements PlaybackListeningSegmentRepository {
  _Segments(this._segments);

  final List<PlaybackListeningSegment> _segments;

  @override
  Future<List<PlaybackListeningSegment>> getAll({
    DateTime? startedBefore,
  }) async => [
    for (final s in _segments)
      if (startedBefore == null || s.startedAt.isBefore(startedBefore)) s,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected query: ${invocation.memberName}');
}
