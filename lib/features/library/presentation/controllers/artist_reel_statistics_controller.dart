import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/artist_library_statistics.dart';

/// Holds every artist's statistics for the Film Reel (UI redesign L1),
/// loaded once and kept until the library or listening history changes.
/// Scrolling the reel never reloads them.
///
/// [refresh] reloads; requests made while a load runs are merged into one
/// more load after it. A failed load keeps the statistics already shown.
class ArtistReelStatisticsController extends ChangeNotifier {
  ArtistReelStatisticsController({required this._load});

  final Future<ArtistLibraryStatisticsSnapshot> Function() _load;

  ArtistLibraryStatisticsSnapshot _snapshot =
      ArtistLibraryStatisticsSnapshot.empty;
  bool _hasLoaded = false;
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;

  ArtistLibraryStatisticsSnapshot get snapshot => _snapshot;

  /// Whether statistics have been loaded at least once.
  bool get hasLoaded => _hasLoaded;

  /// Loads the statistics, or once more after a load already running.
  Future<void> refresh() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _run();
  }

  Future<void> _run() async {
    try {
      do {
        _again = false;
        try {
          final snapshot = await _load();
          if (_disposed) return;
          _snapshot = snapshot;
          _hasLoaded = true;
          notifyListeners();
        } catch (error, stackTrace) {
          developer.log(
            'Artist statistics could not be loaded (${error.runtimeType})',
            name: 'sonus.library.film_reel',
            level: 900,
            error: error,
            stackTrace: stackTrace,
          );
        }
      } while (_again && !_disposed);
    } finally {
      _running = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
