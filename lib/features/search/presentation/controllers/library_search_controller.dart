import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/models/library_search_results.dart';
import '../../application/repositories/library_search_repository.dart';

class LibrarySearchController extends ChangeNotifier {
  LibrarySearchController({
    required LibrarySearchRepository repository,
    Duration debounceDuration = const Duration(milliseconds: 250),
  }) : this._(repository, debounceDuration);

  LibrarySearchController._(this._repository, this._debounceDuration);

  final LibrarySearchRepository _repository;
  final Duration _debounceDuration;

  Timer? _debounceTimer;

  String _query = '';
  LibrarySearchResults _results = const LibrarySearchResults();
  bool _isSearching = false;
  Object? _error;
  int _requestGeneration = 0;

  String get query => _query;

  LibrarySearchResults get results => _results;

  bool get isSearching => _isSearching;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get hasQuery => _query.trim().isNotEmpty;

  bool get hasResults => _results.isNotEmpty;

  bool get showEmptyState {
    return hasQuery && !_isSearching && !hasError && _results.isEmpty;
  }

  void updateQuery(String value) {
    _query = value;
    _error = null;

    _debounceTimer?.cancel();
    _requestGeneration++;

    if (!hasQuery) {
      _results = const LibrarySearchResults();
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    final generation = _requestGeneration;

    _debounceTimer = Timer(_debounceDuration, () {
      unawaited(_search(generation));
    });
  }

  Future<void> retry() async {
    if (!hasQuery) {
      return;
    }

    _debounceTimer?.cancel();
    _requestGeneration++;

    final generation = _requestGeneration;

    _isSearching = true;
    _error = null;
    notifyListeners();

    await _search(generation);
  }

  void clear() {
    _debounceTimer?.cancel();
    _requestGeneration++;

    _query = '';
    _results = const LibrarySearchResults();
    _isSearching = false;
    _error = null;

    notifyListeners();
  }

  Future<void> _search(int generation) async {
    final submittedQuery = _query.trim();

    try {
      final results = await _repository.search(submittedQuery);

      if (generation != _requestGeneration) {
        return;
      }

      _results = results;
      _error = null;
    } catch (error) {
      if (generation != _requestGeneration) {
        return;
      }

      _results = const LibrarySearchResults();
      _error = error;
    } finally {
      if (generation == _requestGeneration) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
