import 'package:flutter/foundation.dart';

import '../../application/models/home_snapshot.dart';
import '../../application/services/home_data_service.dart';

typedef HomeControllerNow = DateTime Function();

class HomeController extends ChangeNotifier {
  HomeController({required this._service, HomeControllerNow? now})
    : _now = now ?? DateTime.now;

  final HomeDataService _service;
  final HomeControllerNow _now;

  HomeSnapshot? _snapshot;
  bool _isLoading = false;
  Object? _error;

  int _requestGeneration = 0;

  HomeSnapshot? get snapshot => _snapshot;

  bool get isLoading => _isLoading;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get hasData => _snapshot != null;

  bool get isEmpty =>
      !_isLoading &&
      _error == null &&
      (_snapshot == null || _snapshot!.isEmpty);

  Future<void> load() {
    if (_isLoading) {
      return Future<void>.value();
    }

    return _load();
  }

  Future<void> refresh() {
    return _load();
  }

  Future<void> _load() async {
    final generation = ++_requestGeneration;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final snapshot = await _service.load(referenceLocal: _now());

      if (generation != _requestGeneration) {
        return;
      }

      _snapshot = snapshot;
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
}
