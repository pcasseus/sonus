// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../application/models/monthly_insights/monthly_listening_insights.dart';
import '../../application/models/monthly_insights/monthly_listening_insights_presentation_data.dart';
import '../../application/services/monthly_insights/monthly_listening_insights_enrichment_service.dart';
import '../../application/services/monthly_insights/monthly_listening_insights_service.dart';

typedef MonthlyListeningInsightsNow = DateTime Function();

class MonthlyListeningInsightsController extends ChangeNotifier {
  MonthlyListeningInsightsController({
    required MonthlyListeningInsightsLoader service,
    MonthlyListeningInsightsEnricher? enrichment,
    MonthlyListeningInsightsNow? now,
  }) : _service = service,
       _enrichment = enrichment,
       _now = now ?? DateTime.now {
    final current = _monthStart(_now());

    _selectedMonth = current;
    _currentMonth = current;
  }

  final MonthlyListeningInsightsLoader _service;
  final MonthlyListeningInsightsEnricher? _enrichment;
  final MonthlyListeningInsightsNow _now;

  late DateTime _selectedMonth;
  late DateTime _currentMonth;

  MonthlyListeningInsights? _insights;
  MonthlyListeningInsightsPresentationData? _presentationData;

  bool _isLoading = false;
  bool _isRefreshing = false;

  Object? _error;

  int _requestGeneration = 0;

  DateTime get selectedMonth => _selectedMonth;

  DateTime get currentMonth => _currentMonth;

  MonthlyListeningInsights? get insights => _insights;

  MonthlyListeningInsightsPresentationData? get presentationData =>
      _presentationData;

  bool get isLoading => _isLoading;

  bool get isRefreshing => _isRefreshing;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get hasData => _insights != null;

  bool get isEmpty => _insights?.hasListening == false;

  bool get canGoNext => _selectedMonth.isBefore(_currentMonth);

  Future<void> load() {
    if (_isLoading) {
      return Future.value();
    }

    return _loadSelectedMonth(refreshing: false);
  }

  Future<void> refresh() {
    return _loadSelectedMonth(refreshing: true);
  }

  Future<void> previousMonth() async {
    final previous = DateTime(_selectedMonth.year, _selectedMonth.month - 1);

    await selectMonth(previous);
  }

  Future<void> nextMonth() async {
    if (!canGoNext) {
      return;
    }

    final next = DateTime(_selectedMonth.year, _selectedMonth.month + 1);

    await selectMonth(next);
  }

  Future<void> selectMonth(DateTime month) async {
    _syncCurrentMonth();

    final normalized = _monthStart(month);

    final safeMonth = normalized.isAfter(_currentMonth)
        ? _currentMonth
        : normalized;

    if (safeMonth == _selectedMonth && _insights != null) {
      return;
    }

    _selectedMonth = safeMonth;
    _insights = null;
    _presentationData = null;

    await _loadSelectedMonth(refreshing: false);
  }

  Future<void> _loadSelectedMonth({required bool refreshing}) async {
    final generation = ++_requestGeneration;

    _error = null;

    if (refreshing && _insights != null) {
      _isRefreshing = true;
    } else {
      _isLoading = true;
    }

    notifyListeners();

    try {
      final result = await _service.load(referenceLocal: _selectedMonth);

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

      _insights = result;
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

  void _syncCurrentMonth() {
    final resolved = _monthStart(_now());

    if (resolved == _currentMonth) {
      return;
    }

    _currentMonth = resolved;

    if (_selectedMonth.isAfter(_currentMonth)) {
      _selectedMonth = _currentMonth;
    }
  }

  static DateTime _monthStart(DateTime value) {
    return DateTime(value.year, value.month);
  }
}
