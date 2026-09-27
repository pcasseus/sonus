import 'package:flutter/foundation.dart';

import '../../application/models/listening_history_entry.dart';
import '../../application/services/listening_history_service.dart';
import '../../domain/models/listening_history_cursor.dart';

class ListeningHistoryController extends ChangeNotifier {
  ListeningHistoryController({required this._service, int pageSize = 50})
    : _pageSize = _validatedPageSize(pageSize);

  final ListeningHistoryService _service;
  final int _pageSize;

  List<ListeningHistoryEntry> _entries = const [];
  ListeningHistoryCursor? _nextCursor;

  DateTime? _startedAtOrAfter;
  DateTime? _startedBefore;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  Object? _error;

  int _requestGeneration = 0;

  List<ListeningHistoryEntry> get entries => _entries;

  bool get isLoading => _isLoading;

  bool get isLoadingMore => _isLoadingMore;

  bool get hasMore => _hasMore;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isEmpty =>
      !_isLoading && !_isLoadingMore && _error == null && _entries.isEmpty;

  DateTime? get startedAtOrAfter => _startedAtOrAfter;

  DateTime? get startedBefore => _startedBefore;

  bool get hasDateFilter => _startedAtOrAfter != null || _startedBefore != null;

  Future<void> load() {
    if (_isLoading) {
      return Future.value();
    }

    return _loadFirstPage();
  }

  Future<void> refresh() {
    return _loadFirstPage();
  }

  Future<void> setDateRange({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    if (startedAtOrAfter != null &&
        startedBefore != null &&
        !startedAtOrAfter.isBefore(startedBefore)) {
      throw ArgumentError(
        'startedAtOrAfter must be earlier than startedBefore.',
      );
    }

    _startedAtOrAfter = startedAtOrAfter;
    _startedBefore = startedBefore;

    await _loadFirstPage();
  }

  Future<void> clearDateRange() {
    return setDateRange();
  }

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _nextCursor == null) {
      return;
    }

    final generation = _requestGeneration;
    final cursor = _nextCursor;

    _isLoadingMore = true;
    _error = null;
    notifyListeners();

    try {
      final page = await _service.getPage(
        startedAtOrAfter: _startedAtOrAfter,
        startedBefore: _startedBefore,
        before: cursor,
        limit: _pageSize,
      );

      if (generation != _requestGeneration) {
        return;
      }

      _entries = List<ListeningHistoryEntry>.unmodifiable([
        ..._entries,
        ...page.entries,
      ]);

      _nextCursor = page.nextCursor;
      _hasMore = page.hasMore;
    } catch (error) {
      if (generation != _requestGeneration) {
        return;
      }

      _error = error;
    } finally {
      if (generation == _requestGeneration) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_requestGeneration;

    _isLoading = true;
    _isLoadingMore = false;
    _error = null;

    notifyListeners();

    try {
      final page = await _service.getPage(
        startedAtOrAfter: _startedAtOrAfter,
        startedBefore: _startedBefore,
        limit: _pageSize,
      );

      if (generation != _requestGeneration) {
        return;
      }

      _entries = List<ListeningHistoryEntry>.unmodifiable(page.entries);
      _nextCursor = page.nextCursor;
      _hasMore = page.hasMore;
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

  static int _validatedPageSize(int pageSize) {
    if (pageSize <= 0) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Must be greater than zero.',
      );
    }

    return pageSize;
  }
}
