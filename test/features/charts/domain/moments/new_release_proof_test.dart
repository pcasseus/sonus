// App Update 1.3 new-release debuts, user rules 2026-11-16: a debut is told
// as a new release only with proof. Each rule fails closed and names its
// reason (NewReleaseEligibility.proofProblem).
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_eligibility.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

final _start = DateTime.utc(2026, 11, 15);
final _origin = DateTime.utc(2026, 11, 1);
final _week = _start;
final _weekEnd = _start.add(const Duration(days: 7));

const _song = ChartEntitySnapshot(
  entityId: 'song-dead',
  title: 'Dead',
  artistId: 'artist-1',
  artistName: 'Madison Beer',
);

ChartMomentEvent _career({required DateTime at, DateTime? createdAt}) =>
    ChartMomentEvent(
      id: 'career',
      deduplicationKey: 'career',
      chartType: ChartType.songs,
      scope: ChartMomentScope.allTime,
      eventType: ChartMomentEventType.debut,
      entity: _song,
      weekStartUtc: _week,
      weekEndUtc: _weekEnd,
      occurredAt: at,
      createdAt: createdAt ?? at,
      currentRank: 45,
    );

ChartMomentEvent _weekly({required DateTime weekStart, DateTime? createdAt}) {
  final end = weekStart.add(const Duration(days: 7));
  final finalized = end.add(const Duration(hours: 9));
  return ChartMomentEvent(
    id: 'weekly',
    deduplicationKey: 'weekly',
    chartType: ChartType.songs,
    scope: ChartMomentScope.finalized,
    eventType: ChartMomentEventType.debut,
    entity: _song,
    weekStartUtc: weekStart,
    weekEndUtc: end,
    occurredAt: finalized,
    createdAt: createdAt ?? finalized,
    currentRank: 12,
  );
}

NewReleaseSongFacts _single({DateTime? writtenAt}) => NewReleaseSongFacts(
  songId: _song.entityId,
  isSingle: true,
  singleReleaseDate: ReleaseDate.of(2026, 11, 7),
  singleWrittenAt: writtenAt,
);

NewReleaseSongFacts _albumTrack(List<DateTime?> writtenAt) =>
    NewReleaseSongFacts(
      songId: _song.entityId,
      isSingle: false,
      album: NewReleaseAlbumFacts(
        albumId: 'album-1',
        title: 'Locket',
        format: ReleaseFormat.album,
        editions: [
          for (final (index, at) in writtenAt.indexed)
            NewReleaseEditionFacts(
              type: index == 0
                  ? AlbumEditionType.standard
                  : AlbumEditionType.deluxe,
              releaseDate: ReleaseDate.of(2026, 11, 7),
              writtenAt: at,
            ),
        ],
      ),
    );

NewReleaseEvidence _evidence({
  DateTime? origin,
  bool noOrigin = false,
  DateTime? cutoff,
  DateTime? firstPlay,
  bool noPlays = false,
}) => NewReleaseEvidence(
  historyOriginUtc: noOrigin ? null : origin ?? _origin,
  momentsCutoffUtc: cutoff,
  firstPlayAt: noPlays ? const {} : {_song.entityId: firstPlay ?? _start},
);

NewReleaseIneligibility? _problem(
  ChartMomentEvent event,
  NewReleaseSongFacts facts,
  NewReleaseEvidence evidence, {
  DateTime? start,
}) {
  final debut = NewReleaseEligibility.evaluate(event, facts).debut!;
  return NewReleaseEligibility.proofProblem(
    debut,
    facts,
    evidence,
    start: NewReleaseDebutStart(start ?? _start),
  );
}

void main() {
  final debutAt = _start.add(const Duration(days: 2, hours: 10));
  final careerDebut = _career(at: debutAt);

  test('proven: release date written before the debut, first play at the '
      'start, recorded here', () {
    final written = debutAt.subtract(const Duration(days: 3));
    expect(
      _problem(careerDebut, _single(writtenAt: written), _evidence()),
      isNull,
    );
    expect(
      _problem(
        _weekly(weekStart: _week),
        _single(writtenAt: written),
        _evidence(),
      ),
      isNull,
    );
  });

  group('rule 1: a release date set or edited after the debut', () {
    test('a Single date set after the career debut', () {
      expect(
        _problem(
          careerDebut,
          _single(writtenAt: debutAt.add(const Duration(minutes: 1))),
          _evidence(),
        ),
        NewReleaseIneligibility.releaseDateNotProvenBeforeDebut,
      );
    });

    test('a Single date written exactly at the debut is proven', () {
      expect(
        _problem(careerDebut, _single(writtenAt: debutAt), _evidence()),
        isNull,
      );
    });

    test('a weekly debut is dated by its week close: a date edited after '
        'the close (before it was finalized) is not proven', () {
      expect(
        _problem(
          _weekly(weekStart: _week),
          _single(writtenAt: _weekEnd.add(const Duration(hours: 1))),
          _evidence(),
        ),
        NewReleaseIneligibility.releaseDateNotProvenBeforeDebut,
      );
    });

    test('an unknown write time is never proof', () {
      expect(
        _problem(careerDebut, _single(), _evidence()),
        NewReleaseIneligibility.releaseDateNotProvenBeforeDebut,
      );
    });

    test('album and EP tracks: every edition must be written before the '
        'debut', () {
      final before = debutAt.subtract(const Duration(days: 1));
      final after = debutAt.add(const Duration(days: 1));
      expect(
        _problem(careerDebut, _albumTrack([before, before]), _evidence()),
        isNull,
      );
      expect(
        _problem(careerDebut, _albumTrack([before, after]), _evidence()),
        NewReleaseIneligibility.releaseDateNotProvenBeforeDebut,
      );
      expect(
        _problem(careerDebut, _albumTrack([before, null]), _evidence()),
        NewReleaseIneligibility.releaseDateNotProvenBeforeDebut,
      );
    });
  });

  group('rule 2: earlier chart history must be proven complete', () {
    final written = _single(writtenAt: _origin);

    test('first played before the start: unproven', () {
      expect(
        _problem(
          careerDebut,
          written,
          _evidence(firstPlay: _start.subtract(const Duration(seconds: 1))),
        ),
        NewReleaseIneligibility.earlierHistoryUnproven,
      );
    });

    test('no stored play: unproven', () {
      expect(
        _problem(careerDebut, written, _evidence(noPlays: true)),
        NewReleaseIneligibility.earlierHistoryUnproven,
      );
    });

    test('no chart history origin: unproven', () {
      expect(
        _problem(careerDebut, written, _evidence(noOrigin: true)),
        NewReleaseIneligibility.earlierHistoryUnproven,
      );
    });

    test('a history origin after the start (a restore) moves the coverage '
        'start: a first play before it is unproven, after it proven', () {
      final restoredAt = _start.add(const Duration(days: 1));
      expect(
        _problem(
          careerDebut,
          written,
          _evidence(origin: restoredAt, firstPlay: _start),
        ),
        NewReleaseIneligibility.earlierHistoryUnproven,
      );
      expect(
        _problem(
          careerDebut,
          written,
          _evidence(origin: restoredAt, firstPlay: restoredAt),
        ),
        isNull,
      );
    });

    test('a later permanent deletion (Moments cutoff) after the first play: '
        'unproven', () {
      final deletedAt = _start.add(const Duration(days: 1));
      expect(
        _problem(careerDebut, written, _evidence(cutoff: deletedAt)),
        NewReleaseIneligibility.earlierHistoryUnproven,
      );
    });

    test('coverageFrom is the latest of start, origin and cutoff', () {
      final later = _start.add(const Duration(days: 3));
      final start = NewReleaseDebutStart(_start);
      expect(_evidence().coverageFrom(start), _start);
      expect(_evidence(origin: later).coverageFrom(start), later);
      expect(_evidence(cutoff: later).coverageFrom(start), later);
      expect(_evidence(noOrigin: true).coverageFrom(start), isNull);
      expect(_evidence().coverageFrom(NewReleaseDebutStart.none), isNull);
    });
  });

  group('rule 4: only debuts recorded on this database', () {
    final written = _single(writtenAt: _origin);

    test('stored before the coverage start (restored, or pulled from the '
        'cloud archive) although the plays here are later', () {
      final pulled = _career(
        at: debutAt,
        createdAt: _start.subtract(const Duration(hours: 1)),
      );
      expect(
        _problem(pulled, written, _evidence()),
        NewReleaseIneligibility.notRecordedHere,
      );
    });

    test('a weekly debut whose week began before a restore', () {
      final restoredAt = _week.add(const Duration(days: 1));
      expect(
        _problem(
          _weekly(weekStart: _week),
          written,
          _evidence(origin: restoredAt, firstPlay: restoredAt),
        ),
        NewReleaseIneligibility.notRecordedHere,
      );
    });
  });
}
