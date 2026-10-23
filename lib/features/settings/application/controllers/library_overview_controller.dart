import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../services/library_overview_service.dart';

/// Loads the read-only library summary shown in Settings.
///
/// A refresh requested while one is running reuses the running load.
class LibraryOverviewController extends ChangeNotifier {
  LibraryOverviewController({required this._service});

  final LibraryOverviewService _service;

  LibraryOverview? _overview;
  bool _isLoading = false;
  bool _hasError = false;
  Future<void>? _running;
  bool _disposed = false;

  LibraryOverview? get overview => _overview;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;

  Future<void> load() => _running ??= _load().whenComplete(() {
    _running = null;
  });

  Future<void> _load() async {
    _isLoading = true;
    _hasError = false;
    notifyListeners();

    try {
      final overview = await _service.load();
      if (_disposed) return;
      _overview = overview;
    } catch (error, stackTrace) {
      developer.log(
        'Library overview could not be loaded. error=${error.runtimeType}',
        name: 'sonus.settings',
        level: 1000,
        stackTrace: stackTrace,
      );
      if (_disposed) return;
      _hasError = true;
    }

    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
