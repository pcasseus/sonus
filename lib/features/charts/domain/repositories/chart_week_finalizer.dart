import '../entities/chart_snapshot.dart';
import '../moments/chart_moment_event.dart';

/// What happened to a week's Moments when it was finalized.
enum ChartFinalizedMoments {
  /// No Moments were asked for (Moments off, or a week before they start).
  notRequested,

  /// The week's Moments were published with its snapshot.
  published,

  /// The week already had published Moments without a snapshot (left by
  /// the earlier two-step write). They were kept exactly as they were and
  /// nothing was added to them.
  keptEarlier,
}

/// The outcome of [ChartWeekFinalizer.finalizeWeek].
class ChartWeekFinalization {
  const ChartWeekFinalization({
    required this.snapshot,
    required this.wasAlreadyFinalized,
    required this.moments,
  });

  /// The week as stored: the new snapshot, or the one already finalized.
  final ChartSnapshot snapshot;

  /// True when the week was already finalized, so nothing was written.
  final bool wasAlreadyFinalized;

  final ChartFinalizedMoments moments;
}

/// Writes a finalized week and its Moments together (SN-50 F6): both are
/// stored or neither is. A week that is already finalized is never
/// changed, and published Moments are never replaced or added to.
abstract interface class ChartWeekFinalizer {
  /// Stores [snapshot], which must be finalized, and, unless [moments] is
  /// null, publishes them for the same week, in one transaction.
  Future<ChartWeekFinalization> finalizeWeek({
    required ChartSnapshot snapshot,
    List<ChartMomentEvent>? moments,
  });
}
