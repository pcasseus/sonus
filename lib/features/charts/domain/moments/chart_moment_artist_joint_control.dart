import '../entities/chart_entry.dart';
import '../entities/chart_snapshot.dart';
import '../models/chart_type.dart';
import '../services/chart_ranking_engine.dart';
import 'chart_moment_event.dart';
import 'chart_moment_event_type.dart';
import 'chart_moment_scope.dart';

/// Who is credited on a song, for telling joint chart control from a
/// collaboration (REF-19).
class ChartSongCredits {
  const ChartSongCredits({required this.artistIds, required this.complete});

  /// Every credited artist with an identity, whatever the role.
  final Set<String> artistIds;

  /// False when a credit has no artist identity or the song has more than
  /// one primary artist: who the song belongs to is then ambiguous.
  final bool complete;
}

/// A recorded joint-control fact, read back from a stored Moment.
class ArtistJointControl {
  const ArtistJointControl(this.positions, this.partnerArtistId);

  /// The Top N the two artists hold between them, from #1.
  final int positions;
  final String partnerArtistId;

  /// The smallest Top N told; two artists always share the Top 2 or 3
  /// unless one of them sweeps it, so those are never news.
  static const int minimumPositions = 4;

  /// Each artist holds at least this many of the positions.
  static const int minimumEach = 2;

  /// Like a dominance row, stored as
  /// [ChartMomentEventType.artistSimultaneousThresholdSongs] (one row per
  /// artist, with its own count in the Top N), which older builds tell as
  /// "N songs in the Top T": true for each artist.
  static const String sourcePrefix = 'joint:';

  static String sourceIdFor(
    int positions,
    String partnerArtistId,
    String snapshotId,
  ) => '$sourcePrefix$positions:$partnerArtistId:$snapshotId';

  static ArtistJointControl? of(ChartMomentEvent event) {
    final source = event.sourceId;
    if (event.eventType !=
            ChartMomentEventType.artistSimultaneousThresholdSongs ||
        event.scope != ChartMomentScope.finalized ||
        source == null ||
        !source.startsWith(sourcePrefix)) {
      return null;
    }
    final parts = source.substring(sourcePrefix.length).split(':');
    if (parts.length != 3 || parts[1].isEmpty || parts[2].isEmpty) {
      return null;
    }
    final positions = int.tryParse(parts[0]);
    if (positions == null ||
        positions < minimumPositions ||
        positions > ChartRankingEngine.officialChartLimit) {
      return null;
    }
    return ArtistJointControl(positions, parts[1]);
  }
}

/// The two artists holding every position from #1 to #positions, if any.
class _Control {
  const _Control(this.positions, this.songs);

  final int positions;

  /// Each artist's songs in the zone, best rank first.
  final Map<String, List<ChartEntry>> songs;

  Set<String> get pair => songs.keys.toSet();

  /// The pair, read the same whichever artist is asked about.
  String get pairKey => (songs.keys.toList()..sort()).join('|');
}

/// Detects two artists jointly holding the top of a finalized weekly Sonus
/// Hot 100 (REF-19): exactly two distinct primary artists hold every
/// position from #1 to #N, N at least 4, each with at least two songs.
///
/// - Not a collaboration: no song in the zone may credit both artists (by
///   credit, chart artist or attribution), and every song's credits must be
///   known and have one primary artist. Otherwise nothing is recorded.
/// - Told when the pair's N is new or larger than the previous week's
///   for the same pair; a held or smaller one is quiet.
/// - Each artist's own achievements (a sweep, its presence) are recorded
///   as usual beside it; the feed picks the story.
class ChartMomentArtistJointControlDetector {
  const ChartMomentArtistJointControlDetector();

  List<ChartMomentEvent> detect({
    required ChartSnapshot snapshot,
    required Iterable<ChartSnapshot> history,
    required DateTime createdAt,
    required Map<String, ChartSongCredits> credits,
    required Map<String, String?> chartArtists,
    String? userId,
  }) {
    if (!snapshot.isFinalized) {
      throw ArgumentError.value(
        snapshot.finalizedAt,
        'snapshot',
        'Joint chart control requires a finalized chart snapshot.',
      );
    }
    if (snapshot.chartType != ChartType.songs) return const [];

    final control = _control(snapshot);
    if (control == null) return const [];
    if (!_noSharedCredit(control, credits, chartArtists)) return const [];

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
    final before = previous.isEmpty ? null : _control(previous.single);
    if (before != null &&
        before.pairKey == control.pairKey &&
        before.positions >= control.positions) {
      return const [];
    }

    final ids = control.songs.keys.toList()..sort();
    if (ids.any((id) => id.contains(':'))) return const [];
    return List.unmodifiable([
      for (final artistId in ids)
        _event(
          snapshot: snapshot,
          artistId: artistId,
          partnerId: ids.firstWhere((id) => id != artistId),
          control: control,
          createdAt: createdAt,
          userId: userId,
        ),
    ]);
  }

  static _Control? _control(ChartSnapshot week) {
    final byRank = <int, ChartEntry>{};
    for (final entry in week.entries) {
      final artistId = entry.entity.artistId;
      if (artistId == null ||
          artistId.isEmpty ||
          entry.rank < 1 ||
          entry.rank > ChartRankingEngine.officialChartLimit) {
        continue;
      }
      byRank[entry.rank] = entry;
    }
    final songs = <String, List<ChartEntry>>{};
    var positions = 0;
    for (var rank = 1; rank <= ChartRankingEngine.officialChartLimit; rank++) {
      final entry = byRank[rank];
      if (entry == null) break;
      final artistId = entry.entity.artistId!;
      if (!songs.containsKey(artistId) && songs.length == 2) break;
      songs.putIfAbsent(artistId, () => []).add(entry);
      positions = rank;
    }
    if (songs.length != 2 ||
        positions < ArtistJointControl.minimumPositions ||
        songs.values.any(
          (list) => list.length < ArtistJointControl.minimumEach,
        )) {
      return null;
    }
    return _Control(positions, songs);
  }

  /// No song in the zone belongs to both artists in any way, and every
  /// song's ownership is clear.
  static bool _noSharedCredit(
    _Control control,
    Map<String, ChartSongCredits> credits,
    Map<String, String?> chartArtists,
  ) {
    // Every identity each artist appears under in the zone.
    final identities = {
      for (final MapEntry(key: artistId, value: songs) in control.songs.entries)
        artistId: {
          artistId,
          for (final entry in songs)
            if (chartArtists[entry.entity.entityId] case final String id) id,
        },
    };
    final [first, second] = control.pair.toList();
    if (identities[first]!.intersection(identities[second]!).isNotEmpty) {
      return false;
    }
    for (final songs in control.songs.values) {
      for (final entry in songs) {
        final songCredits = credits[entry.entity.entityId];
        if (songCredits == null || !songCredits.complete) return false;
        final touches = {
          ...songCredits.artistIds,
          if (chartArtists[entry.entity.entityId] case final String id) id,
          entry.entity.artistId!,
        };
        if (touches.intersection(identities[first]!).isNotEmpty &&
            touches.intersection(identities[second]!).isNotEmpty) {
          return false;
        }
      }
    }
    return true;
  }

  static ChartMomentEvent _event({
    required ChartSnapshot snapshot,
    required String artistId,
    required String partnerId,
    required _Control control,
    required DateTime createdAt,
    required String? userId,
  }) {
    final own = control.songs[artistId]!;
    final partner = control.songs[partnerId]!;
    final key = [
      'moment',
      'finalized',
      snapshot.chartType.name,
      snapshot.weekStartUtc.toUtc().millisecondsSinceEpoch,
      artistId,
      'joint',
      control.positions,
      partnerId,
      snapshot.id,
    ].join(':');
    final lead = own.first;
    return ChartMomentEvent(
      id: key,
      deduplicationKey: key,
      userId: userId,
      sourceId: ArtistJointControl.sourceIdFor(
        control.positions,
        partnerId,
        snapshot.id,
      ),
      chartType: snapshot.chartType,
      scope: ChartMomentScope.finalized,
      eventType: ChartMomentEventType.artistSimultaneousThresholdSongs,
      entity: lead.entity,
      relatedEntity: partner.first.entity,
      weekStartUtc: snapshot.weekStartUtc.toUtc(),
      weekEndUtc: snapshot.weekEndUtc.toUtc(),
      occurredAt: snapshot.finalizedAt!.toUtc(),
      createdAt: createdAt.toUtc(),
      previousRank: lead.previousFinalRank,
      currentRank: lead.rank,
      threshold: control.positions,
      currentPeakRank: lead.peakRank,
      qualifiedStreamCount: lead.qualifiedStreamCount,
      milestoneValue: own.length,
    );
  }
}
