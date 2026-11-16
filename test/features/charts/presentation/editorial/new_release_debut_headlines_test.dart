import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_eligibility.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/new_release_debut_headlines.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

ChartMomentEvent debutEvent({
  required String title,
  required String artist,
  required int rank,
  ChartMomentScope scope = ChartMomentScope.finalized,
}) {
  final week = DateTime.utc(2026, 11, 16);
  return ChartMomentEvent(
    id: 'event-$title',
    deduplicationKey: 'dedupe-$title',
    chartType: ChartType.songs,
    scope: scope,
    eventType: ChartMomentEventType.debut,
    entity: ChartEntitySnapshot(
      entityId: 'song-$title',
      title: title,
      artistName: artist,
    ),
    weekStartUtc: week,
    weekEndUtc: week.add(const Duration(days: 7)),
    occurredAt: week.add(const Duration(days: 7)),
    createdAt: week.add(const Duration(days: 7)),
    currentRank: rank,
  );
}

NewReleaseDebut singleDebut(
  int rank, {
  ChartMomentScope scope = ChartMomentScope.finalized,
}) => NewReleaseEligibility.evaluate(
  debutEvent(title: 'Dead', artist: 'Madison Beer', rank: rank, scope: scope),
  NewReleaseSongFacts(
    songId: 'song-Dead',
    isSingle: true,
    singleReleaseDate: ReleaseDate.of(2026, 11, 7),
  ),
).debut!;

NewReleaseDebut albumTrackDebut(
  int rank, {
  ChartMomentScope scope = ChartMomentScope.finalized,
  ReleaseFormat format = ReleaseFormat.album,
}) => NewReleaseEligibility.evaluate(
  debutEvent(
    title: 'For All Eternity',
    artist: 'Tate McRae',
    rank: rank,
    scope: scope,
  ),
  NewReleaseSongFacts(
    songId: 'song-For All Eternity',
    isSingle: false,
    album: NewReleaseAlbumFacts(
      albumId: 'album-anatomy',
      title: 'Anatomy of a Popstar',
      format: format,
      editions: [
        NewReleaseEditionFacts(
          type: AlbumEditionType.standard,
          releaseDate: ReleaseDate.of(2026, 11),
        ),
      ],
    ),
  ),
).debut!;

void main() {
  group('4.1 new single headline', () {
    test('weekly Hot 100', () {
      expect(
        NewReleaseDebutHeadlines.headline(singleDebut(18)),
        'Madison Beer debuts new single "Dead" on the Weekly Sonus Hot 100 '
        'at #18.',
      );
    });

    test('weekly Bubbling Under keeps the real position', () {
      expect(
        NewReleaseDebutHeadlines.headline(singleDebut(150)),
        'Madison Beer debuts new single "Dead" on the Weekly Sonus Bubbling '
        'Under at #150.',
      );
    });

    test('career Hot 100 and Bubbling Under', () {
      expect(
        NewReleaseDebutHeadlines.headline(
          singleDebut(1, scope: ChartMomentScope.allTime),
        ),
        'Madison Beer debuts new single "Dead" on the Career Sonus Hot 100 '
        'at #1.',
      );
      expect(
        NewReleaseDebutHeadlines.headline(
          singleDebut(101, scope: ChartMomentScope.allTime),
        ),
        'Madison Beer debuts new single "Dead" on the Career Sonus Bubbling '
        'Under at #101.',
      );
    });

    test('featured artists are named in credit order', () {
      expect(
        NewReleaseDebutHeadlines.headline(
          singleDebut(18),
          featured: const ['Guest One', ' ', 'Guest Two'],
        ),
        'Madison Beer debuts new single "Dead" featuring Guest One and Guest '
        'Two on the Weekly Sonus Hot 100 at #18.',
      );
    });
  });

  group('4.2 new album track headline', () {
    test('weekly Hot 100, neutral phrasing, no ordinal', () {
      expect(
        NewReleaseDebutHeadlines.headline(albumTrackDebut(24)),
        '"For All Eternity" by Tate McRae debuts at #24 on the Weekly Sonus '
        'Hot 100 from the new album Anatomy of a Popstar.',
      );
    });

    test('weekly Bubbling Under and career charts', () {
      expect(
        NewReleaseDebutHeadlines.headline(albumTrackDebut(187)),
        '"For All Eternity" by Tate McRae debuts at #187 on the Weekly Sonus '
        'Bubbling Under from the new album Anatomy of a Popstar.',
      );
      expect(
        NewReleaseDebutHeadlines.headline(
          albumTrackDebut(42, scope: ChartMomentScope.allTime),
        ),
        '"For All Eternity" by Tate McRae debuts at #42 on the Career Sonus '
        'Hot 100 from the new album Anatomy of a Popstar.',
      );
    });

    test('an EP is called an EP', () {
      expect(
        NewReleaseDebutHeadlines.headline(
          albumTrackDebut(24, format: ReleaseFormat.ep),
        ),
        '"For All Eternity" by Tate McRae debuts at #24 on the Weekly Sonus '
        'Hot 100 from the new EP Anatomy of a Popstar.',
      );
    });
  });

  group('safeguards', () {
    test('no ordinal, "studio", certification or gendered pronoun', () {
      final lines = [
        for (final rank in [1, 18, 100, 101, 200])
          for (final scope in [
            ChartMomentScope.finalized,
            ChartMomentScope.allTime,
          ]) ...[
            NewReleaseDebutHeadlines.headline(singleDebut(rank, scope: scope)),
            NewReleaseDebutHeadlines.headline(
              albumTrackDebut(rank, scope: scope),
            ),
          ],
      ];
      final forbidden = RegExp(
        r'\b(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|'
        r'tenth|\d+(st|nd|rd|th)|studio|platinum|gold|certified|her|his|'
        r'their|she|he|they)\b',
        caseSensitive: false,
      );
      for (final line in lines) {
        expect(forbidden.hasMatch(line), isFalse, reason: line);
      }
    });

    test('deterministic: the same debut always gives the same line', () {
      expect(
        NewReleaseDebutHeadlines.headline(singleDebut(18)),
        NewReleaseDebutHeadlines.headline(singleDebut(18)),
      );
    });

    test('drafts only: unapproved and outside the approved families', () {
      expect(NewReleaseDebutHeadlines.approved, isFalse);
      expect(NewReleaseDebutActivation.generationApproved, isFalse);
      // It re-words the existing debut stories, never adds a family.
      expect(NewReleaseDebutHeadlines.replacesFamilies, {
        MomentFamily.songDebutNumberOne,
        MomentFamily.songDebutTop10,
        MomentFamily.songDebut,
        MomentFamily.songBubblingUnderDebut,
      });
      for (final family in NewReleaseDebutHeadlines.replacesFamilies) {
        expect(MomentHeadlines.approvedFamilies, contains(family));
      }
    });
  });
}
