import '../../../library/domain/entities/library_organization.dart';
import '../../../library/domain/entities/release_date.dart';
import 'chart_moment_scope.dart';
import 'new_release_eligibility.dart';

/// The stable record of a song's one published new-release debut story
/// (App Update 1.3, user decision 2026-11-16): the facts and words it was
/// first shown with. Once it exists the story is told from it, never again
/// from the library, so later edits (a renamed song or album, another
/// Single date, the Single switch) cannot rewrite a headline already shown.
///
/// One per song id, written at most once. A future, separately controlled
/// correction would replace the facts in place, raise [revision] and set
/// [correctedAt]; nothing in this build does.
class NewReleasePublication {
  const NewReleasePublication({
    required this.songId,
    required this.storyId,
    required this.eventId,
    required this.eventKey,
    required this.kind,
    required this.scope,
    required this.rank,
    required this.chartName,
    required this.weekStartUtc,
    required this.debutedAtUtc,
    required this.songTitle,
    required this.artistName,
    required this.featuredArtists,
    required this.releaseDate,
    required this.headline,
    required this.publishedAtUtc,
    this.albumId,
    this.albumTitle,
    this.albumFormat,
    this.revision = 1,
    this.correctedAtUtc,
  });

  /// The record of [debut] told with [headline] in the story [storyId],
  /// first shown at [publishedAt].
  factory NewReleasePublication.of(
    NewReleaseDebut debut, {
    required String storyId,
    required String headline,
    required String chartName,
    required List<String> featuredArtists,
    required DateTime publishedAt,
  }) {
    final event = debut.event;
    final albumTrack = debut.kind == NewReleaseDebutKind.albumTrack;
    return NewReleasePublication(
      songId: event.entity.entityId,
      storyId: storyId,
      eventId: event.id,
      eventKey: event.deduplicationKey,
      kind: debut.kind,
      scope: event.scope,
      rank: debut.rank,
      chartName: chartName,
      weekStartUtc: event.weekStartUtc.toUtc(),
      debutedAtUtc: NewReleaseEligibility.effectiveAt(event),
      songTitle: event.entity.title.trim(),
      artistName: event.entity.artistName.trim(),
      featuredArtists: List.unmodifiable(featuredArtists),
      albumId: albumTrack ? debut.albumId : null,
      albumTitle: albumTrack ? debut.albumTitle : null,
      albumFormat: albumTrack ? debut.albumFormat : null,
      releaseDate: debut.releaseDate,
      headline: headline,
      publishedAtUtc: publishedAt.toUtc(),
    );
  }

  /// The song's id: the record follows the song, never its title.
  final String songId;

  /// The feed story it was first shown in.
  final String storyId;

  /// The chart debut it tells: its id and deduplication key.
  final String eventId;
  final String eventKey;

  final NewReleaseDebutKind kind;

  /// Weekly (finalized) or Career (all-time).
  final ChartMomentScope scope;

  /// The position it debuted at, #1–200.
  final int rank;

  /// For example "the Weekly Sonus Hot 100".
  final String chartName;
  final DateTime weekStartUtc;

  /// NewReleaseEligibility.effectiveAt of the debut.
  final DateTime debutedAtUtc;

  /// The credit as shown: title, main artist and featured artists.
  final String songTitle;
  final String artistName;
  final List<String> featuredArtists;

  /// For album and EP tracks only.
  final String? albumId;
  final String? albumTitle;
  final ReleaseFormat? albumFormat;

  /// The date that made it new: the Single's own, or the release's
  /// earliest edition's.
  final ReleaseDate releaseDate;

  /// The words shown.
  final String headline;
  final DateTime publishedAtUtc;

  /// 1 as first published; a correction would raise it.
  final int revision;
  final DateTime? correctedAtUtc;

  /// The headline variant id the story records.
  String get variantId => 'new-release-${kind.name}';

  /// One story per song (NewReleaseEligibility.storyKey).
  String get storyKey => NewReleaseEligibility.songStoryKey(songId);

  @override
  bool operator ==(Object other) =>
      other is NewReleasePublication &&
      other.songId == songId &&
      other.storyId == storyId &&
      other.eventId == eventId &&
      other.eventKey == eventKey &&
      other.kind == kind &&
      other.scope == scope &&
      other.rank == rank &&
      other.chartName == chartName &&
      other.weekStartUtc == weekStartUtc &&
      other.debutedAtUtc == debutedAtUtc &&
      other.songTitle == songTitle &&
      other.artistName == artistName &&
      _sameList(other.featuredArtists, featuredArtists) &&
      other.albumId == albumId &&
      other.albumTitle == albumTitle &&
      other.albumFormat == albumFormat &&
      other.releaseDate == releaseDate &&
      other.headline == headline &&
      other.publishedAtUtc == publishedAtUtc &&
      other.revision == revision &&
      other.correctedAtUtc == correctedAtUtc;

  @override
  int get hashCode => Object.hash(songId, eventKey, headline, revision);

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
