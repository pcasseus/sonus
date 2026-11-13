import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/events/library_change_signal.dart';
import '../../analytics/application/services/pulse/pulse_entity_directory.dart';
import '../../analytics/application/services/pulse/pulse_insights_service.dart';
import '../../analytics/application/services/pulse/pulse_listening_records.dart';
import '../../analytics/application/models/analytics_time_window.dart';
import '../../analytics/data/repositories/sqlite_pulse_listening_records.dart';
import '../../analytics/domain/repositories/playback_session_repository.dart';
import '../../analytics/presentation/scopes/listening_artist_attribution_lookup.dart';
import '../../charts/application/services/library_release_chart_eligibility.dart';
import '../../library/application/repositories/library_query_repository.dart';
import '../../library/application/services/library_organization_service.dart';
import '../application/wrapped_history_reader.dart';
import '../application/wrapped_service.dart';
import '../data/sqlite_wrapped_history_reader.dart';
import 'wrapped_controller.dart';

/// Provides Sonus Wrapped to the pages pushed for it. Built at the route,
/// from what the app already provides, so no app-wide file changes.
class WrappedScope extends StatefulWidget {
  const WrappedScope({
    super.key,
    required this.child,
    this.loader,
    this.changes,
  });

  final Widget child;

  /// A loader to use instead of the app database (tests).
  final WrappedLoader? loader;
  final LibraryChangeSignal? changes;

  @override
  State<WrappedScope> createState() => _WrappedScopeState();
}

class _WrappedScopeState extends State<WrappedScope> {
  WrappedController? _controller;
  LibraryChangeRefresher? _refresher;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final loader = widget.loader ?? _appLoader();
    if (loader == null) return;
    final controller = WrappedController(loader: loader);
    _controller = controller;
    _refresher = LibraryChangeRefresher(
      signal: widget.changes ?? LibraryChangeSignal.shared,
      kinds: {
        LibraryChangeKind.libraryEdited,
        LibraryChangeKind.listeningRecorded,
        LibraryChangeKind.importCompleted,
      },
      onChange: controller.invalidate,
    );
    controller.initialize();
  }

  WrappedLoader? _appLoader() {
    final database = context.read<AppDatabase?>();
    final library = context.read<LibraryQueryRepository?>();
    final sessions = context.read<PlaybackSessionRepository?>();
    if (database == null || library == null || sessions == null) return null;
    final organization = context.read<LibraryOrganizationService?>();
    final records = _LazyRecords(database);
    return WrappedService(
      pulse: PulseInsightsService(
        records: records,
        artistAttribution: listeningArtistAttributionOf(context),
        releaseEligibility: organization == null
            ? null
            : LibraryReleaseChartEligibility(organization),
      ),
      directory: PulseEntityDirectoryService(
        library: library,
        playbackSessions: sessions,
        statedReleaseFormats: organization == null
            ? null
            : () async => {
                for (final MapEntry(key: id, value: format)
                    in (await organization.releaseFormats()).entries)
                  id: format.label,
              },
      ),
      history: _LazyHistory(database),
    );
  }

  @override
  void dispose() {
    _refresher?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider<WrappedController?>.value(
        value: _controller,
        child: widget.child,
      );
}

/// [SqlitePulseListeningRecords] over the app database, opened on first use.
class _LazyRecords implements PulseListeningRecords {
  _LazyRecords(this._database);

  final AppDatabase _database;
  Future<SqlitePulseListeningRecords>? _records;

  Future<SqlitePulseListeningRecords> get _ready =>
      _records ??= _database.database.then<SqlitePulseListeningRecords>(
        (Database db) => SqlitePulseListeningRecords(db),
      );

  @override
  Future<DateTime?> firstSessionStartedAt() async =>
      (await _ready).firstSessionStartedAt();

  @override
  Future<List<PulseSegmentRecord>> segmentsOverlapping(
    AnalyticsTimeWindow window,
  ) async => (await _ready).segmentsOverlapping(window);

  @override
  Future<List<PulsePlayRecord>> qualifiedPlays(
    AnalyticsTimeWindow window,
  ) async => (await _ready).qualifiedPlays(window);

  @override
  Future<List<PulsePlayRecord>> audibleSessions(
    AnalyticsTimeWindow window,
  ) async => (await _ready).audibleSessions(window);
}

/// [SqliteWrappedHistoryReader] over the app database, opened on first use.
class _LazyHistory implements WrappedHistoryReader {
  _LazyHistory(this._database);

  final AppDatabase _database;
  Future<SqliteWrappedHistoryReader>? _reader;

  Future<SqliteWrappedHistoryReader> get _ready =>
      _reader ??= _database.database.then<SqliteWrappedHistoryReader>(
        (Database db) => SqliteWrappedHistoryReader(db),
      );

  @override
  Future<List<WrappedGenrePlay>> genrePlays(AnalyticsTimeWindow window) async =>
      (await _ready).genrePlays(window);

  @override
  Future<int> streamsBefore(DateTime utc) async =>
      (await _ready).streamsBefore(utc);

  @override
  Future<DateTime?> nthStreamAt(int n) async => (await _ready).nthStreamAt(n);

  @override
  Future<List<WrappedChartLeader>> weeklyNumberOnes() async =>
      (await _ready).weeklyNumberOnes();
}
