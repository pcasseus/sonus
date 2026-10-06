// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../application/models/year_in_sonus/year_in_sonus_presentation_data.dart';
import '../../application/models/year_in_sonus/year_in_sonus_recap.dart';
import '../../application/services/year_in_sonus/year_in_sonus_enrichment_service.dart';
import '../../application/services/year_in_sonus/year_in_sonus_service.dart';

typedef YearInSonusNow = DateTime Function();

class YearInSonusController extends ChangeNotifier {
  YearInSonusController({
    required YearInSonusLoader service,
    YearInSonusEnricher? enrichment,
    YearInSonusNow? now,
  }) : _service = service,
       _enrichment = enrichment,
       _now = now ?? DateTime.now {
    final current = _now().year;

    _selectedYear = current;
    _currentYear = current;
  }

  final YearInSonusLoader _service;
  final YearInSonusEnricher? _enrichment;
  final YearInSonusNow _now;

  late int _selectedYear;
  late int _currentYear;

  YearInSonusRecap? _recap;
  YearInSonusPresentationData? _presentationData;

  bool _isLoading = false;
  bool _isRefreshing = false;

  Object? _error;

  int _requestGeneration = 0;

  int get selectedYear => _selectedYear;

  int get currentYear => _currentYear;

  YearInSonusRecap? get recap => _recap;

  YearInSonusPresentationData? get presentationData => _presentationData;

  bool get isLoading => _isLoading;

  bool get isRefreshing => _isRefreshing;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get hasData => _recap != null;

  bool get isEmpty => _recap?.hasListening == false;

  bool get canGoNext => _selectedYear < _currentYear;

  Future<void> load() {
    if (_isLoading) {
      return Future.value();
    }

    return _loadSelectedYear(refreshing: false);
  }

  Future<void> refresh() {
    return _loadSelectedYear(refreshing: true);
  }

  Future<void> previousYear() async {
    await selectYear(_selectedYear - 1);
  }

  Future<void> nextYear() async {
    if (!canGoNext) {
      return;
    }

    await selectYear(_selectedYear + 1);
  }

  Future<void> selectYear(int year) async {
    _syncCurrentYear();

    final safeYear = year > _currentYear ? _currentYear : year;

    if (safeYear < 1) {
      throw ArgumentError.value(year, 'year', 'Must be greater than zero.');
    }

    if (safeYear == _selectedYear && _recap != null) {
      return;
    }

    _selectedYear = safeYear;
    _recap = null;
    _presentationData = null;

    await _loadSelectedYear(refreshing: false);
  }

  Future<void> _loadSelectedYear({required bool refreshing}) async {
    final generation = ++_requestGeneration;

    _error = null;

    if (refreshing && _recap != null) {
      _isRefreshing = true;
    } else {
      _isLoading = true;
    }

    notifyListeners();

    try {
      final result = await _service.load(year: _selectedYear);

      if (generation != _requestGeneration) {
        return;
      }

      final enrichment = _enrichment;

      final presentationData = enrichment == null
          ? null
          : await enrichment.enrich(result);

      if (generation != _requestGeneration) {
        return;
      }

      _recap = result;
      _presentationData = presentationData;
    } catch (error) {
      if (generation != _requestGeneration) {
        return;
      }

      _error = error;
    } finally {
      if (generation == _requestGeneration) {
        _isLoading = false;
        _isRefreshing = false;

        notifyListeners();
      }
    }
  }

  void _syncCurrentYear() {
    final resolved = _now().year;

    if (resolved == _currentYear) {
      return;
    }

    _currentYear = resolved;

    if (_selectedYear > _currentYear) {
      _selectedYear = _currentYear;
    }
  }
}
