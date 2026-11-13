import '../../../core/design/sonus_count_label.dart';
import '../../analytics/application/models/pulse/pulse_period.dart';
import '../application/wrapped_summary.dart';

/// Labels for Sonus Wrapped's plain presentation. Every number shown comes
/// from a [WrappedSummary]; nothing here computes a statistic.
abstract final class WrappedFormat {
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String monthName(int month) => _months[month - 1];

  static String shortMonth(int month) => _months[month - 1].substring(0, 3);

  /// "March 2027" or "2027".
  static String period(PulsePeriod period) => switch (period.kind) {
    PulsePeriodKind.month => '${monthName(period.month)} ${period.year}',
    PulsePeriodKind.year => '${period.year}',
  };

  /// "12 March 2027".
  static String day(DateTime local) =>
      '${local.day} ${monthName(local.month)} ${local.year}';

  static String streams(int count) => sonusCount(count, 'stream');

  static String time(Duration listened) => sonusListeningTime(listened);

  /// What kind of summary this is, or null for a finished period with
  /// complete history.
  static String? stateNote(WrappedSummary summary) {
    final start = summary.historyStartLocal;
    return switch (summary.state) {
      WrappedPeriodState.future => 'This period hasn\'t started yet.',
      WrappedPeriodState.beforeHistory =>
        'Sonus has no listening history for this period.',
      WrappedPeriodState.inProgress =>
        summary.period.kind == PulsePeriodKind.year
            ? 'Year in progress: your Wrapped so far.'
            : 'Month in progress: your Wrapped so far.',
      WrappedPeriodState.complete when start != null =>
        'Partial: your Sonus listening history starts on ${day(start)}.',
      WrappedPeriodState.complete => null,
    };
  }

  /// "+12 streams on February" style change, or null.
  static String change(int now, int before, String what, PulsePeriod than) {
    final difference = now - before;
    final label = than.kind == PulsePeriodKind.month
        ? monthName(than.month)
        : '${than.year}';
    if (difference == 0) return 'Same $what as $label';
    final sign = difference > 0 ? '+' : '−';
    return '$sign${difference.abs()} $what on $label';
  }

  static String milestone(WrappedMilestone milestone) {
    return switch (milestone.kind) {
      WrappedMilestoneKind.lifetimeStreams =>
        'Your ${milestone.value}th stream in Sonus, on ${day(milestone.atLocal)}',
      WrappedMilestoneKind.longestStreak =>
        '${milestone.value} days in a row with a stream, from '
            '${day(milestone.atLocal)} to ${day(milestone.untilLocal!)}',
      WrappedMilestoneKind.busiestDay =>
        'Busiest day: ${day(milestone.atLocal)}, '
            '${streams(milestone.value)}',
    };
  }
}
