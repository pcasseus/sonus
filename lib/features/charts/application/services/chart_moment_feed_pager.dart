import '../../domain/moments/chart_moment_event.dart';
import '../../domain/repositories/chart_moment_repository.dart';

/// Reads stored Moments for the feed, newest first, a bounded page at a
/// time and only in whole local days (SN-50 F-Q25).
///
/// The editorial desk decides a day's stories from the whole day (the
/// daily cap on minor stories; a finalized week is published at one
/// instant), so a page that ends inside a day reads on until that day is
/// complete. Every loaded day then has the same stories as a full read.
class ChartMomentFeedPager {
  ChartMomentFeedPager(this._repository, {this.pageSize = defaultPageSize})
    : assert(pageSize > 0);

  static const int defaultPageSize = 200;

  final ChartMomentRepository _repository;
  final int pageSize;

  final List<ChartMomentEvent> _events = [];
  List<ChartMomentEvent> _partialDay = const [];
  ChartMomentPageCursor? _cursor;
  bool _exhausted = false;
  int _days = 0;

  /// The loaded whole days, newest first.
  List<ChartMomentEvent> get events => List.unmodifiable(_events);

  /// Whether older Moments may still be stored.
  bool get hasMore => !_exhausted;

  /// The local day of the oldest loaded Moment, as [localDay] gives it.
  String? get oldestDay =>
      _events.isEmpty ? null : localDay(_events.last.occurredAt);

  /// How many Moments are loaded.
  int get length => _events.length;

  /// The local calendar day the desk counts a Moment in.
  static String localDay(DateTime occurredAt) {
    final local = occurredAt.toLocal();
    return '${local.year}-${local.month}-${local.day}';
  }

  /// Reads at least [minimum] more Moments (a page by default) and, while
  /// older ones remain, at least two whole days in all, so the oldest day
  /// can serve as the context of the day after it.
  Future<void> loadMore({int? minimum}) async {
    final wanted = _events.length + (minimum ?? pageSize);

    while (!_exhausted && (_events.length < wanted || _days < 2)) {
      final page = await _repository.getPage(before: _cursor, limit: pageSize);

      if (page.isNotEmpty) {
        _cursor = ChartMomentPageCursor.of(page.last);
      }

      final pending = [..._partialDay, ...page];

      if (page.length < pageSize) {
        _exhausted = true;
        _partialDay = const [];
        _add(pending);
        return;
      }

      final lastDay = localDay(pending.last.occurredAt);
      final split = pending.indexWhere(
        (event) => localDay(event.occurredAt) == lastDay,
      );

      _add(pending.take(split));
      _partialDay = pending.sublist(split);
    }
  }

  void _add(Iterable<ChartMomentEvent> events) {
    for (final event in events) {
      final previous = _events.isEmpty
          ? null
          : localDay(_events.last.occurredAt);
      if (localDay(event.occurredAt) != previous) _days++;
      _events.add(event);
    }
  }
}
