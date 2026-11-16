import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/library_organization.dart';
import '../../../library/domain/entities/release_date.dart';
import '../models/chart_type.dart';
import '../services/chart_ranking_engine.dart';
import 'chart_moment_event.dart';
import 'chart_moment_event_type.dart';
import 'chart_moment_scope.dart';

/// New-release debuts (App Update 1.3, proposed): a song chart debut told
/// as a new Single's or a new album track's debut.
///
/// SWITCHED OFF. Nothing here is wired into the editorial desk, the
/// planner or the feed; nothing is recorded or stored. Telling these
/// stories needs the wording approved ([generationApproved]) and a
/// prospective start ([NewReleaseDebutStart]) recorded once on the first
/// run of an approved build, so no chart event from before it is ever
/// re-told as a new-release debut.
abstract final class NewReleaseDebutActivation {
  /// Fail-closed: no new-release debut is told while this is false.
  static const bool generationApproved = false;
}

/// Where new-release debuts would start on an install: the first run of a
/// build that carries approved wording, recorded once (write-once, like
/// the chronicle start in ChartMomentRules). Null: never.
///
/// Like ChartMomentRules.appliesTo, weekly (finalized) debuts follow it
/// only for chart weeks starting at or after it, so the week running at
/// activation is never re-told; career (all-time) debuts follow it from the
/// play's own instant. Live debuts are never told.
class NewReleaseDebutStart {
  const NewReleaseDebutStart(this.fromUtc);

  /// Not started.
  static const NewReleaseDebutStart none = NewReleaseDebutStart(null);

  final DateTime? fromUtc;

  /// Whether [event] falls after the start. [approved] is
  /// [NewReleaseDebutActivation.generationApproved] outside tests.
  bool applies(
    ChartMomentEvent event, {
    bool approved = NewReleaseDebutActivation.generationApproved,
  }) {
    final from = fromUtc;
    if (!approved || from == null) return false;
    final at = switch (event.scope) {
      ChartMomentScope.live => null,
      ChartMomentScope.finalized => event.weekStartUtc,
      ChartMomentScope.allTime => event.occurredAt,
    };
    return at != null && !at.toUtc().isBefore(from.toUtc());
  }
}

/// Which new-release story a debut is.
enum NewReleaseDebutKind {
  /// 4.1: the song is a Single, dated by its own Single release date.
  single,

  /// 4.2: the song is on a new album or EP, dated by that release.
  albumTrack,
}

/// Why a debut is not a new-release debut. Every check fails closed.
enum NewReleaseIneligibility {
  /// Not a debut event (a re-entry, climb, exit, …).
  notADebut,

  /// A re-entry: never a new-release debut.
  reentry,

  /// Only the song charts (Hot 100 and Bubbling Under) are covered.
  notSongChart,

  /// Live (in-progress week) Moments are never told.
  liveScope,

  /// No position, or one outside #1–200.
  noRank,

  /// The event records an earlier rank or peak, so it is not a genuine
  /// first appearance.
  priorChartHistory,

  /// The release facts belong to another song.
  entityMismatch,

  /// A Single without its own Single release date. The album date is
  /// never borrowed.
  singleDateMissing,

  /// The Single's own date is on or before the cutoff, or may be.
  singleDateNotNew,

  /// No album relationship (or the song is not on it).
  albumMissing,

  /// The release's format is unconfirmed (it might be a Single).
  releaseFormatUnconfirmed,

  /// The song's release is a Single release, but the song is not marked a
  /// Single: neither path can tell it truthfully.
  releaseIsSingleFormat,

  /// A compilation, soundtrack or cast recording, or a live release:
  /// a new release of that kind can carry older songs.
  releaseKindExcluded,

  /// The release has no title to name.
  albumTitleMissing,

  /// No standard edition, so the original release date is unknown (a
  /// library may hold only a later Deluxe).
  noStandardEdition,

  /// A remaster or anniversary edition: a reissue of older music.
  reissueEdition,

  /// An edition without a release date, or with a date whose precision was
  /// never recorded: the album's first release date is ambiguous.
  editionDateMissing,

  /// An edition is dated on or before the cutoff, or may be.
  albumDateNotNew,
}

/// One edition of the song's release, as the eligibility check reads it.
class NewReleaseEditionFacts {
  const NewReleaseEditionFacts({required this.type, this.releaseDate});

  /// An edition as stored: a date without a recorded precision is
  /// ambiguous (it may be a partial date saved as a day) and reads as
  /// missing.
  factory NewReleaseEditionFacts.fromStored({
    required AlbumEditionType type,
    DateTime? releaseDate,
    ReleaseDatePrecision? precision,
  }) => NewReleaseEditionFacts(
    type: type,
    releaseDate: releaseDate == null || precision == null
        ? null
        : ReleaseDate.fromStored(releaseDate, precision),
  );

  final AlbumEditionType type;
  final ReleaseDate? releaseDate;
}

/// The song's release (its album), as stored. Import or date-added times
/// are deliberately not part of it.
class NewReleaseAlbumFacts {
  const NewReleaseAlbumFacts({
    required this.albumId,
    required this.title,
    required this.format,
    required this.editions,
    this.kind,
    this.live,
    this.songOnAlbum = true,
  });

  final String albumId;
  final String title;

  /// As stated; null while unconfirmed.
  final ReleaseFormat? format;

  final ReleaseKind? kind;

  /// The stated live flag; null when not stated.
  final bool? live;

  /// Every edition of the release.
  final List<NewReleaseEditionFacts> editions;

  /// Whether an edition of this release lists the song.
  final bool songOnAlbum;
}

/// What the library says about a debuting song's release.
class NewReleaseSongFacts {
  const NewReleaseSongFacts({
    required this.songId,
    required this.isSingle,
    this.singleReleaseDate,
    this.album,
  });

  final String songId;

  /// `songs.is_single`.
  final bool isSingle;

  /// SongSinglePresentation.releaseDate: the Single's own date, set in the
  /// Track Studio. Read only while [isSingle].
  final ReleaseDate? singleReleaseDate;

  final NewReleaseAlbumFacts? album;
}

/// An eligible new-release debut: the facts its headline may state.
class NewReleaseDebut {
  const NewReleaseDebut({
    required this.kind,
    required this.event,
    required this.rank,
    required this.releaseDate,
    this.albumTitle,
    this.albumFormat,
  });

  final NewReleaseDebutKind kind;
  final ChartMomentEvent event;

  /// The real chart position, #1–200 (#101–200 is Bubbling Under).
  final int rank;

  /// The date that made it eligible: the Single's own date, or the
  /// release's earliest edition date.
  final ReleaseDate releaseDate;

  /// For album tracks: the release's title and format (album or EP).
  final String? albumTitle;
  final ReleaseFormat? albumFormat;

  /// Weekly (finalized) or career (all-time) chart.
  bool get weekly => event.scope == ChartMomentScope.finalized;

  bool get bubblingUnder => rank > ChartRankingEngine.officialChartLimit;

  /// Once per song per chart; see [NewReleaseEligibility.storyKey].
  String get storyKey => NewReleaseEligibility.storyKey(event);
}

/// The outcome of [NewReleaseEligibility.evaluate].
class NewReleaseDecision {
  const NewReleaseDecision.eligible(NewReleaseDebut this.debut) : reason = null;

  const NewReleaseDecision.ineligible(NewReleaseIneligibility this.reason)
    : debut = null;

  final NewReleaseDebut? debut;
  final NewReleaseIneligibility? reason;

  bool get isEligible => debut != null;
}

/// The new-release debut rules (pure; no reads, no writes).
abstract final class NewReleaseEligibility {
  /// Releases dated on this day or earlier never qualify: 2026-10-02 is
  /// the first eligible day.
  static final DateTime cutoffDay = DateTime.utc(2026, 10, 1);

  /// Whether [date] is strictly after [cutoffDay] over its whole interval:
  /// `2026-10-02` and `2026-11` qualify; `2026-10-01`, `2026-10` and
  /// `2026` do not; `2027` does. A partial date's interval starts at its
  /// [ReleaseDate.instant], so that start must be after the cutoff day.
  static bool isNew(ReleaseDate? date) =>
      date != null && date.instant.isAfter(cutoffDay);

  /// The dedup key: one new-release story per song per chart (weekly or
  /// career), whatever the week.
  static String storyKey(ChartMomentEvent event) =>
      'new-release-debut:${event.chartType.name}:${event.scope.name}:'
      '${event.entity.entityId}';

  /// Whether [event] with [song]'s release facts is a new-release debut.
  static NewReleaseDecision evaluate(
    ChartMomentEvent event,
    NewReleaseSongFacts song,
  ) {
    final problem = _eventProblem(event, song);
    if (problem != null) return NewReleaseDecision.ineligible(problem);

    // _eventProblem guarantees a rank of #1–200.
    final rank = event.currentRank!;
    // A Single is judged by its own date only, never its album's.
    return song.isSingle
        ? _single(event, rank, song)
        : _albumTrack(event, rank, song.album);
  }

  /// Keeps the first debut of each [NewReleaseDebut.storyKey], by time
  /// then key, and drops any whose key is in [alreadyTold].
  static List<NewReleaseDebut> deduplicate(
    Iterable<NewReleaseDebut> debuts, {
    Set<String> alreadyTold = const {},
  }) {
    final ordered = debuts.toList()
      ..sort((a, b) {
        final byTime = a.event.occurredAt.compareTo(b.event.occurredAt);
        return byTime != 0 ? byTime : a.storyKey.compareTo(b.storyKey);
      });
    final seen = {...alreadyTold};
    return [
      for (final debut in ordered)
        if (seen.add(debut.storyKey)) debut,
    ];
  }

  static NewReleaseIneligibility? _eventProblem(
    ChartMomentEvent event,
    NewReleaseSongFacts song,
  ) {
    if (event.eventType == ChartMomentEventType.reentry) {
      return NewReleaseIneligibility.reentry;
    }
    if (event.eventType != ChartMomentEventType.debut) {
      return NewReleaseIneligibility.notADebut;
    }
    if (event.chartType != ChartType.songs) {
      return NewReleaseIneligibility.notSongChart;
    }
    if (event.scope == ChartMomentScope.live) {
      return NewReleaseIneligibility.liveScope;
    }
    final rank = event.currentRank;
    if (rank == null ||
        rank < 1 ||
        rank > ChartRankingEngine.extendedStandingsLimit) {
      return NewReleaseIneligibility.noRank;
    }
    if (event.previousRank != null || event.previousPeakRank != null) {
      return NewReleaseIneligibility.priorChartHistory;
    }
    if (event.entity.entityId != song.songId) {
      return NewReleaseIneligibility.entityMismatch;
    }
    return null;
  }

  static NewReleaseDecision _single(
    ChartMomentEvent event,
    int rank,
    NewReleaseSongFacts song,
  ) {
    // The Single's own date only: never the album's.
    final date = song.singleReleaseDate;
    if (date == null) {
      return const NewReleaseDecision.ineligible(
        NewReleaseIneligibility.singleDateMissing,
      );
    }
    if (!isNew(date)) {
      return const NewReleaseDecision.ineligible(
        NewReleaseIneligibility.singleDateNotNew,
      );
    }
    return NewReleaseDecision.eligible(
      NewReleaseDebut(
        kind: NewReleaseDebutKind.single,
        event: event,
        rank: rank,
        releaseDate: date,
      ),
    );
  }

  static NewReleaseDecision _albumTrack(
    ChartMomentEvent event,
    int rank,
    NewReleaseAlbumFacts? album,
  ) {
    final problem = _albumProblem(album);
    if (problem != null) return NewReleaseDecision.ineligible(problem);

    final dates = [for (final edition in album!.editions) edition.releaseDate!];
    if (!dates.every(isNew)) {
      return const NewReleaseDecision.ineligible(
        NewReleaseIneligibility.albumDateNotNew,
      );
    }
    final earliest = dates.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    return NewReleaseDecision.eligible(
      NewReleaseDebut(
        kind: NewReleaseDebutKind.albumTrack,
        event: event,
        rank: rank,
        releaseDate: earliest,
        albumTitle: album.title.trim(),
        albumFormat: album.format,
      ),
    );
  }

  static NewReleaseIneligibility? _albumProblem(NewReleaseAlbumFacts? album) {
    if (album == null || !album.songOnAlbum) {
      return NewReleaseIneligibility.albumMissing;
    }
    switch (album.format) {
      case null:
        return NewReleaseIneligibility.releaseFormatUnconfirmed;
      case ReleaseFormat.single:
        return NewReleaseIneligibility.releaseIsSingleFormat;
      case ReleaseFormat.ep || ReleaseFormat.album:
        break;
    }
    if (album.kind != null || album.live == true) {
      return NewReleaseIneligibility.releaseKindExcluded;
    }
    if (album.title.trim().isEmpty) {
      return NewReleaseIneligibility.albumTitleMissing;
    }
    final types = {for (final edition in album.editions) edition.type};
    if (!types.contains(AlbumEditionType.standard)) {
      return NewReleaseIneligibility.noStandardEdition;
    }
    if (types.contains(AlbumEditionType.remaster) ||
        types.contains(AlbumEditionType.anniversary)) {
      return NewReleaseIneligibility.reissueEdition;
    }
    if (album.editions.any((edition) => edition.releaseDate == null)) {
      return NewReleaseIneligibility.editionDateMissing;
    }
    return null;
  }
}
