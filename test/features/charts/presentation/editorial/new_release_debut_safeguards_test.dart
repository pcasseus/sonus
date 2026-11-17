// App Update 1.3 new-release debuts, final safeguards (user rules
// 2026-11-16), through the real editorial desk: no retroactive story from a
// release date set after the debut, no unproven first appearance, nothing
// new about deleted, merged-away or orphaned songs, no breaking news from a
// restore or a cloud rebuild, and published records told unchanged
// through all of it.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_eligibility.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/new_release_debut_desk.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

import 'new_release_debut_desk_test.dart'
    show
        Facts,
        albumFacts,
        albumTrack,
        career,
        compose,
        dead,
        eternity,
        isNewRelease,
        proven,
        start,
        storyOf,
        week1,
        week2,
        weekly;

/// The career debut of "Dead": Tuesday of the first week told.
final debutAt = week1.add(const Duration(days: 2, hours: 10));

NewReleaseLookups singleWritten(DateTime? at) => Facts({
  dead.entityId: NewReleaseSongFacts(
    songId: dead.entityId,
    isSingle: true,
    singleReleaseDate: ReleaseDate.of(2026, 11, 7),
    singleWrittenAt: at,
  ),
});

NewReleaseEvidence evidence({
  DateTime? origin,
  DateTime? cutoff,
  Map<String, DateTime>? firstPlays,
}) => NewReleaseEvidence(
  historyOriginUtc: origin ?? proven.historyOriginUtc,
  momentsCutoffUtc: cutoff,
  firstPlayAt: firstPlays ?? proven.firstPlayAt,
);

bool toldAsNew(List<MomentStory> stories, ChartMomentEvent event) =>
    isNewRelease(storyOf(stories, event));

void main() {
  final careerDebut = career(dead, at: debutAt, rank: 45);
  final weeklyDebut = weekly(dead, weekStart: week1, rank: 12);

  test('baseline: proven, the first debut is told as the new single', () {
    expect(toldAsNew(compose([careerDebut, weeklyDebut]), careerDebut), isTrue);
  });

  group('rule 1: a Single date set or edited after the debut', () {
    test('set after the original chart debut: no special story on either '
        'chart', () {
      final facts = singleWritten(debutAt.add(const Duration(hours: 2)));
      final stories = compose([careerDebut, weeklyDebut], facts: facts);
      expect(stories.where(isNewRelease), isEmpty);
      // Not delayed to the weekly debut either, though the date was written
      // before that week closed.
      expect(toldAsNew(stories, weeklyDebut), isFalse);
    });

    test('edited after the debut (set before, changed later): no special '
        'story', () {
      // The presentation existed before the debut; its last write is after.
      final facts = singleWritten(week2.add(const Duration(days: 1)));
      expect(compose([weeklyDebut], facts: facts).where(isNewRelease), isEmpty);
    });

    test('an album edition dated after the debut: no special story', () {
      final facts = Facts({eternity.entityId: albumTrack(albumFacts())});
      final debut = career(eternity, at: debutAt, rank: 30);
      expect(toldAsNew(compose([debut], facts: facts), debut), isTrue);

      final edited = albumFacts();
      final late = Facts({
        eternity.entityId: albumTrack(
          NewReleaseAlbumFacts(
            albumId: edited.albumId,
            title: edited.title,
            format: edited.format,
            editions: [
              NewReleaseEditionFacts(
                type: edited.editions.single.type,
                releaseDate: edited.editions.single.releaseDate,
                writtenAt: debutAt.add(const Duration(minutes: 5)),
              ),
            ],
          ),
        ),
      });
      expect(toldAsNew(compose([debut], facts: late), debut), isFalse);
    });

    test('an unknown write time tells nothing', () {
      expect(
        compose([careerDebut], facts: singleWritten(null)).where(isNewRelease),
        isEmpty,
      );
    });
  });

  group('rule 2: missing earlier history', () {
    test('first played before the coverage start (it may have charted '
        'unrecorded): no special story', () {
      final stories = compose(
        [careerDebut, weeklyDebut],
        evidence: evidence(
          firstPlays: {dead.entityId: start.subtract(const Duration(days: 9))},
        ),
      );
      expect(stories.where(isNewRelease), isEmpty);
    });

    test('no stored play: no special story', () {
      expect(
        compose([
          careerDebut,
        ], evidence: evidence(firstPlays: const {})).where(isNewRelease),
        isEmpty,
      );
    });

    test('no evidence at all (unread or failed): no special story', () {
      expect(
        compose([
          careerDebut,
        ], evidence: NewReleaseEvidence.none).where(isNewRelease),
        isEmpty,
      );
    });

    test('a permanent deletion after the first play (weeks recalculated '
        'without Moments): no special story', () {
      expect(
        compose(
          [weeklyDebut],
          evidence: evidence(cutoff: week1.add(const Duration(days: 3))),
        ).where(isNewRelease),
        isEmpty,
      );
    });
  });

  group('rule 3: deleted, merged-away and orphaned identities', () {
    test('a deleted song (no longer in the library) gets nothing new', () {
      expect(
        compose([careerDebut], facts: Facts(const {})).where(isNewRelease),
        isEmpty,
      );
    });

    test('a merged-away song: its stray debut tells nothing; the kept song, '
        'whose plays moved in, is not proven either', () {
      // "Dead" was merged into "For All Eternity": only the kept song is in
      // the library, and the merge moved the duplicate's earlier plays.
      final keptFacts = Facts({eternity.entityId: albumTrack(albumFacts())});
      final mergedAt = week1.add(const Duration(days: 1));
      final keptDebut = career(eternity, at: debutAt, rank: 30);
      final stories = compose(
        [careerDebut, keptDebut],
        facts: keptFacts,
        evidence: evidence(
          cutoff: mergedAt,
          firstPlays: {eternity.entityId: start, dead.entityId: start},
        ),
      );
      expect(toldAsNew(stories, careerDebut), isFalse);
      expect(toldAsNew(stories, keptDebut), isFalse);
      // Without the merge's cutoff the kept song would have been told.
      expect(
        toldAsNew(compose([keptDebut], facts: keptFacts), keptDebut),
        isTrue,
      );
    });

    test('an orphaned record (its song no longer exists) creates nothing '
        'new and stays as it was', () {
      final record = storyOf(
        compose([careerDebut]),
        careerDebut,
      ).newRelease!.publication;
      // A later debut of the same id (for example pulled from the cloud)
      // while the song is gone.
      final stray = weekly(dead, weekStart: week2, rank: 20);
      final stories = compose(
        [stray],
        facts: Facts(const {}),
        publications: {dead.entityId: record},
      );
      expect(stories.where(isNewRelease), isEmpty);
    });
  });

  group('rule 4: restores and cloud rebuilds', () {
    test('a restored database: older debuts without records are not '
        'published as new', () {
      // Restored the day after the week closed; the plays and debuts came
      // back with the backup.
      final restoredAt = week2.add(const Duration(days: 1));
      final stories = compose([
        careerDebut,
        weeklyDebut,
      ], evidence: evidence(origin: restoredAt));
      expect(stories.where(isNewRelease), isEmpty);
    });

    test('after the restore, a song first played and debuting after it is '
        'told', () {
      final restoredAt = week1.add(const Duration(days: 1));
      final afterRestore = career(
        dead,
        at: restoredAt.add(const Duration(hours: 3)),
        rank: 45,
      );
      final stories = compose(
        [afterRestore],
        evidence: evidence(
          origin: restoredAt,
          firstPlays: {dead.entityId: restoredAt.add(const Duration(hours: 1))},
        ),
      );
      expect(toldAsNew(stories, afterRestore), isTrue);
    });

    test('a phone rebuilt from the cloud: career debuts from the archive '
        'are not breaking news, even when only later plays arrived', () {
      final rebuiltAt = week2.add(const Duration(days: 2));
      final archived = career(dead, at: debutAt, rank: 45);
      // Its earlier plays arrived too.
      expect(
        compose([
          archived,
        ], evidence: evidence(origin: rebuiltAt)).where(isNewRelease),
        isEmpty,
      );
      // Only plays after the rebuild are here, but the archived debut was
      // stored on the other device before this database began.
      final rebuilt = NewReleaseEvidence(
        historyOriginUtc: rebuiltAt,
        firstPlayAt: {dead.entityId: rebuiltAt.add(const Duration(hours: 1))},
      );
      expect(
        compose([archived], evidence: rebuilt).where(isNewRelease),
        isEmpty,
      );
    });
  });

  group('rule 5: published records are told unchanged through all of it', () {
    test('restore, cloud rebuild, deletion cutoff, missing plays, a date '
        'edited later, and the song gone', () {
      final record = storyOf(
        compose([careerDebut]),
        careerDebut,
      ).newRelease!.publication;
      final published = {dead.entityId: record};
      final later = week2.add(const Duration(days: 3));

      final scenarios = <String, List<MomentStory>>{
        'restored': compose(
          [careerDebut, weeklyDebut],
          publications: published,
          evidence: evidence(origin: later),
        ),
        'cutoff': compose(
          [careerDebut, weeklyDebut],
          publications: published,
          evidence: evidence(cutoff: later),
        ),
        'no plays': compose(
          [careerDebut, weeklyDebut],
          publications: published,
          evidence: evidence(firstPlays: const {}),
        ),
        'no evidence': compose(
          [careerDebut, weeklyDebut],
          publications: published,
          evidence: NewReleaseEvidence.none,
        ),
        'date edited later': compose(
          [careerDebut, weeklyDebut],
          publications: published,
          facts: singleWritten(later),
        ),
        'song gone': compose(
          [careerDebut, weeklyDebut],
          publications: published,
          facts: Facts(const {}),
        ),
      };
      for (final MapEntry(key: name, value: stories) in scenarios.entries) {
        final story = storyOf(stories, careerDebut);
        expect(story.headline, record.headline, reason: name);
        expect(story.newRelease!.recorded, isTrue, reason: name);
        expect(
          identical(story.newRelease!.publication, record),
          isTrue,
          reason: name,
        );
        expect(toldAsNew(stories, weeklyDebut), isFalse, reason: name);
      }
    });
  });
}
