typedef AnalyticsUserAttachment = Future<void> Function(String userId);

class AccountAnalyticsAttachmentCoordinator {
  AccountAnalyticsAttachmentCoordinator({
    required this._attachActiveSession,
    required this._attachHistoricalAnalytics,
  });

  final AnalyticsUserAttachment _attachActiveSession;
  final AnalyticsUserAttachment _attachHistoricalAnalytics;

  Future<void> _pending = Future<void>.value();

  String? _currentUserId;
  String? _attachedUserId;
  String? _failedUserId;

  Object? _lastError;

  String? get currentUserId => _currentUserId;

  String? get attachedUserId => _attachedUserId;

  String? get failedUserId => _failedUserId;

  Object? get lastError => _lastError;

  Future<void> get settled => _pending;

  void updateUserId(String? userId) {
    final normalizedUserId = _normalizeUserId(userId);

    _currentUserId = normalizedUserId;

    if (normalizedUserId == null) {
      _attachedUserId = null;
      _failedUserId = null;
      _lastError = null;
    } else if (normalizedUserId != _failedUserId) {
      _failedUserId = null;
    }

    _pending = _pending.then((_) => _attachIfNeeded(normalizedUserId));
  }

  Future<void> _attachIfNeeded(String? requestedUserId) async {
    if (requestedUserId == null ||
        requestedUserId != _currentUserId ||
        requestedUserId == _attachedUserId ||
        requestedUserId == _failedUserId) {
      return;
    }

    try {
      await _attachActiveSession(requestedUserId);

      if (requestedUserId != _currentUserId) {
        return;
      }

      await _attachHistoricalAnalytics(requestedUserId);

      if (requestedUserId != _currentUserId) {
        return;
      }

      _attachedUserId = requestedUserId;
      _failedUserId = null;
      _lastError = null;
    } catch (error) {
      if (requestedUserId == _currentUserId) {
        _failedUserId = requestedUserId;
        _lastError = error;
      }
    }
  }

  static String? _normalizeUserId(String? userId) {
    final normalized = userId?.trim();

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }
}
