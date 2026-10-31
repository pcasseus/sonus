import 'moment_facts.dart';
import 'moment_family.dart';
import 'moment_headlines.dart';

/// A refined-only rewording of a catalog headline (SN-50 editorial contract
/// §5). The line keeps its id and its place in the family; only stories told
/// under the refined rules use the new text. The legacy line is never
/// edited, so stories published before the refined rules keep their words.
class RefinedOverride {
  const RefinedOverride(
    this.id,
    this.build, {
    this.requires,
    required this.approved,
  });

  final String id;
  final String Function(MomentFacts f) build;

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
  const RefinedAddition(this.family, this.variant, {required this.approved});

  final MomentFamily family;
  final HeadlineVariant variant;
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
    ],
    additions: [],
  );

  final List<RefinedOverride> overrides;
  final List<RefinedExclusion> exclusions;
  final List<RefinedAddition> additions;

  List<HeadlineVariant> of(MomentFamily family, MomentFacts facts) {
    final reworded = {
      for (final override in overrides)
        if (override.approved) override.id: override,
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
        if (addition.approved && addition.family == family) addition.variant,
    ];
  }
}

bool _hasGuest(MomentFacts f) => f.featured != null;
