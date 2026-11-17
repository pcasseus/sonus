import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/new_release_eligibility.dart';
import '../../domain/moments/new_release_publication.dart';
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
  const NewReleaseRewording(this.publication, {required this.recorded});

  /// The record the story is told from: stored ([recorded]), or composed
  /// now from the library and to be stored once the story is shown.
  final NewReleasePublication publication;

  /// Whether [publication] is already stored.
  final bool recorded;

  String get headline => publication.headline;

  /// The headline variant id the story records.
  String get variantId => publication.variantId;

  String get storyKey => publication.storyKey;
}

/// Chooses which debut story, if any, is told as a song's new-release
/// debut (App Update 1.3, user decisions 2026-11-16).
///
/// - Published once, then fixed: a song with a stored publication
///   ([publications]) is told from it, at its own debut only, whatever the
///   library says now. Nothing else of the song is ever told as new.
/// - Otherwise one per song across the Weekly and Career charts: the
///   song's first chart appearance by actual chronology
///   ([NewReleaseEligibility.firstDebuts]); at the same instant the
///   Weekly chart's. A song that first charted before the start is never
///   told as new. The other chart's debut keeps its ordinary story.
/// - Only a debut story is re-worded, in place: same story id and family
///   ([NewReleaseDebutHeadlines.replacesFamilies]). Re-entries, movement
///   and every other story are untouched.
/// - Prospective: only debuts from [start] on.
///
/// [storedDebuts] are the song chart debuts stored since the start (read
/// beyond the loaded feed pages) and every earlier appearance of those
/// songs, joined with the feed's own events, so restarts and paging give
/// the same choice.
class NewReleaseDebutDesk {
  NewReleaseDebutDesk({
    required this.start,
    required this.lookups,
    Iterable<ChartMomentEvent> storedDebuts = const [],
    Map<String, NewReleasePublication> publications = const {},
    DateTime Function()? now,
    this.generationApproved = NewReleaseDebutActivation.generationApproved,
    this.headlinesApproved = NewReleaseDebutHeadlines.approved,
  }) : _storedDebuts = List.unmodifiable(storedDebuts),
       _publications = Map.unmodifiable(publications),
       _now = now ?? DateTime.now;

  final NewReleaseDebutStart start;
  final NewReleaseLookups lookups;
  final List<ChartMomentEvent> _storedDebuts;

  /// Stored publications by song id.
  final Map<String, NewReleasePublication> _publications;

  /// When a newly composed story is first shown.
  final DateTime Function() _now;

  /// [NewReleaseDebutActivation.generationApproved] outside tests.
  final bool generationApproved;

  /// [NewReleaseDebutHeadlines.approved] outside tests.
  final bool headlinesApproved;

  bool get active =>
      generationApproved && headlinesApproved && start.fromUtc != null;

  /// The debut of each song that may be told as new, among [items] and the
  /// stored debuts, by song id. Empty while not [active]. A published
  /// song's entry is never used: [rewordingFor] tells its record first.
  Map<String, ChartMomentEvent> select(Iterable<ChartMomentFeedItem> items) {
    if (!active) return const {};
    return NewReleaseEligibility.firstDebuts(
      [..._storedDebuts, for (final item in items) ...item.events],
      start: start,
      approved: generationApproved,
    );
  }

  /// The new-release wording for the story of [family] told from [item]:
  /// from the song's publication when its debut is the one published;
  /// otherwise, when its debut is the one [chosen] for an unpublished song
  /// and the song's release qualifies, composed now. Null otherwise.
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
      final songId = event.entity.entityId;
      final published = _publications[songId];
      if (published != null) {
        if (published.eventKey != event.deduplicationKey) continue;
        return NewReleaseRewording(published, recorded: true);
      }
      final first = chosen[songId];
      if (first == null || first.deduplicationKey != event.deduplicationKey) {
        continue;
      }
      final facts = lookups.newReleaseFactsOf(songId);
      if (facts == null) return null;
      final debut = NewReleaseEligibility.evaluate(event, facts).debut;
      if (debut == null) return null;
      final credited = [
        for (final name in featured)
          if (name.trim().isNotEmpty) name.trim(),
      ];
      return NewReleaseRewording(
        NewReleasePublication.of(
          debut,
          storyId: item.id,
          headline: NewReleaseDebutHeadlines.headline(
            debut,
            featured: credited,
          ),
          chartName: NewReleaseDebutHeadlines.chartName(debut),
          featuredArtists: credited,
          publishedAt: _now(),
        ),
        recorded: false,
      );
    }
    return null;
  }
}
