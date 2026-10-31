import '../../domain/models/chart_type.dart';
import '../../domain/services/chart_ranking_engine.dart';
import 'moment_facts.dart';
import 'moment_family.dart';
import 'moment_headlines.dart';
import 'moment_publisher.dart';
import 'moment_story_planner.dart';

/// A refined-only rewording of a catalog headline (SN-50 editorial contract
/// §5). The line keeps its id and its place in the family; only stories told
/// under the refined rules use the new text. The legacy line is never
/// edited, so stories published before the refined rules keep their words.
class RefinedOverride {
  const RefinedOverride(
    this.id,
    this.build, {
    this.requires,
    this.when,
    required this.approved,
  });

  final String id;
  final String Function(MomentFacts f) build;

  /// Applies only to stories where this holds (always when null);
  /// otherwise the line keeps its catalog text.
  final bool Function(MomentFacts f)? when;

  /// The facts the new text needs; the legacy line's when null.
  final Set<MomentFact>? requires;

  /// Only approved changes take effect.
  final bool approved;
}

/// A catalog headline left out of refined stories, whenever [when] holds
/// (always when null).
class RefinedExclusion {
  const RefinedExclusion(this.id, {this.when, required this.approved});

  final String id;
  final bool Function(MomentFacts f)? when;
  final bool approved;
}

/// A headline only refined stories can use, placed after the family's
/// catalog lines.
class RefinedAddition {
  const RefinedAddition(
    this.family,
    this.variant, {
    this.when,
    required this.approved,
  });

  final MomentFamily family;
  final HeadlineVariant variant;

  /// Offered only to stories where this holds (always when null).
  final bool Function(MomentFacts f)? when;
  final bool approved;
}

/// The headlines of stories told under the refined Moments rules: the
/// catalog ([MomentHeadlines.legacyOf]) with approved overrides applied in
/// place, approved exclusions removed and approved additions appended.
///
/// Stories under the earlier rules never read this. Unapproved entries
/// have no effect anywhere.
class RefinedHeadlineCatalog {
  const RefinedHeadlineCatalog({
    this.overrides = const [],
    this.exclusions = const [],
    this.additions = const [],
  });

  /// The app's refined changes. Each entry needs its own editorial
  /// approval (SN50_Final_Editorial_Approval_and_Implementation_Contract.md).
  static final RefinedHeadlineCatalog standard = RefinedHeadlineCatalog(
    overrides: [
      // P-007 to P-009 (Batch 1): finished weeks are never "this week".
      RefinedOverride(
        'song-gainer-d6',
        (f) =>
            'No song climbed further in the chart week than ${f.subject}, '
            'up ${f.places} places to #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'song-gainer-p6',
        (f) =>
            '${f.work} leads every climber of the chart week, rising '
            '${f.places} places to #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'artist-sim-p4',
        (f) =>
            '${f.artist} lands ${f.count} songs in the Top ${f.threshold} of '
            '${f.chart}.',
        approved: true,
      ),
      // P-001, P-002 (Batch 2): "a first", never "its" for people; full credit.
      RefinedOverride(
        'artist-hot100-d5',
        (f) =>
            '${f.subject} gives ${f.ownerName} a first Sonus Hot 100 entry, '
            'at #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'artist-1-d6',
        (f) => '${f.subject} gives ${f.ownerName} a first #1 on ${f.chart}.',
        approved: true,
      ),
      // P-010: the rank, not the streams, is the entry.
      RefinedOverride(
        'artist-hot100-p4',
        (f) =>
            '${f.careerArtist} cracks the Sonus Hot 100 for the first time: '
            '${f.work} enters at #${f.rank} with ${f.streamsText}.',
        approved: true,
      ),
      // P-011, P-012: no name or count said twice.
      RefinedOverride(
        'artist-top-p3',
        (f) =>
            'Head to head with ${f.rivalTitle}, ${f.title} pulls ahead as your '
            '#1 artist.',
        approved: true,
      ),
      RefinedOverride(
        'artist-sim-p2',
        (f) =>
            '${f.count} songs, one artist: ${f.artist} is all over the Top '
            '${f.threshold}.',
        approved: true,
      ),
      // P-013 to P-019: "#1" said once.
      RefinedOverride(
        'artist-1-d1',
        (f) =>
            '${f.careerArtist} earns a first #1 hit as ${f.work} tops ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'artist-1-n-d1',
        (f) =>
            '${f.careerArtist} earns ${f.aOrdinalText} #1 hit as ${f.work} '
            'tops ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'artist-release-1-d1',
        (f) =>
            '${f.careerArtist} earns a first #1 ${f.releaseWord} as '
            '${f.title} tops ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'artist-release-1-n-d1',
        (f) =>
            '${f.careerArtist} earns ${f.aOrdinalText} #1 release as '
            '${f.title} tops ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-debut-1-d6',
        (f) =>
            'A #1 debut for ${f.artist}: the ${f.releaseWord} ${f.title} '
            'opens at the top of ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-debut-1-p5',
        (f) => 'New ${f.releaseWord}, new #1: ${f.subject} debuts at the top.',
        approved: true,
      ),
      RefinedOverride(
        'release-debut-1-p6',
        (f) =>
            '${f.artist} lands a #1 debut: ${f.title} enters ${f.chart} at '
            'the very top.',
        approved: true,
      ),
      // P-020 to P-023: PulsePop voice.
      RefinedOverride(
        'song-debut-10-p4',
        (f) =>
            'Out of the gate with ${f.streamsText}, ${f.subject} debuts in '
            'the Top 10 at #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'song-1-p4',
        (f) => '${f.streamsText} and the top spot: ${f.subject} hits #1!',
        approved: true,
      ),
      RefinedOverride(
        'song-debut-p6',
        (f) =>
            'New arrival alert: ${f.subject} makes its debut at #${f.rank} on '
            '${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-debut-p3',
        (f) =>
            'Straight onto the chart: ${f.subject} enters at #${f.rank} with '
            '${f.streamsText}.',
        approved: true,
      ),
      // P-024 to P-050 (Batch 3): release lines that copied a song line word
      // for word now name the release (F-Q29).
      RefinedOverride(
        'release-debut-1-d1',
        (f) => '${f.subject} opens its chart run at #1 on ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-debut-1-d3',
        (f) =>
            'The ${f.releaseWord} ${f.subject} debuts at #1 on ${f.chart} with '
            '${f.streamsText}.',
        approved: true,
      ),
      RefinedOverride(
        'release-debut-d1',
        (f) =>
            'The ${f.releaseWord} ${f.subject} debuts at #${f.rank} on ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-debut-d3',
        (f) =>
            'The ${f.releaseWord} ${f.subject} opens at #${f.rank} with '
            '${f.streamsText}.',
        approved: true,
      ),
      RefinedOverride(
        'release-1-d1',
        (f) => 'The ${f.releaseWord} ${f.subject} reaches #1 on ${f.chart}.',
        approved: true,
      ),
      // P-029 (revised): never implies the rival had the same format.
      RefinedOverride(
        'release-1-d2',
        (f) =>
            '${f.subject} succeeds ${f.rivalSubject} at #1 on ${f.chart}, the new '
            '#1 ${f.releaseWord}.',
        approved: true,
      ),
      RefinedOverride(
        'release-1-d3',
        (f) =>
            '${f.subject} rises from #${f.previousRank} to become the #1 '
            '${f.releaseWord} on ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-1-d4',
        (f) =>
            '${f.subject} tops ${f.chart} with ${f.streamsText}, the new #1 '
            '${f.releaseWord}.',
        approved: true,
      ),
      RefinedOverride(
        'release-1-again-d1',
        (f) => 'The ${f.releaseWord} ${f.subject} returns to #1 on ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-1-again-d2',
        (f) =>
            '${f.subject} is the #1 ${f.releaseWord} again, taking over from '
            '${f.rivalSubject}.',
        approved: true,
      ),
      RefinedOverride(
        'release-1-again-p1',
        (f) =>
            'Back at #1! The ${f.releaseWord} ${f.subject} reclaims the top spot.',
        approved: true,
      ),
      RefinedOverride(
        'release-1-again-p5',
        (f) =>
            'Once more at #1: ${MomentFacts.possessive(f.artist)} '
            '${f.releaseWord} ${f.title} heads ${f.chart} again.',
        approved: true,
      ),
      RefinedOverride(
        'release-peak-d1',
        (f) =>
            'The ${f.releaseWord} ${f.subject} reaches a new peak of #${f.rank} '
            'on ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-peak-d4',
        (f) =>
            'The ${f.releaseWord} ${f.subject} enters the Top ${f.threshold} at '
            '#${f.rank} on ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-peak-d5',
        (f) =>
            'With ${f.streamsText}, the ${f.releaseWord} ${f.subject} hits a new '
            'peak of #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'release-peak-d6',
        (f) =>
            '${f.subject} moves from #${f.previousRank} to #${f.rank}, a new peak '
            'for the ${f.releaseWord}.',
        approved: true,
      ),
      RefinedOverride(
        'release-peak-p1',
        (f) =>
            'New peak for the ${f.releaseWord}! ${f.subject} climbs to #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'release-peak-p5',
        (f) =>
            '${f.streamsText} and a new peak: the ${f.releaseWord} ${f.subject} '
            'reaches #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'release-reentry-d1',
        (f) =>
            'The ${f.releaseWord} ${f.subject} re-enters ${f.chart} at #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'release-reentry-d2',
        (f) =>
            'Back on ${f.chart}: the ${f.releaseWord} ${f.subject} returns at '
            '#${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'release-reentry-d4',
        (f) =>
            'The ${f.releaseWord} ${f.subject} returns at #${f.rank}, having '
            'peaked at #${f.previousPeak}.',
        approved: true,
      ),
      RefinedOverride(
        'release-reentry-p1',
        (f) =>
            'The ${f.releaseWord} is back! ${f.subject} re-enters at #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'release-streams-d1',
        (f) =>
            'The ${f.releaseWord} ${f.subject} reaches ${f.milestoneText} on Sonus.',
        approved: true,
      ),
      RefinedOverride(
        'release-streams-d3',
        (f) =>
            'The ${f.releaseWord} ${f.subject} reaches ${f.milestoneText} and '
            'stands at #${f.rank} on ${f.chart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-streams-d6',
        (f) => 'The ${f.releaseWord} ${f.subject} passes ${f.milestoneText}.',
        approved: true,
      ),
      RefinedOverride(
        'release-streams-p1',
        (f) =>
            '${f.milestoneText}! The ${f.releaseWord} ${f.subject} hits a '
            'streaming milestone.',
        approved: true,
      ),
      RefinedOverride(
        'release-streams-p5',
        (f) =>
            'Milestone unlocked: the ${f.releaseWord} ${f.subject} reaches '
            '${f.milestoneText}.',
        approved: true,
      ),
      // Batch 3 attribution: the song's full credit, featured guests included.
      RefinedOverride(
        'song-weeks-p5',
        (f) =>
            '${MomentFacts.weeksText(f.weeks!)} ${f.weeksPlace} for ${f.subject}.',
        approved: true,
      ),
      // Chart-jump lines (CJ-004, CJ-006, CJ-010, CJ-022, CJ-025, CJ-029):
      // same wording with the song's full credit.
      RefinedOverride(
        'song-jump-d4',
        (f) =>
            '${f.subject} rises ${f.places} places to #${f.rank} on the weekly '
            'Sonus Hot 100.',
        approved: true,
      ),
      RefinedOverride(
        'song-jump-d6',
        (f) =>
            '${f.subject} gains ${f.places} places on the weekly Sonus Hot 100 '
            'and reaches #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'song-jump-p4',
        (f) =>
            '${f.subject} soars ${f.places} places to #${f.rank} on the Sonus Hot '
            '100.',
        approved: true,
      ),
      RefinedOverride(
        'song-run-d3',
        (f) =>
            '${f.subject} is up ${f.runPlaces} places over ${f.runWeeks} weeks '
            'on the weekly Sonus Hot 100, now #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'song-run-d6',
        (f) =>
            '${f.subject} keeps climbing the weekly Sonus Hot 100 and reaches '
            '#${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'song-run-p4',
        (f) =>
            '${f.subject} is on a run, up ${f.runPlaces} spots in ${f.runWeeks} '
            'weeks to #${f.rank}.',
        approved: true,
      ),
      // BU-001, BU-002 (Batch 4): a first Hot 100 entry from Bubbling Under
      // names both charts and never reads as a Hot 100 climb.
      RefinedOverride(
        'song-break-p3',
        (f) =>
            'Previously #${f.previousRank} on Sonus Bubbling Under, '
            '${f.work} enters the Sonus Hot 100 at #${f.rank}.',
        when: _fromBubblingUnder,
        approved: true,
      ),
      RefinedOverride(
        'song-break-d2',
        (f) =>
            '${f.subject} enters the Sonus Hot 100 at #${f.rank}, from '
            '#${f.previousRank} on Sonus Bubbling Under in the preceding '
            'chart week.',
        when: _weeklyFromBubblingUnder,
        approved: true,
      ),
      // Batch 6 (contract §6.2): songFirstThreshold, releaseFirstThreshold.
      RefinedOverride(
        'song-zone-d2',
        (f) =>
            'First time in the Top ${f.threshold} of ${f.scopedChart}: ${f.subject} is at #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'song-zone-p1',
        (f) =>
            'Into the Top ${f.threshold}! ${f.subject} gets there for the first time, at #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'song-zone-p2',
        (f) =>
            '${f.work} cracks the Top ${f.threshold} for the first time, at #${f.rank}.',
        approved: true,
      ),
      RefinedOverride(
        'release-zone-p1',
        (f) =>
            '${f.title} reaches the Top ${f.threshold} for the first time, at #${f.rank}!',
        approved: true,
      ),
      // Batch 7 (contract §6.2): songSelfReplacement, releaseSelfReplacement.
      RefinedOverride(
        'release-self-1-d1',
        (f) =>
            '${f.careerArtist} replaces ${f.rivalWork} with the ${f.releaseWord} ${f.title} at #1 on ${f.scopedChart}.',
        approved: true,
      ),
      RefinedOverride(
        'release-self-1-p1',
        (f) =>
            '${f.careerArtist} follows one #1 release with another: the ${f.releaseWord} ${f.title} replaces ${f.rivalWork}.',
        approved: true,
      ),
      // Batch 8 (contract §6.2): artistRepeatNumberOne, artistRepeatNumberOneRelease, artistSimultaneousReleases.
      RefinedOverride(
        'artist-repeat-1-p1',
        (f) =>
            'That\'s ${f.aOrdinalText} #1 song for ${f.careerArtist}: ${f.work} tops the weekly Sonus Hot 100!',
        approved: true,
      ),
      RefinedOverride(
        'artist-release-repeat-1-p1',
        (f) =>
            '${f.careerArtist} collects ${f.aOrdinalText} #1 release with the ${f.releaseWord} ${f.title}!',
        approved: true,
      ),
    ],
    exclusions: [
      // Contract §6.4 (Batch 2): lines that name the song by its primary
      // artist alone, which would leave a featured guest out.
      RefinedExclusion('song-debut-1-p4', when: _hasGuest, approved: true),
      RefinedExclusion('song-debut-10-p6', when: _hasGuest, approved: true),
      RefinedExclusion('song-debut-p2', when: _hasGuest, approved: true),
      RefinedExclusion('song-bu-debut-p2', when: _hasGuest, approved: true),
      RefinedExclusion('song-bu-debut-p5', when: _hasGuest, approved: true),
      RefinedExclusion('song-break-d5', when: _hasGuest, approved: true),
      RefinedExclusion('song-peak-p2', when: _hasGuest, approved: true),
      RefinedExclusion('song-repeak-d5', when: _hasGuest, approved: true),
      RefinedExclusion('song-climb-d5', when: _hasGuest, approved: true),
      RefinedExclusion('song-gainer-d5', when: _hasGuest, approved: true),
      RefinedExclusion('song-reentry-d5', when: _hasGuest, approved: true),
      RefinedExclusion('song-streams-d4', when: _hasGuest, approved: true),
      RefinedExclusion('song-streams-p6', when: _hasGuest, approved: true),
      RefinedExclusion('artist-top10-d5', when: _hasGuest, approved: true),
      // P-051 (Batch 2): "<artist> cracks the Sonus Hot 100" reads as the
      // artist's first entry. A refined career story is told this way only
      // when the artist already had one (an artist's first entry gets its
      // own story), and weekly stories can't verify it, so refined stories
      // never use it.
      RefinedExclusion('song-break-p4', approved: true),
      // Batch 4: the catalog wording of song-break-p3 ("jumps from") and
      // song-break-d2 ("climbs from") never reaches a refined story that
      // BU-001 or BU-002 does not cover.
      RefinedExclusion(
        'song-break-p3',
        when: _notFromBubblingUnder,
        approved: true,
      ),
      RefinedExclusion(
        'song-break-d2',
        when: _notWeeklyFromBubblingUnder,
        approved: true,
      ),
    ],
    additions: [
      // Batch 8 (contract §6.2): artistRepeatNumberOne, artistRepeatNumberOneRelease, artistSimultaneousReleases.
      RefinedAddition(
        MomentFamily.artistRepeatNumberOne,
        HeadlineVariant(
          'artist-repeat-1-d2',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.work} takes #1 on ${f.scopedChart}, ${f.aOrdinalText} #1 song there for ${f.careerArtist}.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOne,
        HeadlineVariant(
          'artist-repeat-1-d3',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.careerArtist} collects ${f.aOrdinalText} #1 on ${f.scopedChart} with ${f.work}.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOne,
        HeadlineVariant(
          'artist-repeat-1-d4',
          MomentPublisher.sonusDaily,
          (f) =>
              'With ${f.work} at the top, ${f.careerArtist} now has ${f.ordinal} #1 songs on ${f.scopedChart}.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOne,
        HeadlineVariant(
          'artist-repeat-1-d5',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.work} is ${MomentFacts.possessive(f.careerArtist)} ${f.ordinalText} #1 song on ${f.scopedChart}.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOne,
        HeadlineVariant(
          'artist-repeat-1-d6',
          MomentPublisher.sonusDaily,
          (f) =>
              'The weekly Sonus Hot 100 has a new #1 in ${f.work}, ${f.aOrdinalText} #1 song for ${f.careerArtist}.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOne,
        HeadlineVariant(
          'artist-repeat-1-p2',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.careerArtist} is back on top with ${f.aOrdinalText} #1 song: ${f.work}!',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOne,
        HeadlineVariant(
          'artist-repeat-1-p3',
          MomentPublisher.pulsePop,
          (f) =>
              'Another one! ${f.work} gives ${f.careerArtist} ${f.aOrdinalText} #1 song.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOne,
        HeadlineVariant(
          'artist-repeat-1-p4',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.careerArtist} does it again: ${f.work} hits #1 on the weekly Sonus Hot 100.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOne,
        HeadlineVariant(
          'artist-repeat-1-p5',
          MomentPublisher.pulsePop,
          (f) =>
              '#1 again for ${f.careerArtist}! This time it\'s ${f.work}, the artist\'s ${f.ordinalText} #1 song.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOne,
        HeadlineVariant(
          'artist-repeat-1-p6',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.careerArtist} adds another #1 song: ${f.work} takes the top spot!',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOneRelease,
        HeadlineVariant(
          'artist-release-repeat-1-d2',
          MomentPublisher.sonusDaily,
          (f) =>
              'The ${f.releaseWord} ${f.title} is ${MomentFacts.possessive(f.careerArtist)} ${f.ordinalText} release to reach #1 on ${f.scopedChart}.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOneRelease,
        HeadlineVariant(
          'artist-release-repeat-1-d3',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.careerArtist} now counts ${f.ordinal} #1 releases on ${f.scopedChart}, the latest being the ${f.releaseWord} ${f.title}.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOneRelease,
        HeadlineVariant(
          'artist-release-repeat-1-d4',
          MomentPublisher.sonusDaily,
          (f) =>
              '${MomentFacts.possessive(f.careerArtist)} ${f.ordinalText} #1 release on ${f.scopedChart} is the ${f.releaseWord} ${f.title}.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOneRelease,
        HeadlineVariant(
          'artist-release-repeat-1-d5',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.title} takes #1 on ${f.scopedChart}, adding ${f.aOrdinalText} #1 release to ${MomentFacts.possessive(f.careerArtist)} record.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOneRelease,
        HeadlineVariant(
          'artist-release-repeat-1-d6',
          MomentPublisher.sonusDaily,
          (f) =>
              'The ${f.releaseWord} ${f.title} becomes ${MomentFacts.possessive(f.careerArtist)} latest #1 release on ${f.scopedChart}, the ${f.ordinalText} in all.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOneRelease,
        HeadlineVariant(
          'artist-release-repeat-1-p2',
          MomentPublisher.pulsePop,
          (f) =>
              'Back at #1! ${f.careerArtist} returns to the top of the Sonus Albums & EPs chart with ${f.title}.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOneRelease,
        HeadlineVariant(
          'artist-release-repeat-1-p3',
          MomentPublisher.pulsePop,
          (f) =>
              '#1 again! ${f.title} hands ${f.careerArtist} ${f.aOrdinalText} chart-topping release.',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOneRelease,
        HeadlineVariant(
          'artist-release-repeat-1-p4',
          MomentPublisher.pulsePop,
          (f) =>
              'Another #1 release for ${f.careerArtist}: the ${f.releaseWord} ${f.title} takes the top spot!',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOneRelease,
        HeadlineVariant(
          'artist-release-repeat-1-p5',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.title} makes it ${f.ordinal} #1 releases for ${f.careerArtist}!',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistRepeatNumberOneRelease,
        HeadlineVariant(
          'artist-release-repeat-1-p6',
          MomentPublisher.pulsePop,
          (f) =>
              'Chart-topper number ${f.ordinal} for ${f.careerArtist}: the ${f.releaseWord} ${f.title} is #1!',
          requires: const {MomentFact.rank, MomentFact.ordinal},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistSimultaneousReleases,
        HeadlineVariant(
          'artist-sim-release-d3',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.artist} holds ${f.count} places in the Top ${f.threshold} of ${f.scopedChart}.',
          requires: const {MomentFact.count, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistSimultaneousReleases,
        HeadlineVariant(
          'artist-sim-release-d4',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.count} of the Top ${f.threshold} releases on ${f.scopedChart} are by ${f.artist}.',
          requires: const {MomentFact.count, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistSimultaneousReleases,
        HeadlineVariant(
          'artist-sim-release-d5',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.artist} places ${f.count} releases in the Top ${f.threshold} of ${f.scopedChart}.',
          requires: const {MomentFact.count, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistSimultaneousReleases,
        HeadlineVariant(
          'artist-sim-release-d6',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.artist} appears ${f.count} times in the Top ${f.threshold} of ${f.scopedChart}.',
          requires: const {MomentFact.count, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistSimultaneousReleases,
        HeadlineVariant(
          'artist-sim-release-p2',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.count} at once! ${f.artist} crowds the Top ${f.threshold}.',
          requires: const {MomentFact.count, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistSimultaneousReleases,
        HeadlineVariant(
          'artist-sim-release-p3',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.artist} is everywhere: ${f.count} releases in the Top ${f.threshold}!',
          requires: const {MomentFact.count, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistSimultaneousReleases,
        HeadlineVariant(
          'artist-sim-release-p4',
          MomentPublisher.pulsePop,
          (f) =>
              'Top ${f.threshold} takeover: ${f.count} releases from ${f.artist}.',
          requires: const {MomentFact.count, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistSimultaneousReleases,
        HeadlineVariant(
          'artist-sim-release-p5',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.artist} stacks the Top ${f.threshold} with ${f.count} releases at the same time.',
          requires: const {MomentFact.count, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.artistSimultaneousReleases,
        HeadlineVariant(
          'artist-sim-release-p6',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.artist} fills ${f.count} Top ${f.threshold} slots on ${f.scopedChart} at once!',
          requires: const {MomentFact.count, MomentFact.threshold},
        ),
        approved: true,
      ),
      // Batch 7 (contract §6.2): songSelfReplacement, releaseSelfReplacement.
      RefinedAddition(
        MomentFamily.songSelfReplacement,
        HeadlineVariant(
          'song-self-1-d3',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.careerArtist} holds #1 on ${f.scopedChart} as ${f.work} succeeds ${f.rivalWork}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songSelfReplacement,
        HeadlineVariant(
          'song-self-1-d4',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.work} replaces ${f.rivalWork} at #1 on ${f.scopedChart}; both songs are by ${f.careerArtist}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songSelfReplacement,
        HeadlineVariant(
          'song-self-1-d5',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.careerArtist} has a new #1 on ${f.scopedChart}: ${f.work} takes over from ${f.rivalWork}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songSelfReplacement,
        HeadlineVariant(
          'song-self-1-d6',
          MomentPublisher.sonusDaily,
          (f) =>
              '#1 on ${f.scopedChart} stays with ${f.careerArtist}, as ${f.work} replaces ${f.rivalWork}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songSelfReplacement,
        HeadlineVariant(
          'song-self-1-p3',
          MomentPublisher.pulsePop,
          (f) =>
              '#1 swap, same artist: ${f.work} takes over from ${f.rivalWork} for ${f.careerArtist}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songSelfReplacement,
        HeadlineVariant(
          'song-self-1-p4',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.work} bumps ${f.rivalWork} from #1, and ${f.careerArtist} keeps the top spot!',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songSelfReplacement,
        HeadlineVariant(
          'song-self-1-p5',
          MomentPublisher.pulsePop,
          (f) =>
              'Still #1, new song: ${f.careerArtist} trades ${f.rivalWork} for ${f.work} at the top.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songSelfReplacement,
        HeadlineVariant(
          'song-self-1-p6',
          MomentPublisher.pulsePop,
          (f) =>
              'One ${f.careerArtist} #1 makes way for another: ${f.work} succeeds ${f.rivalWork}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseSelfReplacement,
        HeadlineVariant(
          'release-self-1-d2',
          MomentPublisher.sonusDaily,
          (f) =>
              'The ${f.releaseWord} ${f.title} succeeds ${f.rivalWork} at #1 on ${f.scopedChart}, keeping the top spot with ${f.careerArtist}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseSelfReplacement,
        HeadlineVariant(
          'release-self-1-d3',
          MomentPublisher.sonusDaily,
          (f) =>
              'The top of ${f.scopedChart} changes hands within ${MomentFacts.possessive(f.careerArtist)} catalog: ${f.title} is the new #1.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseSelfReplacement,
        HeadlineVariant(
          'release-self-1-d4',
          MomentPublisher.sonusDaily,
          (f) =>
              'On ${f.scopedChart}, ${f.title} takes over at #1 from ${f.rivalWork}, another release by ${f.careerArtist}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseSelfReplacement,
        HeadlineVariant(
          'release-self-1-d5',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.title} is ${MomentFacts.possessive(f.careerArtist)} new #1 ${f.releaseWord} on ${f.scopedChart}, replacing ${f.rivalWork}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseSelfReplacement,
        HeadlineVariant(
          'release-self-1-d6',
          MomentPublisher.sonusDaily,
          (f) =>
              'With the ${f.releaseWord} ${f.title}, ${f.careerArtist} follows ${f.rivalWork} at #1 on ${f.scopedChart}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseSelfReplacement,
        HeadlineVariant(
          'release-self-1-p2',
          MomentPublisher.pulsePop,
          (f) =>
              'New ${f.releaseWord}, same #1 artist: ${f.title} replaces ${f.rivalWork} for ${f.careerArtist}!',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseSelfReplacement,
        HeadlineVariant(
          'release-self-1-p3',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.title} unseats ${f.rivalWork} at #1, and the top spot stays in ${MomentFacts.possessive(f.careerArtist)} hands!',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseSelfReplacement,
        HeadlineVariant(
          'release-self-1-p4',
          MomentPublisher.pulsePop,
          (f) =>
              'Catalog takeover: ${f.careerArtist} swaps one #1 for another with the ${f.releaseWord} ${f.title}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseSelfReplacement,
        HeadlineVariant(
          'release-self-1-p5',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.careerArtist} still rules #1! The ${f.releaseWord} ${f.title} replaces ${f.rivalWork}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseSelfReplacement,
        HeadlineVariant(
          'release-self-1-p6',
          MomentPublisher.pulsePop,
          (f) =>
              'The #1 ${f.releaseWord} is new, the artist isn\'t: ${f.title} by ${f.careerArtist} replaces ${f.rivalWork}.',
          requires: const {MomentFact.rival},
        ),
        approved: true,
      ),
      // Batch 6 (contract §6.2): songFirstThreshold, releaseFirstThreshold.
      RefinedAddition(
        MomentFamily.songFirstThreshold,
        HeadlineVariant(
          'song-zone-d3',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} reaches #${f.rank} on ${f.scopedChart}, its first time in the Top ${f.threshold}.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songFirstThreshold,
        HeadlineVariant(
          'song-zone-d4',
          MomentPublisher.sonusDaily,
          (f) =>
              'A first Top ${f.threshold} position for ${f.subject}: #${f.rank} on ${f.scopedChart}.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songFirstThreshold,
        HeadlineVariant(
          'song-zone-d5',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} moves into the Top ${f.threshold} of ${f.scopedChart} at #${f.rank}, a first for the song.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        when: _climbed,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songFirstThreshold,
        HeadlineVariant(
          'song-zone-d6',
          MomentPublisher.sonusDaily,
          (f) =>
              'At #${f.rank}, ${f.subject} is inside the Top ${f.threshold} of ${f.scopedChart} for the first time.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songFirstThreshold,
        HeadlineVariant(
          'song-zone-p3',
          MomentPublisher.pulsePop,
          (f) =>
              'Hello, Top ${f.threshold}! ${f.work} makes it in at #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songFirstThreshold,
        HeadlineVariant(
          'song-zone-p4',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.work} breaks new ground at #${f.rank}: a first Top ${f.threshold} spot.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songFirstThreshold,
        HeadlineVariant(
          'song-zone-p5',
          MomentPublisher.pulsePop,
          (f) =>
              'New territory for ${f.work}: #${f.rank} and a place in the Top ${f.threshold}.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songFirstThreshold,
        HeadlineVariant(
          'song-zone-p6',
          MomentPublisher.pulsePop,
          (f) =>
              'Top ${f.threshold}, unlocked: ${f.subject} lands at #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseFirstThreshold,
        HeadlineVariant(
          'release-zone-d2',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} earns its first Top ${f.threshold} position, at #${f.rank} on ${f.scopedChart}.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseFirstThreshold,
        HeadlineVariant(
          'release-zone-d3',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} is now a Top ${f.threshold} ${f.releaseWord}: it reaches #${f.rank} on ${f.scopedChart}, a first.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseFirstThreshold,
        HeadlineVariant(
          'release-zone-d4',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} moves into the Top ${f.threshold} of ${f.scopedChart} at #${f.rank}, the ${f.releaseWord}\'s first time there.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        when: _climbed,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseFirstThreshold,
        HeadlineVariant(
          'release-zone-d5',
          MomentPublisher.sonusDaily,
          (f) =>
              'At #${f.rank}, the ${f.releaseWord} ${f.subject} enters the Top ${f.threshold} of ${f.scopedChart} for the first time.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseFirstThreshold,
        HeadlineVariant(
          'release-zone-d6',
          MomentPublisher.sonusDaily,
          (f) =>
              'For the ${f.releaseWord} ${f.subject}, #${f.rank} on ${f.scopedChart} means a first Top ${f.threshold} placing.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseFirstThreshold,
        HeadlineVariant(
          'release-zone-p2',
          MomentPublisher.pulsePop,
          (f) =>
              'Top ${f.threshold} for the ${f.releaseWord}! ${f.subject} arrives at #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseFirstThreshold,
        HeadlineVariant(
          'release-zone-p3',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.title} breaks into the Top ${f.threshold} at #${f.rank}, a first for the ${f.releaseWord}.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseFirstThreshold,
        HeadlineVariant(
          'release-zone-p4',
          MomentPublisher.pulsePop,
          (f) =>
              'New high-water mark: the ${f.releaseWord} ${f.title} enters the Top ${f.threshold} at #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseFirstThreshold,
        HeadlineVariant(
          'release-zone-p5',
          MomentPublisher.pulsePop,
          (f) =>
              '${MomentFacts.possessive(f.artist)} ${f.releaseWord} ${f.title} makes the Top ${f.threshold} for the first time, at #${f.rank}!',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.releaseFirstThreshold,
        HeadlineVariant(
          'release-zone-p6',
          MomentPublisher.pulsePop,
          (f) =>
              'First Top ${f.threshold} spot for ${f.title}: the ${f.releaseWord} lands at #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.threshold},
        ),
        approved: true,
      ),
      // BU-020 to BU-031 (Batch 5): falls of 30+ within Bubbling Under.
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-d1',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} falls from #${f.previousRank} to #${f.rank} on the '
              'weekly Sonus Bubbling Under.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-d2',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} drops ${f.placesDown} places on the weekly Sonus '
              'Bubbling Under, to #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.placesDown},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-d3',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} slips to #${f.rank} on the weekly Sonus Bubbling '
              'Under, down from #${f.previousRank}.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-d4',
          MomentPublisher.sonusDaily,
          (f) =>
              'A ${f.placesDown}-place fall on the weekly Sonus Bubbling Under '
              'takes ${f.subject} to #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.placesDown},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-d5',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} moves down the weekly Sonus Bubbling Under, from '
              '#${f.previousRank} to #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-d6',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} loses ${f.placesDown} places on the weekly Sonus '
              'Bubbling Under and sits at #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.placesDown},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-p1',
          MomentPublisher.pulsePop,
          (f) =>
              'Down ${f.placesDown}: ${f.work} slides to #${f.rank} on Sonus '
              'Bubbling Under.',
          requires: const {MomentFact.rank, MomentFact.placesDown},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-p2',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.work} takes a tumble on Sonus Bubbling Under, from '
              '#${f.previousRank} to #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-p3',
          MomentPublisher.pulsePop,
          (f) =>
              'Rough week for ${f.subject}: down to #${f.rank} on Sonus '
              'Bubbling Under.',
          requires: const {MomentFact.rank},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-p4',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.work} drops ${f.placesDown} spots to #${f.rank} on Sonus '
              'Bubbling Under.',
          requires: const {MomentFact.rank, MomentFact.placesDown},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-p5',
          MomentPublisher.pulsePop,
          (f) =>
              'From #${f.previousRank} to #${f.rank}: ${f.work} loses ground on '
              'Sonus Bubbling Under.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songBubblingUnderFall,
        HeadlineVariant(
          'song-bu-fall-p6',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.subject} slips ${f.placesDown} places on Sonus Bubbling '
              'Under, now at #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.placesDown},
        ),
        when: _bubblingUnderFall,
        approved: true,
      ),
      // BU-040 to BU-051 (Batch 5): notable exits into Bubbling Under.
      // Both ranks are positions on two charts, never a place count.
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-d1',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} leaves the Sonus Hot 100 and is #${f.rank} on the '
              'weekly Sonus Bubbling Under.',
          requires: const {MomentFact.rank},
        ),
        when: _hot100Exit,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-d2',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} slips from #${f.previousRank} on the Sonus Hot 100 '
              'to #${f.rank} on Sonus Bubbling Under.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _hot100Exit,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-d3',
          MomentPublisher.sonusDaily,
          (f) =>
              'Once #${f.previousPeak} on the Sonus Hot 100, ${f.subject} moves '
              'to Sonus Bubbling Under at #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.previousPeak},
        ),
        when: _hot100ExitAfterTop40Peak,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-d4',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} exits the Sonus Hot 100 after peaking at '
              '#${f.previousPeak}; it is now #${f.rank} on Sonus Bubbling '
              'Under.',
          requires: const {MomentFact.rank, MomentFact.previousPeak},
        ),
        when: _hot100ExitAfterTop40Peak,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-d5',
          MomentPublisher.sonusDaily,
          (f) =>
              'After its Sonus Hot 100 run, ${f.subject} continues on Sonus '
              'Bubbling Under at #${f.rank}.',
          requires: const {MomentFact.rank},
        ),
        when: _hot100Exit,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-d6',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} drops out of the Sonus Hot 100, to #${f.rank} on '
              'Sonus Bubbling Under.',
          requires: const {MomentFact.rank},
        ),
        when: _hot100Exit,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-p1',
          MomentPublisher.pulsePop,
          (f) =>
              'Out of the Sonus Hot 100: ${f.work} drops to #${f.rank} on Sonus '
              'Bubbling Under.',
          requires: const {MomentFact.rank},
        ),
        when: _hot100Exit,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-p2',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.work} says goodbye to the Sonus Hot 100 and lands at '
              '#${f.rank} on Sonus Bubbling Under.',
          requires: const {MomentFact.rank},
        ),
        when: _hot100Exit,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-p3',
          MomentPublisher.pulsePop,
          (f) =>
              'A #${f.previousPeak} peak behind it, ${f.subject} slides to Sonus '
              'Bubbling Under at #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.previousPeak},
        ),
        when: _hot100ExitAfterTop40Peak,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-p4',
          MomentPublisher.pulsePop,
          (f) =>
              '${f.work} falls from #${f.previousRank} on the Sonus Hot 100 to '
              '#${f.rank} on Sonus Bubbling Under.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _hot100Exit,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-p5',
          MomentPublisher.pulsePop,
          (f) =>
              'Hot 100 exit: ${f.subject} is now #${f.rank} on Sonus Bubbling '
              'Under.',
          requires: const {MomentFact.rank},
        ),
        when: _hot100Exit,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Exit,
        HeadlineVariant(
          'song-exit-p6',
          MomentPublisher.pulsePop,
          (f) =>
              'A Sonus Hot 100 run comes to an end: ${f.work} is now #${f.rank} '
              'on Sonus Bubbling Under.',
          requires: const {MomentFact.rank},
        ),
        when: _hot100Exit,
        approved: true,
      ),
      // BU-010 to BU-015 (Batch 4). "The week before" lines are weekly only.
      RefinedAddition(
        MomentFamily.songHot100Breakthrough,
        HeadlineVariant(
          'song-break-d7',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} enters the Sonus Hot 100 at #${f.rank}; the week '
              'before, it was #${f.previousRank} on Sonus Bubbling Under.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _weeklyFromBubblingUnder,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Breakthrough,
        HeadlineVariant(
          'song-break-d8',
          MomentPublisher.sonusDaily,
          (f) =>
              'After #${f.previousRank} on Sonus Bubbling Under, ${f.subject} '
              'makes its Sonus Hot 100 debut at #${f.rank}.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _fromBubblingUnder,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Breakthrough,
        HeadlineVariant(
          'song-break-d9',
          MomentPublisher.sonusDaily,
          (f) =>
              '${f.subject} debuts on the Sonus Hot 100 at #${f.rank}, having '
              'been #${f.previousRank} on Sonus Bubbling Under the week '
              'before.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _weeklyFromBubblingUnder,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Breakthrough,
        HeadlineVariant(
          'song-break-p7',
          MomentPublisher.pulsePop,
          (f) =>
              'New to the Sonus Hot 100: ${f.work} arrives at #${f.rank}, '
              'after #${f.previousRank} on Sonus Bubbling Under the week '
              'before.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _weeklyFromBubblingUnder,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Breakthrough,
        HeadlineVariant(
          'song-break-p8',
          MomentPublisher.pulsePop,
          (f) =>
              'From #${f.previousRank} on Sonus Bubbling Under to a Sonus Hot '
              '100 debut at #${f.rank}: ${f.subject} is in.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _fromBubblingUnder,
        approved: true,
      ),
      RefinedAddition(
        MomentFamily.songHot100Breakthrough,
        HeadlineVariant(
          'song-break-p9',
          MomentPublisher.pulsePop,
          (f) =>
              'Hot 100 debut! ${f.work} arrives on the Sonus Hot 100 at '
              '#${f.rank}, having been #${f.previousRank} on Sonus Bubbling '
              'Under the week before.',
          requires: const {MomentFact.rank, MomentFact.previousRank},
        ),
        when: _weeklyFromBubblingUnder,
        approved: true,
      ),
    ],
  );

  final List<RefinedOverride> overrides;
  final List<RefinedExclusion> exclusions;
  final List<RefinedAddition> additions;

  List<HeadlineVariant> of(MomentFamily family, MomentFacts facts) {
    final reworded = {
      for (final override in overrides)
        if (override.approved && (override.when?.call(facts) ?? true))
          override.id: override,
    };
    bool excluded(String id) => exclusions.any(
      (exclusion) =>
          exclusion.approved &&
          exclusion.id == id &&
          (exclusion.when?.call(facts) ?? true),
    );

    return [
      for (final variant in MomentHeadlines.legacyOf(family))
        if (!excluded(variant.id))
          switch (reworded[variant.id]) {
            null => variant,
            final override => HeadlineVariant(
              variant.id,
              variant.publisher,
              override.build,
              requires: override.requires ?? variant.requires,
            ),
          },
      for (final addition in additions)
        if (addition.approved &&
            addition.family == family &&
            (addition.when?.call(facts) ?? true))
          addition.variant,
    ];
  }
}

bool _hasGuest(MomentFacts f) => f.featured != null;

/// A Hot 100 arrival whose previous rank is a Bubbling Under position.
bool _fromBubblingUnder(MomentFacts f) =>
    f.chartType == ChartType.songs &&
    (f.rank ?? 101) <= ChartRankingEngine.officialChartLimit &&
    (f.previousRank ?? 0) > ChartRankingEngine.officialChartLimit;

/// [_fromBubblingUnder] on the weekly chart, where the previous rank is the
/// preceding finalized week's.
bool _weeklyFromBubblingUnder(MomentFacts f) =>
    f.weekly && _fromBubblingUnder(f);

bool _notFromBubblingUnder(MomentFacts f) => !_fromBubblingUnder(f);

/// The story's rank is higher than a known previous one: the song or
/// release really moved up, so movement wording is true.
bool _climbed(MomentFacts f) {
  final before = f.previousRank;
  final now = f.rank;
  return before != null && now != null && before > now;
}

/// A weekly move between two Bubbling Under positions.
bool _bubblingUnderFall(MomentFacts f) =>
    f.weekly &&
    f.chartType == ChartType.songs &&
    (f.previousRank ?? 0) > ChartRankingEngine.officialChartLimit &&
    (f.rank ?? 0) > ChartRankingEngine.officialChartLimit;

/// A weekly move from a Hot 100 position to a Bubbling Under one.
bool _hot100Exit(MomentFacts f) =>
    f.weekly &&
    f.chartType == ChartType.songs &&
    (f.previousRank ?? 101) <= ChartRankingEngine.officialChartLimit &&
    (f.rank ?? 0) > ChartRankingEngine.officialChartLimit;

/// [_hot100Exit] with a verified Top 40 peak to name.
bool _hot100ExitAfterTop40Peak(MomentFacts f) =>
    _hot100Exit(f) &&
    (f.previousPeak ?? 101) <= MomentStoryPlanner.notableExitPeak;

bool _notWeeklyFromBubblingUnder(MomentFacts f) => !_weeklyFromBubblingUnder(f);
