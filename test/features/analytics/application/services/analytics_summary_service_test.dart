import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_summary_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';

class FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  FakeQualifiedPlayRepository([List<QualifiedPlay> plays = const []])
    : _plays = List<QualifiedPlay>.from(plays);

  final List<QualifiedPlay> _plays;

  DateTime? lastQualifiedAtOrAfter;
  DateTime? lastQualifiedBefore;

  @override
  Future<void> create(QualifiedPlay play) async {
    _plays.add(play);
  }

  @override
  Future<void> save(QualifiedPlay play) async {
    final index = _plays.indexWhere((value) => value.id == play.id);

    if (index == -1) {
      throw StateError('Qualified play not found: ${play.id}');
    }

    _plays[index] = play;
  }

  @override
  Future<QualifiedPlay?> getById(String id) async {
    for (final play in _plays) {
      if (play.id == id) {
        return play;
      }
    }

    return null;
  }

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(
    String playbackSessionId,
  ) async {
    for (final play in _plays) {
      if (play.playbackSessionId == playbackSessionId) {
        return play;
      }
    }

    return null;
  }

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) async {
    final ids = playbackSessionIds.toSet();

    return _plays
        .where((play) => ids.contains(play.playbackSessionId))
        .toList(growable: false);
  }

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    lastQualifiedAtOrAfter = qualifiedAtOrAfter;
    lastQualifiedBefore = qualifiedBefore;

    return _plays.where((play) {
      final qualifiedAt = play.qualifiedAt.toUtc();

      if (qualifiedAtOrAfter != null &&
          qualifiedAt.isBefore(qualifiedAtOrAfter.toUtc())) {
        return false;
      }

      if (qualifiedBefore != null &&
          !qualifiedAt.isBefore(qualifiedBefore.toUtc())) {
        return false;
      }

      return true;
    }).toList();
  }
}

QualifiedPlay play({
  required String id,
  required String songId,
  required String artistId,
  required String albumId,
  required DateTime qualifiedAt,
  required Duration listenedDuration,
  String albumEditionId = 'edition',
}) {
  return QualifiedPlay(
    id: id,
    playbackSessionId: 'session_$id',
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: albumEditionId,
    qualifiedAt: qualifiedAt,
    listenedDuration: listenedDuration,
    trackDuration: const Duration(minutes: 3),
    createdAt: qualifiedAt,
  );
}

void main() {
  group('AnalyticsSummaryService', () {
    test('returns empty summary when there are no qualified plays', () async {
      final repository = FakeQualifiedPlayRepository();

      final service = AnalyticsSummaryService(qualifiedPlays: repository);

      final summary = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(summary.qualifiedStreamCount, 0);
      expect(summary.qualifiedListeningDuration, Duration.zero);
      expect(summary.distinctSongCount, 0);
      expect(summary.distinctArtistCount, 0);
      expect(summary.distinctAlbumCount, 0);
      expect(summary.firstQualifiedAt, isNull);
      expect(summary.lastQualifiedAt, isNull);
      expect(summary.hasListening, isFalse);
    });

    test('counts qualified streams independently', () async {
      final repository = FakeQualifiedPlayRepository([
        play(
          id: 'play_1',
          songId: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          qualifiedAt: DateTime.utc(2026, 9, 25, 10),
          listenedDuration: const Duration(seconds: 30),
        ),
        play(
          id: 'play_2',
          songId: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          qualifiedAt: DateTime.utc(2026, 9, 25, 11),
          listenedDuration: const Duration(seconds: 45),
        ),
      ]);

      final service = AnalyticsSummaryService(qualifiedPlays: repository);

      final summary = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(summary.qualifiedStreamCount, 2);
      expect(summary.qualifiedListeningDuration, const Duration(seconds: 75));

      expect(summary.distinctSongCount, 1);
      expect(summary.distinctArtistCount, 1);
      expect(summary.distinctAlbumCount, 1);
      expect(summary.hasListening, isTrue);
    });

    test('counts distinct songs artists and parent albums', () async {
      final repository = FakeQualifiedPlayRepository([
        play(
          id: 'play_1',
          songId: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          albumEditionId: 'edition_1',
          qualifiedAt: DateTime.utc(2026, 9, 25, 9),
          listenedDuration: const Duration(seconds: 30),
        ),
        play(
          id: 'play_2',
          songId: 'song_2',
          artistId: 'artist_1',
          albumId: 'album_1',
          albumEditionId: 'edition_2',
          qualifiedAt: DateTime.utc(2026, 9, 25, 10),
          listenedDuration: const Duration(seconds: 30),
        ),
        play(
          id: 'play_3',
          songId: 'song_3',
          artistId: 'artist_2',
          albumId: 'album_2',
          albumEditionId: 'edition_3',
          qualifiedAt: DateTime.utc(2026, 9, 25, 11),
          listenedDuration: const Duration(seconds: 30),
        ),
      ]);

      final service = AnalyticsSummaryService(qualifiedPlays: repository);

      final summary = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(summary.distinctSongCount, 3);
      expect(summary.distinctArtistCount, 2);
      expect(summary.distinctAlbumCount, 2);
    });

    test('parent album count combines multiple editions', () async {
      final repository = FakeQualifiedPlayRepository([
        play(
          id: 'play_standard',
          songId: 'song_standard',
          artistId: 'artist_1',
          albumId: 'album_parent',
          albumEditionId: 'edition_standard',
          qualifiedAt: DateTime.utc(2026, 9, 25, 10),
          listenedDuration: const Duration(seconds: 30),
        ),
        play(
          id: 'play_deluxe',
          songId: 'song_deluxe',
          artistId: 'artist_1',
          albumId: 'album_parent',
          albumEditionId: 'edition_deluxe',
          qualifiedAt: DateTime.utc(2026, 9, 25, 11),
          listenedDuration: const Duration(seconds: 30),
        ),
      ]);

      final service = AnalyticsSummaryService(qualifiedPlays: repository);

      final summary = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(summary.qualifiedStreamCount, 2);
      expect(summary.distinctAlbumCount, 1);
    });

    test('records earliest and latest qualified play', () async {
      final repository = FakeQualifiedPlayRepository([
        play(
          id: 'play_middle',
          songId: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          qualifiedAt: DateTime.utc(2026, 9, 25, 12),
          listenedDuration: const Duration(seconds: 30),
        ),
        play(
          id: 'play_latest',
          songId: 'song_2',
          artistId: 'artist_2',
          albumId: 'album_2',
          qualifiedAt: DateTime.utc(2026, 9, 25, 20),
          listenedDuration: const Duration(seconds: 30),
        ),
        play(
          id: 'play_earliest',
          songId: 'song_3',
          artistId: 'artist_3',
          albumId: 'album_3',
          qualifiedAt: DateTime.utc(2026, 9, 25, 8),
          listenedDuration: const Duration(seconds: 30),
        ),
      ]);

      final service = AnalyticsSummaryService(qualifiedPlays: repository);

      final summary = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(summary.firstQualifiedAt, DateTime.utc(2026, 9, 25, 8));

      expect(summary.lastQualifiedAt, DateTime.utc(2026, 9, 25, 20));
    });

    test('excludes plays at the exclusive end boundary', () async {
      final repository = FakeQualifiedPlayRepository([
        play(
          id: 'inside',
          songId: 'song_inside',
          artistId: 'artist_1',
          albumId: 'album_1',
          qualifiedAt: DateTime(2026, 9, 25, 23, 59, 59).toUtc(),
          listenedDuration: const Duration(seconds: 30),
        ),
        play(
          id: 'next_day',
          songId: 'song_next',
          artistId: 'artist_2',
          albumId: 'album_2',
          qualifiedAt: DateTime(2026, 9, 26).toUtc(),
          listenedDuration: const Duration(seconds: 30),
        ),
      ]);

      final service = AnalyticsSummaryService(qualifiedPlays: repository);

      final summary = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(summary.qualifiedStreamCount, 1);
      expect(summary.distinctSongCount, 1);
    });

    test('passes resolved period boundaries to repository', () async {
      final repository = FakeQualifiedPlayRepository();

      final service = AnalyticsSummaryService(qualifiedPlays: repository);

      await service.load(
        period: AnalyticsPeriod.week,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(repository.lastQualifiedAtOrAfter, DateTime(2026, 9, 20).toUtc());

      expect(repository.lastQualifiedBefore, DateTime(2026, 9, 27).toUtc());
    });

    test('lifetime requests all qualified plays without boundaries', () async {
      final repository = FakeQualifiedPlayRepository([
        play(
          id: 'old',
          songId: 'song_old',
          artistId: 'artist_old',
          albumId: 'album_old',
          qualifiedAt: DateTime.utc(2020, 1, 1),
          listenedDuration: const Duration(seconds: 30),
        ),
        play(
          id: 'new',
          songId: 'song_new',
          artistId: 'artist_new',
          albumId: 'album_new',
          qualifiedAt: DateTime.utc(2026, 9, 25),
          listenedDuration: const Duration(seconds: 40),
        ),
      ]);

      final service = AnalyticsSummaryService(qualifiedPlays: repository);

      final summary = await service.load(
        period: AnalyticsPeriod.lifetime,
        referenceLocal: DateTime(2026, 9, 25),
      );

      expect(repository.lastQualifiedAtOrAfter, isNull);
      expect(repository.lastQualifiedBefore, isNull);

      expect(summary.qualifiedStreamCount, 2);
      expect(summary.qualifiedListeningDuration, const Duration(seconds: 70));
    });
  });
}
