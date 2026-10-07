import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncNetworkAccess {
  allowed,
  offline,
  mobileConsentRequired,
  mobileDenied,
  unsupported,
}

class SyncNetworkDecision {
  const SyncNetworkDecision({required this.access, required this.connectivity});

  final SyncNetworkAccess access;
  final List<ConnectivityResult> connectivity;

  bool get canSync => access == SyncNetworkAccess.allowed;

  bool get requiresMobileConsent =>
      access == SyncNetworkAccess.mobileConsentRequired;
}

class SyncNetworkPolicyService {
  SyncNetworkPolicyService({
    Connectivity? connectivity,
    SharedPreferencesAsync? preferences,
  }) : _checkConnectivity = (connectivity ?? Connectivity()).checkConnectivity,
       _getBool = (preferences ?? SharedPreferencesAsync()).getBool,
       _setBool = (preferences ?? SharedPreferencesAsync()).setBool,
       _remove = (preferences ?? SharedPreferencesAsync()).remove;

  @visibleForTesting
  SyncNetworkPolicyService.forTesting({
    required this._checkConnectivity,
    required this._getBool,
    required this._setBool,
    required this._remove,
  });

  static const String mobileDataAllowedPreferenceKey =
      'sync.mobile_data_allowed';

  final Future<List<ConnectivityResult>> Function() _checkConnectivity;
  final Future<bool?> Function(String key) _getBool;
  final Future<void> Function(String key, bool value) _setBool;
  final Future<void> Function(String key) _remove;

  Future<bool?> get mobileDataAllowed {
    return _getBool(mobileDataAllowedPreferenceKey);
  }

  Future<void> allowMobileData() {
    return _setBool(mobileDataAllowedPreferenceKey, true);
  }

  Future<void> denyMobileData() {
    return _setBool(mobileDataAllowedPreferenceKey, false);
  }

  Future<void> resetMobileDataChoice() {
    return _remove(mobileDataAllowedPreferenceKey);
  }

  Future<SyncNetworkDecision> evaluate() async {
    final connectivity = await _checkConnectivity();

    if (_isOffline(connectivity)) {
      return SyncNetworkDecision(
        access: SyncNetworkAccess.offline,
        connectivity: connectivity,
      );
    }

    if (_hasAutomaticallyAllowedTransport(connectivity)) {
      return SyncNetworkDecision(
        access: SyncNetworkAccess.allowed,
        connectivity: connectivity,
      );
    }

    if (connectivity.contains(ConnectivityResult.mobile)) {
      final allowed = await mobileDataAllowed;

      if (allowed == true) {
        return SyncNetworkDecision(
          access: SyncNetworkAccess.allowed,
          connectivity: connectivity,
        );
      }

      if (allowed == false) {
        return SyncNetworkDecision(
          access: SyncNetworkAccess.mobileDenied,
          connectivity: connectivity,
        );
      }

      return SyncNetworkDecision(
        access: SyncNetworkAccess.mobileConsentRequired,
        connectivity: connectivity,
      );
    }

    return SyncNetworkDecision(
      access: SyncNetworkAccess.unsupported,
      connectivity: connectivity,
    );
  }

  bool _isOffline(List<ConnectivityResult> connectivity) {
    return connectivity.isEmpty ||
        (connectivity.length == 1 &&
            connectivity.single == ConnectivityResult.none);
  }

  bool _hasAutomaticallyAllowedTransport(
    List<ConnectivityResult> connectivity,
  ) {
    return connectivity.contains(ConnectivityResult.wifi) ||
        connectivity.contains(ConnectivityResult.ethernet);
  }
}
