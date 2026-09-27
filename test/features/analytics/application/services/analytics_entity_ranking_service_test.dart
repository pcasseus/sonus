import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_entity_ranking_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';

class FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  FakeQualifiedPlayRepository([List<QualifiedPlay> plays = const []])
    : _plays = List<QualifiedPlay>.from(plays);

  final List<QualifiedPlay> _plays;

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
  required String albumEditionId,
  required DateTime qualifiedAt,
}) {
  return QualifiedPlay(
    id: id,
    playbackSessionId: 'session_$id',
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: albumEditionId,
    qualifiedAt: qualifiedAt,
    listenedDuration: const Duration(seconds: 30),
    trackDuration: const Duration(minutes: 3),
    createdAt: qualifiedAt,
  );
}

void main() {
  group('AnalyticsEntityRankingService', () {
    test('returns empty rankings when there are no qualified plays', () async {
      final service = AnalyticsEntityRankingService(
        qualifiedPlays: FakeQualifiedPlayRepository(),
      );

      final rankings = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(rankings.songs, isEmpty);
      expect(rankings.artists, isEmpty);
      expect(rankings.albums, isEmpty);
      expect(rankings.albumEditions, isEmpty);
    });

    test('ranks songs by qualified stream count descending', () async {
      final service = AnalyticsEntityRankingService(
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(
            id: '1',
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
            albumEditionId: 'edition_a',
            qualifiedAt: DateTime.utc(2026, 9, 25, 8),
          ),
          play(
            id: '2',
            songId: 'song_b',
            artistId: 'artist_b',
            albumId: 'album_b',
            albumEditionId: 'edition_b',
            qualifiedAt: DateTime.utc(2026, 9, 25, 9),
          ),
          play(
            id: '3',
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
            albumEditionId: 'edition_a',
            qualifiedAt: DateTime.utc(2026, 9, 25, 10),
          ),
          play(
            id: '4',
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
            albumEditionId: 'edition_a',
            qualifiedAt: DateTime.utc(2026, 9, 25, 11),
          ),
        ]),
      );

      final rankings = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(rankings.songs.map((entry) => entry.entityId).toList(), [
        'song_a',
        'song_b',
      ]);

      expect(rankings.songs[0].qualifiedStreamCount, 3);
      expect(rankings.songs[1].qualifiedStreamCount, 1);
    });

    test(
      'artist rankings use primary artist ids from qualified plays',
      () async {
        final service = AnalyticsEntityRankingService(
          qualifiedPlays: FakeQualifiedPlayRepository([
            play(
              id: '1',
              songId: 'song_1',
              artistId: 'artist_primary',
              albumId: 'album_1',
              albumEditionId: 'edition_1',
              qualifiedAt: DateTime.utc(2026, 9, 25, 8),
            ),
            play(
              id: '2',
              songId: 'song_2',
              artistId: 'artist_primary',
              albumId: 'album_2',
              albumEditionId: 'edition_2',
              qualifiedAt: DateTime.utc(2026, 9, 25, 9),
            ),
          ]),
        );

        final rankings = await service.load(
          period: AnalyticsPeriod.day,
          referenceLocal: DateTime(2026, 9, 25, 12),
        );

        expect(rankings.artists, hasLength(1));
        expect(rankings.artists.single.entityId, 'artist_primary');
        expect(rankings.artists.single.qualifiedStreamCount, 2);
      },
    );

    test('parent album ranking combines different album editions', () async {
      final service = AnalyticsEntityRankingService(
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(
            id: '1',
            songId: 'song_standard',
            artistId: 'artist_1',
            albumId: 'album_parent',
            albumEditionId: 'edition_standard',
            qualifiedAt: DateTime.utc(2026, 9, 25, 8),
          ),
          play(
            id: '2',
            songId: 'song_deluxe',
            artistId: 'artist_1',
            albumId: 'album_parent',
            albumEditionId: 'edition_deluxe',
            qualifiedAt: DateTime.utc(2026, 9, 25, 9),
          ),
        ]),
      );

      final rankings = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(rankings.albums, hasLength(1));
      expect(rankings.albums.single.entityId, 'album_parent');
      expect(rankings.albums.single.qualifiedStreamCount, 2);

      expect(rankings.albumEditions, hasLength(2));
    });

    test('album editions remain separately ranked', () async {
      final service = AnalyticsEntityRankingService(
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(
            id: '1',
            songId: 'song_1',
            artistId: 'artist_1',
            albumId: 'album_parent',
            albumEditionId: 'edition_standard',
            qualifiedAt: DateTime.utc(2026, 9, 25, 8),
          ),
          play(
            id: '2',
            songId: 'song_2',
            artistId: 'artist_1',
            albumId: 'album_parent',
            albumEditionId: 'edition_deluxe',
            qualifiedAt: DateTime.utc(2026, 9, 25, 9),
          ),
          play(
            id: '3',
            songId: 'song_3',
            artistId: 'artist_1',
            albumId: 'album_parent',
            albumEditionId: 'edition_deluxe',
            qualifiedAt: DateTime.utc(2026, 9, 25, 10),
          ),
        ]),
      );

      final rankings = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(rankings.albumEditions.map((entry) => entry.entityId).toList(), [
        'edition_deluxe',
        'edition_standard',
      ]);

      expect(rankings.albumEditions.first.qualifiedStreamCount, 2);
    });

    test('ties prefer the entity played most recently', () async {
      final service = AnalyticsEntityRankingService(
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(
            id: '1',
            songId: 'song_old',
            artistId: 'artist_1',
            albumId: 'album_1',
            albumEditionId: 'edition_1',
            qualifiedAt: DateTime.utc(2026, 9, 25, 8),
          ),
          play(
            id: '2',
            songId: 'song_recent',
            artistId: 'artist_2',
            albumId: 'album_2',
            albumEditionId: 'edition_2',
            qualifiedAt: DateTime.utc(2026, 9, 25, 10),
          ),
        ]),
      );

      final rankings = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(rankings.songs.map((entry) => entry.entityId).toList(), [
        'song_recent',
        'song_old',
      ]);
    });

    test('complete ties use entity id for deterministic ordering', () async {
      final timestamp = DateTime.utc(2026, 9, 25, 10);

      final service = AnalyticsEntityRankingService(
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(
            id: '1',
            songId: 'song_b',
            artistId: 'artist_b',
            albumId: 'album_b',
            albumEditionId: 'edition_b',
            qualifiedAt: timestamp,
          ),
          play(
            id: '2',
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
            albumEditionId: 'edition_a',
            qualifiedAt: timestamp,
          ),
        ]),
      );

      final rankings = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      expect(rankings.songs.map((entry) => entry.entityId).toList(), [
        'song_a',
        'song_b',
      ]);
    });

    test('tracks first and last qualification time for each entity', () async {
      final service = AnalyticsEntityRankingService(
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(
            id: '1',
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
            albumEditionId: 'edition_a',
            qualifiedAt: DateTime.utc(2026, 9, 25, 11),
          ),
          play(
            id: '2',
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
            albumEditionId: 'edition_a',
            qualifiedAt: DateTime.utc(2026, 9, 25, 8),
          ),
          play(
            id: '3',
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
            albumEditionId: 'edition_a',
            qualifiedAt: DateTime.utc(2026, 9, 25, 15),
          ),
        ]),
      );

      final rankings = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
      );

      final song = rankings.songs.single;

      expect(song.firstQualifiedAt, DateTime.utc(2026, 9, 25, 8));

      expect(song.lastQualifiedAt, DateTime.utc(2026, 9, 25, 15));
    });

    test(
      'period filtering excludes qualified plays outside the window',
      () async {
        final service = AnalyticsEntityRankingService(
          qualifiedPlays: FakeQualifiedPlayRepository([
            play(
              id: 'inside',
              songId: 'song_inside',
              artistId: 'artist_inside',
              albumId: 'album_inside',
              albumEditionId: 'edition_inside',
              qualifiedAt: DateTime(2026, 9, 25, 12).toUtc(),
            ),
            play(
              id: 'outside',
              songId: 'song_outside',
              artistId: 'artist_outside',
              albumId: 'album_outside',
              albumEditionId: 'edition_outside',
              qualifiedAt: DateTime(2026, 9, 26).toUtc(),
            ),
          ]),
        );

        final rankings = await service.load(
          period: AnalyticsPeriod.day,
          referenceLocal: DateTime(2026, 9, 25, 12),
        );

        expect(rankings.songs, hasLength(1));
        expect(rankings.songs.single.entityId, 'song_inside');
      },
    );

    test('limit applies independently to every ranking category', () async {
      final service = AnalyticsEntityRankingService(
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(
            id: '1',
            songId: 'song_1',
            artistId: 'artist_1',
            albumId: 'album_1',
            albumEditionId: 'edition_1',
            qualifiedAt: DateTime.utc(2026, 9, 25, 8),
          ),
          play(
            id: '2',
            songId: 'song_2',
            artistId: 'artist_2',
            albumId: 'album_2',
            albumEditionId: 'edition_2',
            qualifiedAt: DateTime.utc(2026, 9, 25, 9),
          ),
          play(
            id: '3',
            songId: 'song_3',
            artistId: 'artist_3',
            albumId: 'album_3',
            albumEditionId: 'edition_3',
            qualifiedAt: DateTime.utc(2026, 9, 25, 10),
          ),
        ]),
      );

      final rankings = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25, 12),
        limit: 2,
      );

      expect(rankings.songs, hasLength(2));
      expect(rankings.artists, hasLength(2));
      expect(rankings.albums, hasLength(2));
      expect(rankings.albumEditions, hasLength(2));
    });

    test('rejects non-positive limits', () async {
      final service = AnalyticsEntityRankingService(
        qualifiedPlays: FakeQualifiedPlayRepository(),
      );

      expect(
        () => service.load(
          period: AnalyticsPeriod.day,
          referenceLocal: DateTime(2026, 9, 25),
          limit: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
