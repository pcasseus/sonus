// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../application/models/chart_moment_feed_item.dart';
import '../../application/services/chart_finalization_service.dart';
import '../../application/services/chart_moment_feed_aggregator.dart';
import '../../application/services/live_chart_service.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_view_size.dart';
import '../../domain/repositories/chart_moment_repository.dart';
import '../../domain/repositories/chart_repository.dart';
import '../models/charts_presentation_mode.dart';

typedef ChartsControllerNow = DateTime Function();

class ChartsController extends ChangeNotifier {
  ChartsController({
    required LiveChartService liveCharts,
    required ChartFinalizationService finalization,
    required ChartRepository charts,
    required LibraryQueryRepository library,
    ChartMomentRepository? moments,
    ChartMomentFeedAggregator momentFeedAggregator =
        const ChartMomentFeedAggregator(),
    ChartsControllerNow? now,
  }) : _liveCharts = liveCharts,
       _finalization = finalization,
       _charts = charts,
       _library = library,
       _moments = moments,
       _momentFeedAggregator = momentFeedAggregator,
       _now = now ?? DateTime.now;

  final LiveChartService _liveCharts;
  final ChartFinalizationService _finalization;
  final ChartRepository _charts;
  final LibraryQueryRepository _library;
  final ChartMomentRepository? _moments;
  final ChartMomentFeedAggregator _momentFeedAggregator;
  final ChartsControllerNow _now;

  ChartType _chartType = ChartType.songs;
  ChartViewSize _viewSize = ChartViewSize.top100;

  ChartsPresentationMode _presentationMode = ChartsPresentationMode.charts;

  ChartSnapshot? _liveSnapshot;
  List<ChartSnapshot> _history = const [];

  List<ChartMomentFeedItem> _momentFeedItems = const [];
  Object? _momentFeedError;

  Map<String, LibraryTrack> _tracksById = const {};
  Map<String, LibraryAlbum> _albumsById = const {};

  int? _historyIndex;

  bool _isLoading = false;
  Object? _error;

  int _requestGeneration = 0;

  /// The in-flight load that finalizes completed weeks. Callers that ask
  /// for another finalizing load while it runs share it, so finalization
  /// never runs twice at once.
  Future<void>? _finalizingLoad;

  bool _isDisposed = false;

  ChartType get chartType => _chartType;

  ChartViewSize get viewSize => _viewSize;

  ChartsPresentationMode get presentationMode => _presentationMode;

  bool get isShowingCharts =>
      _presentationMode == ChartsPresentationMode.charts;

  bool get isShowingMoments =>
      _presentationMode == ChartsPresentationMode.moments;

  bool get isLoading => _isLoading;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isViewingHistory => _historyIndex != null;

  bool get isViewingLive => _historyIndex == null;

  List<ChartSnapshot> get history => _history;

  List<ChartMomentFeedItem> get momentFeedItems => _momentFeedItems;

  Object? get momentFeedError => _momentFeedError;

  bool get hasMomentFeedError => _momentFeedError != null;

  bool get hasMomentFeedItems => _momentFeedItems.isNotEmpty;

  ChartSnapshot? get liveSnapshot => _liveSnapshot;

  ChartSnapshot? get selectedHistoricalSnapshot {
    final index = _historyIndex;

    if (index == null || index < 0 || index >= _history.length) {
      return null;
    }

    return _history[index];
  }

  ChartSnapshot? get snapshot {
    final selected = selectedHistoricalSnapshot;

    if (selected != null) {
      return _limitSnapshot(selected);
    }

    return _liveSnapshot;
  }

  bool get hasSnapshot => snapshot != null;

  bool get isEmpty =>
      !_isLoading &&
      _error == null &&
      (snapshot == null || snapshot!.entries.isEmpty);

  bool get canGoToOlderWeek {
    if (_history.isEmpty) {
      return false;
    }

    final index = _historyIndex;

    if (index == null) {
      return true;
    }

    return index + 1 < _history.length;
  }

  bool get canGoToNewerWeek {
    final index = _historyIndex;

    if (index == null) {
      return false;
    }

    return index >= 0;
  }

  LibraryTrack? trackForEntry(ChartEntry entry) {
    if (_chartType != ChartType.songs) {
      return null;
    }

    return _tracksById[entry.entity.entityId];
  }

  LibraryAlbum? albumForEntry(ChartEntry entry) {
    if (_chartType != ChartType.albums) {
      return null;
    }

    return _albumsById[entry.entity.entityId];
  }

  bool isTrackInteractive(ChartEntry entry) {
    if (!isViewingLive) {
      return false;
    }

    final track = trackForEntry(entry);

    return track != null &&
        !track.isBlocked &&
        track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  bool isAlbumInteractive(ChartEntry entry) {
    return isViewingLive && albumForEntry(entry) != null;
  }

  void selectPresentationMode(ChartsPresentationMode value) {
    if (_presentationMode == value) {
      return;
    }

    _presentationMode = value;
    _notify();
  }

  String? artworkPathForMoment(ChartMomentFeedItem item) {
    return switch (item.chartType) {
      ChartType.songs => _tracksById[item.entity.entityId]?.artworkPath,
      ChartType.albums => _albumsById[item.entity.entityId]?.artworkPath,
    };
  }

  String? relatedArtworkPathForMoment(ChartMomentFeedItem item) {
    final related = item.relatedEntity;

    if (related == null) {
      return null;
    }

    return switch (item.chartType) {
      ChartType.songs => _tracksById[related.entityId]?.artworkPath,
      ChartType.albums => _albumsById[related.entityId]?.artworkPath,
    };
  }

  Future<void> load() {
    if (_isDisposed) {
      return Future<void>.value();
    }

    if (_isLoading) {
      return _finalizingLoad ?? Future<void>.value();
    }

    return _startFinalizingLoad();
  }

  Future<void> refresh() {
    if (_isDisposed) {
      return Future<void>.value();
    }

    return _finalizingLoad ?? _startFinalizingLoad();
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Makes every in-flight request stale, so none of them writes state or
    // notifies after this point.
    _requestGeneration++;

    super.dispose();
  }

  Future<void> selectChartType(ChartType value) async {
    if (_isDisposed || _chartType == value) {
      return;
    }

    _chartType = value;
    _historyIndex = null;

    await _load(finalizeCompletedWeeks: false);
  }

  Future<void> selectViewSize(ChartViewSize value) async {
    if (_isDisposed || _viewSize == value) {
      return;
    }

    _viewSize = value;

    if (isViewingHistory) {
      _notify();
      return;
    }

    await _loadLiveOnly();
  }

  void showLive() {
    if (_historyIndex == null) {
      return;
    }

    _historyIndex = null;
    _notify();
  }

  void showOlderWeek() {
    if (_history.isEmpty) {
      return;
    }

    final index = _historyIndex;

    if (index == null) {
      _historyIndex = 0;
      _notify();
      return;
    }

    if (index + 1 >= _history.length) {
      return;
    }

    _historyIndex = index + 1;
    _notify();
  }

  void showNewerWeek() {
    final index = _historyIndex;

    if (index == null) {
      return;
    }

    if (index == 0) {
      _historyIndex = null;
      _notify();
      return;
    }

    _historyIndex = index - 1;
    _notify();
  }

  bool selectHistoricalWeek(DateTime weekStartUtc) {
    final target = weekStartUtc.toUtc();

    final index = _history.indexWhere(
      (snapshot) => snapshot.weekStartUtc.toUtc() == target,
    );

    if (index < 0) {
      return false;
    }

    _historyIndex = index;
    _notify();

    return true;
  }

  Future<void> _startFinalizingLoad() {
    late final Future<void> loading;

    loading = _load(finalizeCompletedWeeks: true).whenComplete(() {
      if (identical(_finalizingLoad, loading)) {
        _finalizingLoad = null;
      }
    });

    _finalizingLoad = loading;

    return loading;
  }

  /// Notifies listeners unless the controller has been disposed.
  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  Future<void> _load({required bool finalizeCompletedWeeks}) async {
    if (_isDisposed) {
      return;
    }

    final generation = ++_requestGeneration;

    _isLoading = true;
    _error = null;
    _notify();

    // A superseded or disposed request stops between steps rather than
    // loading data nobody will read.
    bool isStale() => generation != _requestGeneration;

    try {
      final referenceLocal = _now();

      if (finalizeCompletedWeeks) {
        await _finalization.finalizeCompletedWeeks(
          referenceLocal: referenceLocal,
        );

        if (isStale()) {
          return;
        }
      }

      final live = await _liveCharts.load(
        chartType: _chartType,
        referenceLocal: referenceLocal,
        viewSize: _viewSize,
      );

      if (isStale()) {
        return;
      }

      final history = await _charts.getHistory(_chartType);

      final tracks = await _library.getTracks();
      final albums = await _library.getAlbums();

      var momentFeedItems = _momentFeedItems;
      Object? momentFeedError;

      final moments = _moments;

      if (moments != null) {
        try {
          final rawMomentEvents = await moments.getRecent();

          momentFeedItems = _momentFeedAggregator.aggregate(rawMomentEvents);
        } catch (error) {
          momentFeedError = error;
        }
      }

      if (generation != _requestGeneration) {
        return;
      }

      _liveSnapshot = live;
      _history = List<ChartSnapshot>.unmodifiable(history);

      _tracksById = {for (final track in tracks) track.songId: track};

      _albumsById = {for (final album in albums) album.albumId: album};

      _momentFeedItems = List<ChartMomentFeedItem>.unmodifiable(
        momentFeedItems,
      );
      _momentFeedError = momentFeedError;

      final historyIndex = _historyIndex;

      if (historyIndex != null && historyIndex >= _history.length) {
        _historyIndex = _history.isEmpty ? null : _history.length - 1;
      }

      _error = null;
    } catch (error) {
      if (generation != _requestGeneration) {
        return;
      }

      _error = error;
    } finally {
      if (generation == _requestGeneration) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> _loadLiveOnly() async {
    if (_isDisposed) {
      return;
    }

    final generation = ++_requestGeneration;

    _isLoading = true;
    _error = null;
    _notify();

    try {
      final live = await _liveCharts.load(
        chartType: _chartType,
        referenceLocal: _now(),
        viewSize: _viewSize,
      );

      if (generation != _requestGeneration) {
        return;
      }

      _liveSnapshot = live;
      _error = null;
    } catch (error) {
      if (generation != _requestGeneration) {
        return;
      }

      _error = error;
    } finally {
      if (generation == _requestGeneration) {
        _isLoading = false;
        _notify();
      }
    }
  }

  ChartSnapshot _limitSnapshot(ChartSnapshot source) {
    if (source.entries.length <= _viewSize.limit) {
      return source;
    }

    return ChartSnapshot(
      id: source.id,
      chartType: source.chartType,
      weekStartUtc: source.weekStartUtc,
      weekEndUtc: source.weekEndUtc,
      finalizedAt: source.finalizedAt,
      revision: source.revision,
      entries: List.unmodifiable(source.entries.take(_viewSize.limit)),
    );
  }
}
