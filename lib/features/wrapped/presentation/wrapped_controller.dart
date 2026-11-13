// ignore_for_file: prefer_initializing_formals

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../analytics/application/models/pulse/pulse_period.dart';
import '../application/wrapped_service.dart';
import '../application/wrapped_summary.dart';

/// Holds Sonus Wrapped's archive and the summaries viewed in this visit.
///
/// Summaries are kept only while Wrapped is open and only until recorded
/// listening or the library changes ([invalidate]); nothing is stored, so a
/// summary can never contradict the history it was built from.
class WrappedController extends ChangeNotifier {
  WrappedController({required WrappedLoader loader}) : _loader = loader;

  final WrappedLoader _loader;

  WrappedArchive _archive = WrappedArchive.empty;
  bool _archiveLoaded = false;
  bool _archiveFailed = false;
  int _generation = 0;
  final Map<PulsePeriod, Future<WrappedSummary>> _summaries = {};

  WrappedArchive get archive => _archive;
  bool get archiveLoaded => _archiveLoaded;
  bool get archiveFailed => _archiveFailed;

  /// Changes whenever cached summaries are dropped, so views reload.
  int get generation => _generation;

  Future<void> initialize() => _loadArchive();

  Future<void> _loadArchive() async {
    final generation = _generation;
    try {
      final archive = await _loader.archive();
      if (generation != _generation) return;
      _archive = archive;
      _archiveFailed = false;
    } catch (error, stackTrace) {
      developer.log(
        'Sonus Wrapped could not list its periods',
        name: 'sonus.wrapped',
        error: error,
        stackTrace: stackTrace,
      );
      _archiveFailed = true;
    }
    _archiveLoaded = true;
    notifyListeners();
  }

  /// [period]'s summary, loaded once per visit unless history changes. A
  /// failed load is forgotten so the next request tries again.
  Future<WrappedSummary> summary(PulsePeriod period) {
    return _summaries[period] ??= _loader.load(period).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _summaries.remove(period);
      developer.log(
        'Sonus Wrapped could not load $period',
        name: 'sonus.wrapped',
        error: error,
        stackTrace: stackTrace,
      );
      throw error;
    });
  }

  /// Recorded listening or the library changed (a play, an edit, a merge
  /// or a deletion): every summary is rebuilt from history on next view.
  void invalidate() {
    _generation++;
    _summaries.clear();
    notifyListeners();
    _loadArchive();
  }
}
