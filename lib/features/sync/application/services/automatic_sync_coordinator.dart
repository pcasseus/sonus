import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controllers/sync_controller.dart';
import 'sync_network_policy_service.dart';

class AutomaticSyncCoordinator extends ChangeNotifier {
  AutomaticSyncCoordinator({
    required this._syncController,
    required this._networkPolicy,
  });

  final SyncController _syncController;
  final SyncNetworkPolicyService _networkPolicy;

  String? _userId;
  SyncNetworkAccess? _networkAccess;
  bool _mobileConsentRequired = false;

  String? get userId => _userId;

  SyncNetworkAccess? get networkAccess => _networkAccess;

  bool get mobileConsentRequired => _mobileConsentRequired;

  void updateUserId(String? userId) {
    final normalized = userId?.trim();

    if (normalized == null || normalized.isEmpty) {
      _userId = null;
      _mobileConsentRequired = false;
      _networkAccess = null;
      _syncController.resetForSignedOut();
      notifyListeners();
      return;
    }

    _userId = normalized;
    unawaited(_syncController.activateUser(normalized));
  }

  Future<void> trigger() async {
    final userId = _userId;

    if (userId == null || _syncController.hasAccountConflict) {
      return;
    }

    final decision = await _networkPolicy.evaluate();

    if (_userId != userId || _syncController.hasAccountConflict) {
      return;
    }

    _networkAccess = decision.access;
    _mobileConsentRequired = decision.requiresMobileConsent;
    notifyListeners();

    if (!decision.canSync) {
      return;
    }

    _mobileConsentRequired = false;
    notifyListeners();

    await _syncController.synchronize(userId);
  }

  Future<void> allowMobileDataAndSync() async {
    await _networkPolicy.allowMobileData();

    _mobileConsentRequired = false;
    notifyListeners();

    await trigger();
  }

  Future<void> denyMobileData() async {
    await _networkPolicy.denyMobileData();

    _mobileConsentRequired = false;
    _networkAccess = SyncNetworkAccess.mobileDenied;
    notifyListeners();
  }
}
