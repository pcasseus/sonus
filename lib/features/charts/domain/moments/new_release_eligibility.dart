import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/library_organization.dart';
import '../../../library/domain/entities/release_date.dart';
import '../models/chart_type.dart';
import '../services/chart_ranking_engine.dart';
import 'chart_moment_event.dart';
import 'chart_moment_event_type.dart';
import 'chart_moment_scope.dart';

/// New-release debuts (App Update 1.3): a song chart debut told as a new
/// Single's or a new album or EP track's debut.
///
/// Approved 2026-11-16 for prospective activation. The editorial desk
/// re-words a debut story
/// with these rules only while [generationApproved] (and the headlines'
/// own approval) hold and a prospective start ([NewReleaseDebutStart]) has
/// been recorded once, on the first run of an approved build, so no chart
/// event from before it is ever re-told as a new-release debut. The debut
/// is chosen from the stored chart events ([NewReleaseEligibility.
/// firstDebuts]); once its story is shown, a publication record
/// (NewReleasePublication) holds its facts and wording for good.
abstract final class NewReleaseDebutActivation {
  /// Approved 2026-11-16 (prospective activation). Setting this to false
  /// switches the family off again: no story is re-worded and no
  /// publication is written or read.
  static const bool generationApproved = true;
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

  /// Rule 1 (user decision 2026-11-16): the release date was set or edited
  /// after the song's first chart appearance, or when it was written is
  /// unknown. A date added afterwards never makes a retroactive story.
  releaseDateNotProvenBeforeDebut,

  /// Rule 2: the song's chart history before this debut cannot be proven
  /// complete: its first qualified play is unknown, or came before the
  /// point from which this database recorded every appearance on both
  /// charts ([NewReleaseEvidence.coverageFrom]).
  earlierHistoryUnproven,

  /// Rule 4: the debut was not recorded on this database's own chart
  /// history: it was stored before that history began (restored from a
  /// backup, pulled from the cloud archive, or rebuilt), or the debut's
  /// chart week began before it.
  notRecordedHere,
}

/// One edition of the song's release, as the eligibility check reads it.
class NewReleaseEditionFacts {
  const NewReleaseEditionFacts({
    required this.type,
    this.releaseDate,
    this.writtenAt,
  });

  /// An edition as stored: a date without a recorded precision is
  /// ambiguous (it may be a partial date saved as a day) and reads as
  /// missing.
  factory NewReleaseEditionFacts.fromStored({
    required AlbumEditionType type,
    DateTime? releaseDate,
    ReleaseDatePrecision? precision,
    DateTime? writtenAt,
  }) => NewReleaseEditionFacts(
    type: type,
    releaseDate: releaseDate == null || precision == null
        ? null
        : ReleaseDate.fromStored(releaseDate, precision),
    writtenAt: writtenAt,
  );

  final AlbumEditionType type;
  final ReleaseDate? releaseDate;

  /// The edition's last write (`album_editions.updated_at`): its release
  /// date was written at or before it. Any edit moves it, so it is an
  /// upper bound, never earlier than the date's own write. Null: unknown.
  final DateTime? writtenAt;
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
    this.singleWrittenAt,
    this.album,
  });

  final String songId;

  /// `songs.is_single`.
  final bool isSingle;

  /// SongSinglePresentation.releaseDate: the Single's own date, set in the
  /// Track Studio. Read only while [isSingle].
  final ReleaseDate? singleReleaseDate;

  /// SongSinglePresentation.updatedAt: the presentation's last write, so
  /// the Single's date was written at or before it. A cover or chart-cover
  /// edit moves it too: an upper bound, never earlier than the date's own
  /// write (there is no separate date timestamp). Null: unknown.
  final DateTime? singleWrittenAt;

  final NewReleaseAlbumFacts? album;
}

/// What proves a new-release debut is a genuine, first-ever appearance
/// recorded on this database (App Update 1.3, user rules 2026-11-16). Read
/// only from stored data; nothing here is written.
class NewReleaseEvidence {
  const NewReleaseEvidence({
    required this.historyOriginUtc,
    this.momentsCutoffUtc,
    this.firstPlayAt = const {},
  });

  /// No evidence: no new-release story can be proven (published records
  /// are still told).
  static const NewReleaseEvidence none = NewReleaseEvidence(
    historyOriginUtc: null,
  );

  /// When this database's chart history began (`chart_history_origin`):
  /// its creation, its upgrade to version 46, or its latest restore,
  /// whichever is latest. A restore moves it to the restore; a phone
  /// rebuilt from the cloud starts it at its own creation. Null: unknown.
  final DateTime? historyOriginUtc;

  /// The latest permanent deletion, or merge that moved plays (the
  /// deletion journal's Moments cutoff, App Update 1.2 D5): weeks before it
  /// may have been recalculated without Moments and no earlier play
  /// records a career Moment, so appearances before it may be missing.
  final DateTime? momentsCutoffUtc;

  /// Each song's first qualified play still stored, by song id. A song
  /// without one has no proof.
  final Map<String, DateTime> firstPlayAt;

  /// From when this database holds every Weekly and Career song chart
  /// appearance: the latest of the new-release start, the chart history
  /// origin and the Moments cutoff. Null (nothing proven) without a start
  /// or an origin.
  DateTime? coverageFrom(NewReleaseDebutStart start) {
    final from = start.fromUtc;
    final origin = historyOriginUtc;
    if (from == null || origin == null) return null;
    var latest = from.toUtc();
    for (final at in [origin, ?momentsCutoffUtc]) {
      if (at.toUtc().isAfter(latest)) latest = at.toUtc();
    }
    return latest;
  }
}

/// An eligible new-release debut: the facts its headline may state.
class NewReleaseDebut {
  const NewReleaseDebut({
    required this.kind,
    required this.event,
    required this.rank,
    required this.releaseDate,
    this.albumId,
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

  /// For album tracks: the release's id, title and format (album or EP).
  final String? albumId;
  final String? albumTitle;
  final ReleaseFormat? albumFormat;

  /// Weekly (finalized) or career (all-time) chart.
  bool get weekly => event.scope == ChartMomentScope.finalized;

  bool get bubblingUnder => rank > ChartRankingEngine.officialChartLimit;

  /// Once per song across the weekly and career charts; see
  /// [NewReleaseEligibility.storyKey].
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

  /// The dedup key: one new-release story per song across the weekly and
  /// career charts together, whatever the week (user decision 2026-11-16).
  static String storyKey(ChartMomentEvent event) =>
      'new-release-debut:${event.chartType.name}:${event.entity.entityId}';

  /// [storyKey] of a song chart debut of [songId].
  static String songStoryKey(String songId) =>
      'new-release-debut:${ChartType.songs.name}:$songId';

  /// When a chart debut really happened, for choosing a song's first one:
  /// a weekly debut when its chart week closed (its end), whenever the
  /// device finalized it; a career debut at the play that made it.
  static DateTime effectiveAt(ChartMomentEvent event) => switch (event.scope) {
    ChartMomentScope.finalized => event.weekEndUtc,
    ChartMomentScope.allTime || ChartMomentScope.live => event.occurredAt,
  }.toUtc();

  /// Chronological order for new-release debuts: by [effectiveAt]; at the
  /// same instant the Weekly chart's comes first; then by key, so the same
  /// events always give the same order.
  static int compareChronology(ChartMomentEvent a, ChartMomentEvent b) {
    final byTime = effectiveAt(a).compareTo(effectiveAt(b));
    if (byTime != 0) return byTime;
    final aWeekly = a.scope == ChartMomentScope.finalized;
    final bWeekly = b.scope == ChartMomentScope.finalized;
    if (aWeekly != bWeekly) return aWeekly ? -1 : 1;
    return a.deduplicationKey.compareTo(b.deduplicationKey);
  }

  /// Whether [event] itself could be a new-release debut, before the
  /// song's release facts: a genuine Weekly or Career song chart debut at
  /// #1–200, from [start] on.
  static bool isCandidate(
    ChartMomentEvent event, {
    required NewReleaseDebutStart start,
    bool approved = NewReleaseDebutActivation.generationApproved,
  }) =>
      event.eventType == ChartMomentEventType.debut &&
      event.chartType == ChartType.songs &&
      event.scope != ChartMomentScope.live &&
      event.currentRank != null &&
      event.currentRank! >= 1 &&
      event.currentRank! <= ChartRankingEngine.extendedStandingsLimit &&
      event.previousRank == null &&
      event.previousPeakRank == null &&
      start.applies(event, approved: approved);

  /// Whether [event] is a song's appearance on the Weekly or Career song
  /// chart: a debut or a re-entry (a re-entry proves an earlier one).
  static bool isChartAppearance(ChartMomentEvent event) =>
      (event.eventType == ChartMomentEventType.debut ||
          event.eventType == ChartMomentEventType.reentry) &&
      event.chartType == ChartType.songs &&
      event.scope != ChartMomentScope.live;

  /// The one debut of each song that may be told as a new release, keyed
  /// by song id: the song's first appearance on either chart
  /// ([isChartAppearance]) by [compareChronology], and only when that
  /// first appearance is itself a candidate ([isCandidate]). A song whose
  /// first appearance came before the start (or was a re-entry) gets no
  /// new-release story at all, never a delayed one on the other chart
  /// (user decision 2026-11-16). Every other debut keeps its ordinary
  /// story.
  ///
  /// Pure and deterministic over [events] (duplicates by deduplication key
  /// are ignored), so the same stored events always choose the same debut,
  /// across restarts and however the feed is paged, provided [events]
  /// holds every stored debut since the start and every earlier appearance
  /// of those songs.
  static Map<String, ChartMomentEvent> firstDebuts(
    Iterable<ChartMomentEvent> events, {
    required NewReleaseDebutStart start,
    bool approved = NewReleaseDebutActivation.generationApproved,
  }) {
    final first = <String, ChartMomentEvent>{};
    for (final event in events) {
      if (!isChartAppearance(event)) continue;
      final songId = event.entity.entityId;
      final known = first[songId];
      if (known == null || compareChronology(event, known) < 0) {
        first[songId] = event;
      }
    }
    return {
      for (final MapEntry(key: songId, value: event) in first.entries)
        if (isCandidate(event, start: start, approved: approved)) songId: event,
    };
  }

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

  /// Whether an eligible [debut] (the song's first chart appearance, from
  /// [firstDebuts]) is proven, or why not (user rules 2026-11-16; every
  /// check fails closed):
  ///
  /// 1. Its release date was written no later than the debut
  ///    ([effectiveAt]): the Single presentation's, or every edition's,
  ///    last write. A date set or edited after the debut, or written at an
  ///    unknown time, tells no story.
  /// 2. The song's first qualified play is at or after
  ///    [NewReleaseEvidence.coverageFrom], so it cannot have charted before
  ///    the point from which both charts' appearances are all recorded
  ///    here; the debut is then truly its first appearance.
  /// 3. The debut was recorded here: stored ([ChartMomentEvent.createdAt])
  ///    and, for a weekly debut, its week begun at or after that point. A
  ///    debut restored from a backup, pulled from the cloud archive or
  ///    rebuilt from older plays was stored earlier, or has earlier plays,
  ///    so it is never told as breaking news.
  static NewReleaseIneligibility? proofProblem(
    NewReleaseDebut debut,
    NewReleaseSongFacts song,
    NewReleaseEvidence evidence, {
    required NewReleaseDebutStart start,
  }) {
    final debutAt = effectiveAt(debut.event);
    final written = switch (debut.kind) {
      NewReleaseDebutKind.single => [song.singleWrittenAt],
      NewReleaseDebutKind.albumTrack => [
        for (final edition in song.album?.editions ?? const [])
          edition.writtenAt,
      ],
    };
    if (written.isEmpty ||
        written.any((at) => at == null || at.toUtc().isAfter(debutAt))) {
      return NewReleaseIneligibility.releaseDateNotProvenBeforeDebut;
    }

    final coverage = evidence.coverageFrom(start);
    final firstPlay = evidence.firstPlayAt[song.songId];
    if (coverage == null ||
        firstPlay == null ||
        firstPlay.toUtc().isBefore(coverage)) {
      return NewReleaseIneligibility.earlierHistoryUnproven;
    }

    if (debut.event.createdAt.toUtc().isBefore(coverage) ||
        !NewReleaseDebutStart(coverage).applies(debut.event)) {
      return NewReleaseIneligibility.notRecordedHere;
    }
    return null;
  }

  /// Keeps the first debut of each [NewReleaseDebut.storyKey] (one per
  /// song across both charts), by [compareChronology], and drops any whose
  /// key is in [alreadyTold].
  static List<NewReleaseDebut> deduplicate(
    Iterable<NewReleaseDebut> debuts, {
    Set<String> alreadyTold = const {},
  }) {
    final ordered = debuts.toList()
      ..sort((a, b) => compareChronology(a.event, b.event));
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
        albumId: album.albumId,
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
