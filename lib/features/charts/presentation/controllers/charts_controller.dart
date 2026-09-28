// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../application/services/chart_finalization_service.dart';
import '../../application/services/live_chart_service.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_view_size.dart';
import '../../domain/repositories/chart_repository.dart';

typedef ChartsControllerNow = DateTime Function();

class ChartsController extends ChangeNotifier {
  ChartsController({
    required LiveChartService liveCharts,
    required ChartFinalizationService finalization,
    required ChartRepository charts,
    required LibraryQueryRepository library,
    ChartsControllerNow? now,
  }) : _liveCharts = liveCharts,
       _finalization = finalization,
       _charts = charts,
       _library = library,
       _now = now ?? DateTime.now;

  final LiveChartService _liveCharts;
  final ChartFinalizationService _finalization;
  final ChartRepository _charts;
  final LibraryQueryRepository _library;
  final ChartsControllerNow _now;

  ChartType _chartType = ChartType.songs;
  ChartViewSize _viewSize = ChartViewSize.top100;

  ChartSnapshot? _liveSnapshot;
  List<ChartSnapshot> _history = const [];

  Map<String, LibraryTrack> _tracksById = const {};
  Map<String, LibraryAlbum> _albumsById = const {};

  int? _historyIndex;

  bool _isLoading = false;
  Object? _error;

  int _requestGeneration = 0;

  ChartType get chartType => _chartType;

  ChartViewSize get viewSize => _viewSize;

  bool get isLoading => _isLoading;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isViewingHistory => _historyIndex != null;

  bool get isViewingLive => _historyIndex == null;

  List<ChartSnapshot> get history => _history;

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

  Future<void> load() {
    if (_isLoading) {
      return Future<void>.value();
    }

    return _load(finalizeCompletedWeeks: true);
  }

  Future<void> refresh() {
    return _load(finalizeCompletedWeeks: true);
  }

  Future<void> selectChartType(ChartType value) async {
    if (_chartType == value) {
      return;
    }

    _chartType = value;
    _historyIndex = null;

    await _load(finalizeCompletedWeeks: false);
  }

  Future<void> selectViewSize(ChartViewSize value) async {
    if (_viewSize == value) {
      return;
    }

    _viewSize = value;

    if (isViewingHistory) {
      notifyListeners();
      return;
    }

    await _loadLiveOnly();
  }

  void showLive() {
    if (_historyIndex == null) {
      return;
    }

    _historyIndex = null;
    notifyListeners();
  }

  void showOlderWeek() {
    if (_history.isEmpty) {
      return;
    }

    final index = _historyIndex;

    if (index == null) {
      _historyIndex = 0;
      notifyListeners();
      return;
    }

    if (index + 1 >= _history.length) {
      return;
    }

    _historyIndex = index + 1;
    notifyListeners();
  }

  void showNewerWeek() {
    final index = _historyIndex;

    if (index == null) {
      return;
    }

    if (index == 0) {
      _historyIndex = null;
      notifyListeners();
      return;
    }

    _historyIndex = index - 1;
    notifyListeners();
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
    notifyListeners();

    return true;
  }

  Future<void> _load({required bool finalizeCompletedWeeks}) async {
    final generation = ++_requestGeneration;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final referenceLocal = _now();

      if (finalizeCompletedWeeks) {
        await _finalization.finalizeCompletedWeeks(
          referenceLocal: referenceLocal,
        );
      }

      final live = await _liveCharts.load(
        chartType: _chartType,
        referenceLocal: referenceLocal,
        viewSize: _viewSize,
      );

      final history = await _charts.getHistory(_chartType);

      final tracks = _chartType == ChartType.songs
          ? await _library.getTracks()
          : const <LibraryTrack>[];

      final albums = _chartType == ChartType.albums
          ? await _library.getAlbums()
          : const <LibraryAlbum>[];

      if (generation != _requestGeneration) {
        return;
      }

      _liveSnapshot = live;
      _history = List<ChartSnapshot>.unmodifiable(history);

      _tracksById = {for (final track in tracks) track.songId: track};

      _albumsById = {for (final album in albums) album.albumId: album};

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
        notifyListeners();
      }
    }
  }

  Future<void> _loadLiveOnly() async {
    final generation = ++_requestGeneration;

    _isLoading = true;
    _error = null;
    notifyListeners();

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
        notifyListeners();
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
