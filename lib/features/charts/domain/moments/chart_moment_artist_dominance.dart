import '../entities/chart_entry.dart';
import '../entities/chart_snapshot.dart';
import '../models/chart_type.dart';
import '../services/chart_ranking_engine.dart';
import 'chart_history_evidence.dart';
import 'chart_moment_event.dart';
import 'chart_moment_event_type.dart';
import 'chart_moment_scope.dart';

/// The kinds of artist dominance on the weekly Sonus Hot 100 (App Update
/// 1.2, REF-19).
enum ArtistDominanceKind {
  /// Every position from #1 to #tier belongs to the artist (Top 2 to 10).
  sweep,

  /// The artist has at least tier songs in the Top 10.
  top10,

  /// The artist has at least tier songs on the Hot 100 (#1–100).
  hot100;

  /// The qualifying tiers, smallest first.
  List<int> get tiers => switch (this) {
    sweep => const [2, 3, 4, 5, 6, 7, 8, 9, 10],
    top10 => const [3, 5, 10],
    hot100 => const [5, 10, 15, 20],
  };

  /// The zone the count is taken in: Top tier for a sweep.
  int zoneFor(int tier) => switch (this) {
    sweep => tier,
    top10 => 10,
    hot100 => ChartRankingEngine.officialChartLimit,
  };
}

/// What a dominance Moment says about the chart's history, decided once
/// when it is recorded and never recomputed (REF-19).
enum DominanceContextKind {
  none,

  /// No artist had reached this sweep before in Sonus Hot 100 history.
  chartFirst,

  /// More songs in the zone than any artist had held before.
  chartRecord,

  /// As many songs in the zone as the most any artist had held before.
  chartRecordTie,

  /// The [DominanceContext.count]th straight week of this sweep.
  streak,

  /// The artist's first sweep of this size.
  artistFirst,

  /// More songs in the zone than the artist had held before.
  personalBest,

  /// The artist's [DominanceContext.count]th separate sweep of this size.
  repeat,
}

class DominanceContext {
  const DominanceContext(this.kind, [this.count]);

  static const none = DominanceContext(DominanceContextKind.none);

  final DominanceContextKind kind;

  /// Weeks for [DominanceContextKind.streak]; the ordinal for
  /// [DominanceContextKind.repeat].
  final int? count;

  /// Its form in `source_id`: never contains ':'.
  String get token => switch (kind) {
    DominanceContextKind.none => '-',
    DominanceContextKind.chartFirst => 'chart-first',
    DominanceContextKind.chartRecord => 'chart-record',
    DominanceContextKind.chartRecordTie => 'chart-record-tie',
    DominanceContextKind.streak => 'streak$count',
    DominanceContextKind.artistFirst => 'artist-first',
    DominanceContextKind.personalBest => 'personal-best',
    DominanceContextKind.repeat => 'repeat$count',
  };

  static DominanceContext? parse(String token) {
    for (final kind in DominanceContextKind.values) {
      final fixed = DominanceContext(kind).token;
      if (kind != DominanceContextKind.streak &&
          kind != DominanceContextKind.repeat &&
          token == fixed) {
        return DominanceContext(kind);
      }
    }
    for (final (prefix, kind, minimum) in const [
      ('streak', DominanceContextKind.streak, 2),
      ('repeat', DominanceContextKind.repeat, 2),
    ]) {
      if (!token.startsWith(prefix)) continue;
      final count = int.tryParse(token.substring(prefix.length));
      if (count != null && count >= minimum) {
        return DominanceContext(kind, count);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DominanceContext && other.kind == kind && other.count == count;

  @override
  int get hashCode => Object.hash(kind, count);

  @override
  String toString() => 'DominanceContext($token)';
}

/// A recorded dominance fact, read back from a stored Moment.
class ArtistDominance {
  const ArtistDominance(
    this.kind,
    this.tier, [
    this.context = DominanceContext.none,
  ]);

  final ArtistDominanceKind kind;
  final int tier;
  final DominanceContext context;

  /// How a dominance Moment marks itself in `source_id`. The stored type
  /// stays [ChartMomentEventType.artistSimultaneousThresholdSongs], which
  /// every Sonus version reads, with its usual threshold and count, so
  /// older builds tell it as "N songs in the Top T", which is true.
  static const String sourcePrefix = 'dominance:';

  static String sourceIdFor(
    ArtistDominanceKind kind,
    int tier,
    DominanceContext context,
    String snapshotId,
  ) => '$sourcePrefix${kind.name}:$tier:${context.token}:$snapshotId';

  /// The dominance [event] records, or null for every other Moment.
  static ArtistDominance? of(ChartMomentEvent event) {
    final source = event.sourceId;
    if (event.eventType !=
            ChartMomentEventType.artistSimultaneousThresholdSongs ||
        event.scope != ChartMomentScope.finalized ||
        source == null ||
        !source.startsWith(sourcePrefix)) {
      return null;
    }
    final parts = source.substring(sourcePrefix.length).split(':');
    if (parts.length != 4 || parts[3].isEmpty) return null;
    final kind = ArtistDominanceKind.values
        .where((k) => k.name == parts[0])
        .firstOrNull;
    final tier = int.tryParse(parts[1]);
    final context = DominanceContext.parse(parts[2]);
    if (kind == null ||
        tier == null ||
        !kind.tiers.contains(tier) ||
        context == null) {
      return null;
    }
    return ArtistDominance(kind, tier, context);
  }

  @override
  bool operator ==(Object other) =>
      other is ArtistDominance &&
      other.kind == kind &&
      other.tier == tier &&
      other.context == context;

  @override
  int get hashCode => Object.hash(kind, tier, context);

  @override
  String toString() => 'ArtistDominance(${kind.name}, $tier, $context)';
}

/// One week of the songs chart, read for artist dominance.
class _Week {
  _Week(this.snapshot) : byArtist = _hot100ByArtist(snapshot) {
    for (final MapEntry(key: artistId, value: songs) in byArtist.entries) {
      for (final entry in songs) {
        if (entry.rank > 10) break;
        _leaders.putIfAbsent(entry.rank, () => {}).add(artistId);
      }
    }
  }

  final ChartSnapshot snapshot;

  /// Each artist's distinct songs at #1–100, best rank first.
  final Map<String, List<ChartEntry>> byArtist;

  /// Who holds each of #1–10.
  final Map<int, Set<String>> _leaders = {};

  DateTime get startUtc => snapshot.weekStartUtc.toUtc();
  DateTime get endUtc => snapshot.weekEndUtc.toUtc();
  bool get original => snapshot.provenance == ChartSnapshotProvenance.original;

  /// The largest Top N (2–10) [artistId] alone holds from #1, or null.
  int? sweep(String artistId) {
    int? reached;
    for (var rank = 1; rank <= 10; rank++) {
      final holders = _leaders[rank];
      if (holders == null ||
          holders.length != 1 ||
          holders.single != artistId) {
        break;
      }
      if (rank >= 2) reached = rank;
    }
    return reached;
  }

  /// [artistId]'s songs within #1–[zone].
  int countIn(String artistId, int zone) =>
      (byArtist[artistId] ?? const <ChartEntry>[])
          .where((e) => e.rank <= zone)
          .length;

  /// The most songs any one artist holds within #1–[zone].
  int mostIn(int zone) {
    var most = 0;
    for (final artistId in byArtist.keys) {
      final count = countIn(artistId, zone);
      if (count > most) most = count;
    }
    return most;
  }

  /// Whether any artist sweeps at least the Top [size].
  bool anySweepOf(int size) =>
      byArtist.keys.any((artistId) => (sweep(artistId) ?? 0) >= size);

  static Map<String, List<ChartEntry>> _hot100ByArtist(ChartSnapshot week) {
    final best = <String, ChartEntry>{};
    for (final entry in week.entries) {
      final artistId = entry.entity.artistId;
      if (artistId == null ||
          artistId.isEmpty ||
          entry.rank < 1 ||
          entry.rank > ChartRankingEngine.officialChartLimit) {
        continue;
      }
      final known = best[entry.entity.entityId];
      if (known == null || entry.rank < known.rank) {
        best[entry.entity.entityId] = entry;
      }
    }
    final byArtist = <String, List<ChartEntry>>{};
    for (final entry in best.values) {
      byArtist.putIfAbsent(entry.entity.artistId!, () => []).add(entry);
    }
    for (final songs in byArtist.values) {
      songs.sort((a, b) {
        final byRank = a.rank.compareTo(b.rank);
        return byRank != 0
            ? byRank
            : a.entity.entityId.compareTo(b.entity.entityId);
      });
    }
    return byArtist;
  }
}

/// Detects artist dominance on a finalized weekly Sonus Hot 100 (App Update
/// 1.2, REF-19). Pure and deterministic: the same snapshot, history and
/// evidence always give the same events, with the same keys.
///
/// - Songs chart only; ranks #1–100 (Bubbling Under never counts).
/// - Artists as the snapshot attributes them (the chart engine's primary
///   artist); each song counts once, at its best rank.
/// - Sweeps: the largest Top N (2–10) one artist holds alone from #1.
///   Told when it is new, larger than the previous week's, or back after a
///   week without it. An unchanged or smaller sweep is not news again; it
///   is told only as a verified streak, at its 2nd, 3rd, 5th and 10th
///   straight week and every 5 weeks after.
/// - Presence: the highest Top 10 (3, 5, 10) or Hot 100 (5, 10, 15, 20)
///   tier reached, told when higher than the previous week's. The story
///   says the true count.
/// - Zones nest, so a kind counting the same songs as a more notable kind
///   the artist reaches that week is not recorded again ("#1–3 sweep",
///   never also "3 songs in the Top 10").
/// - Historical context (a first, a record, a repeat) only with complete,
///   original history ([ChartHistoryEvidence]); otherwise none.
class ChartMomentArtistDominanceDetector {
  const ChartMomentArtistDominanceDetector();

  List<ChartMomentEvent> detect({
    required ChartSnapshot snapshot,
    required Iterable<ChartSnapshot> history,
    required DateTime createdAt,
    ChartHistoryEvidence evidence = ChartHistoryEvidence.unverified,
    String? userId,
  }) {
    if (!snapshot.isFinalized) {
      throw ArgumentError.value(
        snapshot.finalizedAt,
        'snapshot',
        'Artist dominance requires a finalized chart snapshot.',
      );
    }
    if (snapshot.chartType != ChartType.songs) return const [];

    final current = _Week(snapshot);
    final earlier = [
      for (final week in history)
        if (week.isFinalized &&
            week.chartType == snapshot.chartType &&
            week.weekStartUtc.toUtc().isBefore(current.startUtc))
          _Week(week),
    ]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
    final previousMatches = [
      for (final week in earlier)
        if (week.endUtc == current.startUtc) week,
    ];
    if (previousMatches.length > 1) {
      throw StateError(
        'Multiple finalized previous-week snapshots exist at '
        '${current.startUtc.toIso8601String()}.',
      );
    }
    final previous = previousMatches.firstOrNull;
    final verified = evidence.supportsHistoricalClaims(
      currentStartUtc: current.startUtc,
      earlierWeeks: [for (final week in earlier) week.snapshot],
    );

    final events = <ChartMomentEvent>[];
    final artists = current.byArtist.keys.toList()..sort();

    for (final artistId in artists) {
      final songs = current.byArtist[artistId]!;
      // Songs counted by the more notable kinds this artist reaches.
      final counted = <int>{};
      for (final kind in ArtistDominanceKind.values) {
        final tier = kind == ArtistDominanceKind.sweep
            ? current.sweep(artistId)
            : _countTier(kind, current, artistId);
        if (tier == null) continue;
        final zone = kind.zoneFor(tier);
        final inZone = songs.where((e) => e.rank <= zone).toList();
        if (!counted.add(inZone.length)) continue;

        final previousTier = previous == null
            ? null
            : kind == ArtistDominanceKind.sweep
            ? previous.sweep(artistId)
            : _countTier(kind, previous, artistId);
        final DominanceContext context;
        if (previousTier != null && previousTier >= tier) {
          if (kind != ArtistDominanceKind.sweep) continue;
          final streak = _verifiedStreak(
            artistId: artistId,
            size: tier,
            current: current,
            earlier: earlier,
            evidence: evidence,
          );
          if (streak == null || !_isStreakMilestone(streak)) continue;
          context = DominanceContext(DominanceContextKind.streak, streak);
        } else {
          context = verified
              ? _historicalContext(
                  kind: kind,
                  tier: tier,
                  zone: zone,
                  count: inZone.length,
                  artistId: artistId,
                  current: current,
                  earlier: earlier,
                )
              : DominanceContext.none;
        }

        events.add(
          _event(
            snapshot: snapshot,
            artistId: artistId,
            kind: kind,
            tier: tier,
            zone: zone,
            context: context,
            songs: inZone,
            createdAt: createdAt,
            userId: userId,
          ),
        );
      }
    }

    return List<ChartMomentEvent>.unmodifiable(events);
  }

  /// The 2nd, 3rd, 5th and 10th straight week, then every 5 weeks.
  static bool _isStreakMilestone(int weeks) =>
      weeks == 2 || weeks == 3 || weeks == 5 || (weeks >= 10 && weeks % 5 == 0);

  /// How many straight weeks, this one included, [artistId] has swept at
  /// least the Top [size]; null when that cannot be shown from original
  /// weeks. A week without a chart ends a streak; so does a week whose
  /// chart is not original, or that cannot be shown to have had no chart.
  static int? _verifiedStreak({
    required String artistId,
    required int size,
    required _Week current,
    required List<_Week> earlier,
    required ChartHistoryEvidence evidence,
  }) {
    if (!evidence.currentWeekOriginal) return null;
    final byEnd = {for (final week in earlier) week.endUtc: week};
    var weeks = 1;
    var cursor = current;
    while (true) {
      final before = byEnd[cursor.startUtc];
      if (before == null) {
        // No chart for the week before: a real gap only if this database
        // recorded that whole week and it had no plays.
        return evidence.isKnownEmptyWeekBefore(cursor.startUtc) ? weeks : null;
      }
      if (!before.original) return null;
      if ((before.sweep(artistId) ?? 0) < size) return weeks;
      weeks++;
      cursor = before;
    }
  }

  /// A first, a record or a repeat, in that order; none when nothing
  /// historical holds. Only called with verified history.
  static DominanceContext _historicalContext({
    required ArtistDominanceKind kind,
    required int tier,
    required int zone,
    required int count,
    required String artistId,
    required _Week current,
    required List<_Week> earlier,
  }) {
    if (kind == ArtistDominanceKind.sweep) {
      if (!earlier.any((week) => week.anySweepOf(tier))) {
        return const DominanceContext(DominanceContextKind.chartFirst);
      }
      bool reached(_Week week) => (week.sweep(artistId) ?? 0) >= tier;
      if (!earlier.any(reached)) {
        return const DominanceContext(DominanceContextKind.artistFirst);
      }
      // Separate runs of weeks reaching this size, this one included.
      var runs = 1;
      _Week? last;
      for (final week in earlier) {
        if (reached(week) && (last == null || last.endUtc != week.startUtc)) {
          runs++;
        }
        last = reached(week) ? week : null;
      }
      return DominanceContext(DominanceContextKind.repeat, runs);
    }

    final chartBest = earlier.fold(
      0,
      (most, week) => week.mostIn(zone) > most ? week.mostIn(zone) : most,
    );
    if (chartBest > 0 && count > chartBest) {
      return const DominanceContext(DominanceContextKind.chartRecord);
    }
    if (chartBest > 0 && count == chartBest) {
      return const DominanceContext(DominanceContextKind.chartRecordTie);
    }
    final ownBest = earlier.fold(
      0,
      (most, week) => week.countIn(artistId, zone) > most
          ? week.countIn(artistId, zone)
          : most,
    );
    if (ownBest > 0 && count > ownBest) {
      return const DominanceContext(DominanceContextKind.personalBest);
    }
    return DominanceContext.none;
  }

  /// The highest tier of [kind] the artist's count in its zone reaches.
  static int? _countTier(
    ArtistDominanceKind kind,
    _Week week,
    String artistId,
  ) {
    int? reached;
    for (final tier in kind.tiers) {
      if (week.countIn(artistId, kind.zoneFor(tier)) >= tier) reached = tier;
    }
    return reached;
  }

  static ChartMomentEvent _event({
    required ChartSnapshot snapshot,
    required String artistId,
    required ArtistDominanceKind kind,
    required int tier,
    required int zone,
    required DominanceContext context,
    required List<ChartEntry> songs,
    required DateTime createdAt,
    required String? userId,
  }) {
    final lead = songs.first;
    // The context is not part of the key: one fact per artist, kind, size
    // and week, however its history is told.
    final key = [
      'moment',
      'finalized',
      snapshot.chartType.name,
      snapshot.weekStartUtc.toUtc().millisecondsSinceEpoch,
      artistId,
      'dominance',
      kind.name,
      tier,
      snapshot.id,
    ].join(':');
    return ChartMomentEvent(
      id: key,
      deduplicationKey: key,
      userId: userId,
      sourceId: ArtistDominance.sourceIdFor(kind, tier, context, snapshot.id),
      chartType: snapshot.chartType,
      scope: ChartMomentScope.finalized,
      eventType: ChartMomentEventType.artistSimultaneousThresholdSongs,
      entity: lead.entity,
      relatedEntity: songs.length > 1 ? songs[1].entity : null,
      weekStartUtc: snapshot.weekStartUtc.toUtc(),
      weekEndUtc: snapshot.weekEndUtc.toUtc(),
      occurredAt: snapshot.finalizedAt!.toUtc(),
      createdAt: createdAt.toUtc(),
      previousRank: lead.previousFinalRank,
      currentRank: lead.rank,
      threshold: zone,
      currentPeakRank: lead.peakRank,
      qualifiedStreamCount: lead.qualifiedStreamCount,
      // The songs in the zone: the true "N songs in the Top T" every
      // Sonus version can tell.
      milestoneValue: songs.length,
    );
  }
}
