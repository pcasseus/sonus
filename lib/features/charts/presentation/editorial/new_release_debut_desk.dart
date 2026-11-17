import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/new_release_eligibility.dart';
import 'moment_family.dart';
import 'new_release_debut_headlines.dart';

/// What the library says about a song's release, for new-release debuts
/// (App Update 1.3). Kept apart from MomentLookups so lookups that never
/// tell new-release debuts need nothing new.
abstract interface class NewReleaseLookups {
  /// The song's release facts as stored; null when they are unknown, which
  /// tells no new-release debut.
  NewReleaseSongFacts? newReleaseFactsOf(String songId);
}

/// A debut story re-worded as a new-release debut.
class NewReleaseRewording {
  const NewReleaseRewording(this.debut, this.headline);

  final NewReleaseDebut debut;
  final String headline;

  /// The headline variant id the story records.
  String get variantId => 'new-release-${debut.kind.name}';
}

/// Chooses which debut story, if any, is told as a song's new-release
/// debut (App Update 1.3, user decisions 2026-11-16).
///
/// - One per song across the Weekly and Career charts: the song's first
///   qualifying debut by actual chronology
///   ([NewReleaseEligibility.firstQualifying]); at the same instant the
///   Weekly chart's. The other chart's debut keeps its ordinary story.
/// - Only a debut story is re-worded, in place: same story id and family
///   ([NewReleaseDebutHeadlines.replacesFamilies]). Re-entries, movement
///   and every other story are untouched.
/// - Prospective: only debuts from [start] on.
///
/// Nothing is stored. The choice is made again from stored events on every
/// compose: [storedDebuts] are the song chart debuts stored since the
/// start (read beyond the loaded feed pages), joined with the feed's own
/// events, so restarts and paging give the same choice.
class NewReleaseDebutDesk {
  NewReleaseDebutDesk({
    required this.start,
    required this.lookups,
    Iterable<ChartMomentEvent> storedDebuts = const [],
    this.generationApproved = NewReleaseDebutActivation.generationApproved,
    this.headlinesApproved = NewReleaseDebutHeadlines.approved,
  }) : _storedDebuts = List.unmodifiable(storedDebuts);

  final NewReleaseDebutStart start;
  final NewReleaseLookups lookups;
  final List<ChartMomentEvent> _storedDebuts;

  /// [NewReleaseDebutActivation.generationApproved] outside tests.
  final bool generationApproved;

  /// [NewReleaseDebutHeadlines.approved] outside tests.
  final bool headlinesApproved;

  bool get active =>
      generationApproved && headlinesApproved && start.fromUtc != null;

  /// The first qualifying debut of each song among [items] and the stored
  /// debuts, by song id. Empty while not [active].
  Map<String, ChartMomentEvent> select(Iterable<ChartMomentFeedItem> items) {
    if (!active) return const {};
    return NewReleaseEligibility.firstQualifying(
      [..._storedDebuts, for (final item in items) ...item.events],
      start: start,
      approved: generationApproved,
    );
  }

  /// The new-release wording for the story of [family] told from [item],
  /// when its debut is the one [chosen] for the song and the song's
  /// release qualifies; null otherwise.
  NewReleaseRewording? rewordingFor(
    ChartMomentFeedItem item,
    MomentFamily family,
    Map<String, ChartMomentEvent> chosen, {
    List<String> featured = const [],
  }) {
    if (!active ||
        !NewReleaseDebutHeadlines.replacesFamilies.contains(family)) {
      return null;
    }
    for (final event in item.events) {
      if (event.eventType != ChartMomentEventType.debut) continue;
      final first = chosen[event.entity.entityId];
      if (first == null || first.deduplicationKey != event.deduplicationKey) {
        continue;
      }
      final facts = lookups.newReleaseFactsOf(event.entity.entityId);
      if (facts == null) return null;
      final debut = NewReleaseEligibility.evaluate(event, facts).debut;
      if (debut == null) return null;
      return NewReleaseRewording(
        debut,
        NewReleaseDebutHeadlines.headline(debut, featured: featured),
      );
    }
    return null;
  }
}
