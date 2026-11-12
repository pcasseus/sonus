import '../entities/chart_entry.dart';
import '../entities/chart_snapshot.dart';
import '../models/chart_type.dart';
import '../services/chart_ranking_engine.dart';
import 'chart_moment_event.dart';
import 'chart_moment_event_type.dart';
import 'chart_moment_scope.dart';

/// The kinds of artist dominance on the weekly Sonus Hot 100 (App Update
/// 1.2, REF-19).
enum ArtistDominanceKind {
  /// Every position from #1 to #tier belongs to the artist.
  sweep,

  /// The artist has at least tier songs in the Top 10.
  top10,

  /// The artist has at least tier songs on the Hot 100 (#1–100).
  hot100;

  /// The qualifying tiers, smallest first.
  List<int> get tiers => switch (this) {
    sweep => const [3, 5, 10],
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

/// A recorded dominance fact, read back from a stored Moment.
class ArtistDominance {
  const ArtistDominance(this.kind, this.tier);

  final ArtistDominanceKind kind;
  final int tier;

  /// How a dominance Moment marks itself in `source_id`: the stored type
  /// stays [ChartMomentEventType.artistSimultaneousThresholdSongs], which
  /// every Sonus version reads, with its usual threshold and count. Older
  /// builds tell it as "N songs in the Top T", which is true.
  static const String sourcePrefix = 'dominance:';

  static String sourceIdFor(
    ArtistDominanceKind kind,
    int tier,
    String snapshotId,
  ) => '$sourcePrefix${kind.name}:$tier:$snapshotId';

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
    if (parts.length < 2) return null;
    final kind = ArtistDominanceKind.values
        .where((k) => k.name == parts[0])
        .firstOrNull;
    final tier = int.tryParse(parts[1]);
    if (kind == null || tier == null || !kind.tiers.contains(tier)) {
      return null;
    }
    return ArtistDominance(kind, tier);
  }
}

/// Detects artist dominance on a finalized weekly Sonus Hot 100 (App Update
/// 1.2, REF-19). Pure and deterministic: the same snapshot and history
/// always give the same events, with the same keys.
///
/// - Songs chart only; ranks #1–100 (Bubbling Under never counts).
/// - Artists as the snapshot attributes them (the chart engine's primary
///   artist); each song counts once, at its best rank.
/// - For each kind, only the highest tier reached is recorded, and only
///   when it is higher than the tier the previous finalized week reached:
///   a held run is quiet, a return after a lower week is told again.
/// - Zones nest (Top 3/5/10 within the Top 10 within the Hot 100), so a
///   kind that counts the same number of songs as a more notable one the
///   artist reaches that week is the same songs: only the more notable is
///   recorded ("#1–3 sweep", never also "3 songs in the Top 10").
class ChartMomentArtistDominanceDetector {
  const ChartMomentArtistDominanceDetector();

  List<ChartMomentEvent> detect({
    required ChartSnapshot snapshot,
    required Iterable<ChartSnapshot> history,
    required DateTime createdAt,
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

    final previous = history
        .where(
          (week) =>
              week.isFinalized &&
              week.chartType == snapshot.chartType &&
              week.weekEndUtc.toUtc() == snapshot.weekStartUtc.toUtc(),
        )
        .toList(growable: false);
    if (previous.length > 1) {
      throw StateError(
        'Multiple finalized previous-week snapshots exist at '
        '${snapshot.weekStartUtc.toUtc().toIso8601String()}.',
      );
    }

    final current = _hot100ByArtist(snapshot);
    final before = previous.isEmpty
        ? const <String, List<ChartEntry>>{}
        : _hot100ByArtist(previous.single);
    final currentLeaders = _leadersByRank(current);
    final previousLeaders = _leadersByRank(before);

    final events = <ChartMomentEvent>[];
    final artists = current.keys.toList()..sort();
    for (final artistId in artists) {
      final songs = current[artistId]!;
      final earlier = before[artistId] ?? const <ChartEntry>[];
      // Songs counted by the more notable kinds this artist reaches.
      final counted = <int>{};
      for (final kind in ArtistDominanceKind.values) {
        final tier = kind == ArtistDominanceKind.sweep
            ? _sweepTier(artistId, currentLeaders)
            : _countTier(kind, songs);
        if (tier == null) continue;
        final zone = kind.zoneFor(tier);
        final inZone = songs.where((e) => e.rank <= zone).toList();
        final sameSongs = !counted.add(inZone.length);
        final previousTier = kind == ArtistDominanceKind.sweep
            ? _sweepTier(artistId, previousLeaders)
            : _countTier(kind, earlier);
        if (sameSongs || (previousTier != null && previousTier >= tier)) {
          continue;
        }
        events.add(
          _event(
            snapshot: snapshot,
            artistId: artistId,
            kind: kind,
            tier: tier,
            zone: zone,
            songs: inZone,
            createdAt: createdAt,
            userId: userId,
          ),
        );
      }
    }
    return List<ChartMomentEvent>.unmodifiable(events);
  }

  /// Each artist's distinct songs at #1–100, best rank first.
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

  /// Who holds each of #1–10: the artist of every distinct song at that
  /// rank (a shared rank has several).
  static Map<int, Set<String>> _leadersByRank(
    Map<String, List<ChartEntry>> byArtist,
  ) {
    final leaders = <int, Set<String>>{};
    for (final MapEntry(key: artistId, value: songs) in byArtist.entries) {
      for (final entry in songs) {
        if (entry.rank > 10) break;
        leaders.putIfAbsent(entry.rank, () => {}).add(artistId);
      }
    }
    return leaders;
  }

  /// The largest sweep tier: every position #1–tier is held by
  /// [artistId] alone.
  static int? _sweepTier(String artistId, Map<int, Set<String>> leaders) {
    int? reached;
    for (final tier in ArtistDominanceKind.sweep.tiers) {
      final held = [for (var rank = 1; rank <= tier; rank++) leaders[rank]]
          .every(
            (holders) =>
                holders != null &&
                holders.length == 1 &&
                holders.single == artistId,
          );
      if (!held) break;
      reached = tier;
    }
    return reached;
  }

  /// The highest tier of [kind] the count of [songs] in its zone reaches.
  static int? _countTier(ArtistDominanceKind kind, List<ChartEntry> songs) {
    int? reached;
    for (final tier in kind.tiers) {
      final count = songs.where((e) => e.rank <= kind.zoneFor(tier)).length;
      if (count >= tier) reached = tier;
    }
    return reached;
  }

  static ChartMomentEvent _event({
    required ChartSnapshot snapshot,
    required String artistId,
    required ArtistDominanceKind kind,
    required int tier,
    required int zone,
    required List<ChartEntry> songs,
    required DateTime createdAt,
    required String? userId,
  }) {
    final lead = songs.first;
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
      sourceId: ArtistDominance.sourceIdFor(kind, tier, snapshot.id),
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
