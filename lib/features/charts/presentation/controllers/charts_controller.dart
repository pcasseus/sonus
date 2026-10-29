// ignore_for_file: prefer_initializing_formals

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_album_edition.dart';
import '../../../library/application/models/library_artist.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../library/domain/entities/library_organization.dart';
import '../../application/models/chart_moment_feed_item.dart';
import '../../application/services/chart_finalization_service.dart';
import '../../application/services/chart_moment_feed_aggregator.dart';
import '../../application/services/all_time_chart_service.dart';
import '../../application/services/all_time_moment_service.dart';
import '../../application/services/this_week_chart_service.dart';
import '../../domain/entities/all_time_chart.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_view_size.dart';
import '../../domain/repositories/chart_moment_repository.dart';
import '../../domain/repositories/chart_repository.dart';
import '../editorial/moment_editorial_desk.dart';
import '../editorial/moment_facts.dart';
import '../models/chart_album_presentation.dart';
import '../models/chart_longevity.dart';
import '../models/charts_presentation_mode.dart';

typedef ChartsControllerNow = DateTime Function();

/// Release formats by album id: null while a release's format needs
/// review. Releases missing are Albums.
typedef ReleaseFormatsLoader = Future<Map<String, ReleaseFormat?>> Function();

/// Every Deluxe edition in the library, for the current album chart's
/// titles and covers.
typedef DeluxeEditionsLoader = Future<List<LibraryAlbumEdition>> Function();

class ChartsController extends ChangeNotifier {
  ChartsController({
    required AllTimeChartService allTimeCharts,
    required ChartFinalizationService finalization,
    required ChartRepository charts,
    required LibraryQueryRepository library,
    ChartMomentRepository? moments,
    AllTimeMomentService? allTimeMoments,
    ChartMomentFeedAggregator momentFeedAggregator =
        const ChartMomentFeedAggregator(),
    ChartsControllerNow? now,
    ReleaseFormatsLoader? releaseFormats,
    DeluxeEditionsLoader? deluxeEditions,
    ThisWeekChartService? thisWeekCharts,
  }) : _allTimeCharts = allTimeCharts,
       _finalization = finalization,
       _charts = charts,
       _library = library,
       _moments = moments,
       _allTimeMoments = allTimeMoments,
       _momentFeedAggregator = momentFeedAggregator,
       _now = now ?? DateTime.now,
       _loadReleaseFormats = releaseFormats,
       _loadDeluxeEditions = deluxeEditions,
       _thisWeekCharts = thisWeekCharts;

  final AllTimeChartService _allTimeCharts;
  final ChartFinalizationService _finalization;
  final ChartRepository _charts;
  final LibraryQueryRepository _library;
  final ChartMomentRepository? _moments;
  final AllTimeMomentService? _allTimeMoments;
  final ChartMomentFeedAggregator _momentFeedAggregator;
  final ChartsControllerNow _now;

  /// Without it there is no This Week view.
  final ThisWeekChartService? _thisWeekCharts;
  ProvisionalWeekChart? _thisWeek;
  bool _isViewingThisWeek = false;

  /// Formats name releases correctly in Moments; Albums without it.
  final ReleaseFormatsLoader? _loadReleaseFormats;
  Map<String, ReleaseFormat?> _releaseFormats = const {};

  final DeluxeEditionsLoader? _loadDeluxeEditions;
  Map<String, ChartAlbumPresentation> _albumPresentations = const {};

  /// The published stories for the current feed, composed once per load.
  List<MomentStory>? _momentStories;

  ChartType _chartType = ChartType.songs;
  ChartViewSize _viewSize = ChartViewSize.top100;

  ChartsPresentationMode _presentationMode = ChartsPresentationMode.charts;

  AllTimeChart? _allTimeChart;
  List<ChartSnapshot> _history = const [];
  Map<String, int> _weeklyPeaks = const {};
  ChartLongevityIndex _longevity = ChartLongevityIndex.empty;

  List<ChartMomentFeedItem> _momentFeedItems = const [];
  Object? _momentFeedError;

  Map<String, LibraryTrack> _tracksById = const {};
  Map<String, LibraryAlbum> _albumsById = const {};
  Map<String, LibraryArtist> _artistsById = const {};

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

  /// The provisional chart of the week in progress (SN-50 E-Q5).
  bool get isViewingThisWeek => _isViewingThisWeek;

  /// The default view: the permanent career standings. Older views are This
  /// Week, when offered, then the finalized weekly charts kept as history.
  bool get isViewingAllTime => _historyIndex == null && !_isViewingThisWeek;

  bool get _offersThisWeek => _thisWeekCharts != null;

  List<ChartSnapshot> get history => _history;

  List<ChartMomentFeedItem> get momentFeedItems => _momentFeedItems;

  Object? get momentFeedError => _momentFeedError;

  bool get hasMomentFeedError => _momentFeedError != null;

  bool get hasMomentFeedItems => _momentFeedItems.isNotEmpty;

  /// What Moments may look up about the library.
  late final MomentLookups momentLookups = _ControllerMomentLookups(this);

  /// The Moments feed as published stories, newest first.
  ///
  /// A release that is now a Single, or whose format awaits review, tells
  /// no release-chart story: one recorded earlier stays stored and returns
  /// if the release is made an EP or Album.
  List<MomentStory> get momentStories =>
      _momentStories ??= MomentEditorialDesk(lookups: momentLookups).compose([
        for (final item in _momentFeedItems)
          if (!_offReleaseChart(item)) item,
      ]);

  bool _offReleaseChart(ChartMomentFeedItem item) {
    if (item.chartType != ChartType.albums) return false;
    final id = item.entity.entityId;
    if (!_releaseFormats.containsKey(id)) return false;
    final format = _releaseFormats[id];
    return format == null || !format.chartsAsRelease;
  }

  AllTimeChart? get allTimeChart => _allTimeChart;

  ChartSnapshot? get selectedHistoricalSnapshot {
    final index = _historyIndex;

    if (index == null || index < 0 || index >= _history.length) {
      return null;
    }

    return _history[index];
  }

  /// The selected finalized week, limited to the view size. Null unless a
  /// finalized week is shown.
  ChartSnapshot? get snapshot {
    final selected = selectedHistoricalSnapshot;

    return selected == null ? null : _limitSnapshot(selected);
  }

  /// The week in progress, limited to the view size. Null unless This Week
  /// is shown. Never finalized and never stored.
  ChartSnapshot? get thisWeekSnapshot {
    final thisWeek = _thisWeek;

    return _isViewingThisWeek && thisWeek != null
        ? _limitSnapshot(thisWeek.snapshot)
        : null;
  }

  /// Whether there is a chart to show: career, This Week or historical.
  bool get hasChart => isViewingAllTime
      ? _allTimeChart != null
      : _isViewingThisWeek
      ? _thisWeek != null
      : snapshot != null;

  /// The entries of the chart on screen.
  List<ChartEntry> get entries => isViewingAllTime
      ? _allTimeChart?.entries ?? const []
      : _isViewingThisWeek
      ? thisWeekSnapshot?.entries ?? const []
      : snapshot?.entries ?? const [];

  /// On This Week, the entry's best position so far this week.
  int? bestSoFarRankFor(ChartEntry entry) => _isViewingThisWeek
      ? _thisWeek?.bestSoFarRank(entry.entity.entityId)
      : null;

  bool get isEmpty => !_isLoading && _error == null && entries.isEmpty;

  bool get canGoToOlderWeek {
    if (isViewingAllTime && _offersThisWeek) {
      return true;
    }

    if (_history.isEmpty) {
      return false;
    }

    final index = _historyIndex;

    if (index == null) {
      return true;
    }

    return index + 1 < _history.length;
  }

  bool get canGoToNewerWeek => !isViewingAllTime;

  /// Best official position the entity reached on a finalized weekly
  /// chart, or null if it never made a weekly Top 100.
  int? weeklyPeakFor(ChartEntry entry) => _weeklyPeaks[entry.entity.entityId];

  /// Official longevity from finalized weeks: as of the latest one on the
  /// standings, or as of the week on screen.
  ChartLongevity? longevityFor(ChartEntry entry) {
    final week = selectedHistoricalSnapshot;
    final id = entry.entity.entityId;

    return week == null
        ? _longevity.latest(id)
        : _longevity.asOfWeek(week.weekStartUtc, id);
  }

  /// On a weekly chart, last week's #101–200 position of an entry with no
  /// official position last week; context only (SN-50 E-Q1).
  int? previousExtendedRankFor(ChartEntry entry) {
    final week = selectedHistoricalSnapshot ?? thisWeekSnapshot;

    if (week == null || entry.previousFinalRank != null) {
      return null;
    }

    return _longevity.previousExtendedRank(
      week.weekStartUtc,
      entry.entity.entityId,
    );
  }

  /// The title, cover and edition the current album chart shows for a
  /// release: Deluxe first (SN-50 A-Q21). Null on weekly history, whose
  /// rows keep their stored titles, and for releases not in the library.
  ChartAlbumPresentation? albumPresentationFor(ChartEntry entry) {
    if (!isViewingAllTime || _chartType != ChartType.albums) {
      return null;
    }

    return _albumPresentations[entry.entity.entityId];
  }

  /// The songs of the chart on screen, in rank order, for a playback
  /// queue. Entries without a library song are left out.
  List<LibraryTrack> get entryTracks => [
    for (final entry in entries) ?trackForEntry(entry),
  ];

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

  /// Finalized weekly rows open the living song too; their stored content
  /// stays as it was (SN-50 E-Q8).
  bool isTrackInteractive(ChartEntry entry) {
    final track = trackForEntry(entry);

    return track != null &&
        !track.isBlocked &&
        track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  bool isAlbumInteractive(ChartEntry entry) => albumForEntry(entry) != null;

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

  /// The controller's clock, for relative times in the Moments feed.
  DateTime currentTime() => _now();

  /// The library song a Moment is about, if it is a song story.
  LibraryTrack? trackForMoment(ChartMomentFeedItem item) =>
      item.chartType == ChartType.songs
      ? _tracksById[item.entity.entityId]
      : null;

  /// The album a Moment is about, or the album of its song.
  LibraryAlbum? albumForMoment(ChartMomentFeedItem item) =>
      switch (item.chartType) {
        ChartType.songs => _albumsById[trackForMoment(item)?.albumId],
        ChartType.albums => _albumsById[item.entity.entityId],
      };

  LibraryArtist? artistForMoment(ChartMomentFeedItem item) {
    final artistId = item.artistId ?? item.entity.artistId;
    return artistId == null ? null : _artistsById[artistId];
  }

  /// The artist's portrait, or their banner when there is no portrait.
  String? artistPortraitPathForMoment(ChartMomentFeedItem item) {
    final artist = artistForMoment(item);
    return artist?.topArtistsArtworkPath ?? artist?.headerArtworkPath;
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

  /// Fails open: without formats every release reads as an Album.
  Future<Map<String, ReleaseFormat?>> _readReleaseFormats() async {
    try {
      return await _loadReleaseFormats?.call() ?? const {};
    } catch (_) {
      return const {};
    }
  }

  /// Fails open like formats: without editions releases show their primary.
  Future<List<LibraryAlbumEdition>> _readDeluxeEditions() async {
    try {
      return await _loadDeluxeEditions?.call() ?? const [];
    } catch (error, stackTrace) {
      developer.log(
        'Deluxe editions could not be read (${error.runtimeType}); '
        'albums show their primary edition',
        name: 'sonus.charts',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  /// The provisional week is optional: if it can't be built, the other
  /// views still load and the page returns to the career standings.
  Future<ProvisionalWeekChart?> _readThisWeek(DateTime referenceLocal) async {
    try {
      return await _thisWeekCharts?.load(
        chartType: _chartType,
        referenceLocal: referenceLocal,
      );
    } catch (error, stackTrace) {
      developer.log(
        'The provisional week could not be built (${error.runtimeType})',
        name: 'sonus.charts',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
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
    _isViewingThisWeek = false;

    await _load(finalizeCompletedWeeks: false);
  }

  Future<void> selectViewSize(ChartViewSize value) async {
    if (_isDisposed || _viewSize == value) {
      return;
    }

    _viewSize = value;

    if (!isViewingAllTime) {
      _notify();
      return;
    }

    await _loadAllTimeOnly();
  }

  void showAllTime() {
    if (isViewingAllTime) {
      return;
    }

    _historyIndex = null;
    _isViewingThisWeek = false;
    _notify();
  }

  void showOlderWeek() {
    if (isViewingAllTime && _offersThisWeek) {
      _isViewingThisWeek = true;
      _notify();
      return;
    }

    if (_history.isEmpty) {
      return;
    }

    final index = _historyIndex;

    if (index == null) {
      _isViewingThisWeek = false;
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
      if (_isViewingThisWeek) {
        _isViewingThisWeek = false;
        _notify();
      }
      return;
    }

    if (index == 0) {
      _historyIndex = null;
      _isViewingThisWeek = _offersThisWeek;
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
    _isViewingThisWeek = false;
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

      Object? allTimeMomentsError;
      final allTimeMoments = _allTimeMoments;

      if (finalizeCompletedWeeks && allTimeMoments != null) {
        try {
          await allTimeMoments.record(referenceLocal: referenceLocal);
        } catch (error) {
          allTimeMomentsError = error;
        }

        if (isStale()) {
          return;
        }
      }

      final allTime = await _allTimeCharts.load(
        chartType: _chartType,
        referenceLocal: referenceLocal,
        viewSize: _viewSize,
      );

      if (isStale()) {
        return;
      }

      final history = await _charts.getHistory(_chartType);

      // Once per load, after completed weeks are finalized, so its movement
      // compares with the latest finalized week.
      final thisWeek = await _readThisWeek(referenceLocal);

      final tracks = await _library.getTracks();
      final albums = await _library.getAlbums();
      final artists = await _library.getArtists();
      final formats = await _readReleaseFormats();
      final deluxes = await _readDeluxeEditions();

      var momentFeedItems = _momentFeedItems;
      Object? momentFeedError = allTimeMomentsError;

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

      _allTimeChart = allTime;
      _history = List<ChartSnapshot>.unmodifiable(history);
      _thisWeek = thisWeek;
      if (thisWeek == null) {
        _isViewingThisWeek = false;
      }
      _weeklyPeaks = _weeklyPeaksOf(history);
      _longevity = ChartLongevityIndex.fromHistory(history);

      _tracksById = {for (final track in tracks) track.songId: track};

      _albumsById = {for (final album in albums) album.albumId: album};
      _albumPresentations = _albumPresentationsOf(albums, deluxes);

      _artistsById = {for (final artist in artists) artist.artistId: artist};
      _releaseFormats = formats;

      _momentFeedItems = List<ChartMomentFeedItem>.unmodifiable(
        momentFeedItems,
      );
      _momentStories = null;
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

  Future<void> _loadAllTimeOnly() async {
    if (_isDisposed) {
      return;
    }

    final generation = ++_requestGeneration;

    _isLoading = true;
    _error = null;
    _notify();

    try {
      final allTime = await _allTimeCharts.load(
        chartType: _chartType,
        referenceLocal: _now(),
        viewSize: _viewSize,
      );

      if (generation != _requestGeneration) {
        return;
      }

      _allTimeChart = allTime;
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

  static Map<String, ChartAlbumPresentation> _albumPresentationsOf(
    List<LibraryAlbum> albums,
    List<LibraryAlbumEdition> deluxes,
  ) {
    final byAlbum = <String, List<LibraryAlbumEdition>>{};
    for (final edition in deluxes) {
      byAlbum.putIfAbsent(edition.albumId, () => []).add(edition);
    }

    return Map.unmodifiable({
      for (final album in albums)
        album.albumId: ChartAlbumPresentation.resolve(
          album,
          byAlbum[album.albumId] ?? const [],
        ),
    });
  }

  static Map<String, int> _weeklyPeaksOf(List<ChartSnapshot> history) {
    final peaks = <String, int>{};

    for (final snapshot in history) {
      for (final entry in snapshot.entries) {
        if (!entry.isOfficiallyCharting) {
          continue;
        }

        final id = entry.entity.entityId;
        final best = peaks[id];

        if (best == null || entry.rank < best) {
          peaks[id] = entry.rank;
        }
      }
    }

    return Map<String, int>.unmodifiable(peaks);
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

/// Library lookups for Moments, from what the controller has loaded.
class _ControllerMomentLookups implements MomentLookups {
  _ControllerMomentLookups(this._controller);

  final ChartsController _controller;

  @override
  String? artistName(String artistId) =>
      _controller._artistsById[artistId]?.name;

  @override
  ReleaseFormat? formatOf(String albumId) {
    final formats = _controller._releaseFormats;
    return formats.containsKey(albumId)
        ? formats[albumId]
        : ReleaseFormat.album;
  }

  @override
  ReleaseFormat? songReleaseFormat(String songId) {
    final track = _controller._tracksById[songId];
    return track == null ? null : formatOf(track.albumId);
  }

  @override
  List<String> featuredOf(String songId) =>
      _controller._tracksById[songId]?.featuredArtists ?? const [];

  @override
  String? artistIdNamed(String name) {
    final wanted = name.trim().toLowerCase();
    for (final artist in _controller._artistsById.values) {
      if (artist.name.trim().toLowerCase() == wanted) return artist.artistId;
    }
    return null;
  }

  @override
  String? songCover(String songId) {
    final track = _controller._tracksById[songId];
    if (track == null) return null;
    return _nonEmpty(_controller._albumsById[track.albumId]?.artworkPath) ??
        _nonEmpty(track.artworkPath);
  }

  @override
  String? releaseCover(String albumId) =>
      _nonEmpty(_controller._albumsById[albumId]?.artworkPath);

  @override
  String? artistPortrait(String artistId) {
    final artist = _controller._artistsById[artistId];
    return _nonEmpty(artist?.topArtistsArtworkPath) ??
        _nonEmpty(artist?.headerArtworkPath);
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
