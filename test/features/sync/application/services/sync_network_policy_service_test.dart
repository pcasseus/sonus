import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/application/services/sync_network_policy_service.dart';

void main() {
  test('allows Wi-Fi automatically', () async {
    final service = _service(connectivity: [ConnectivityResult.wifi]);

    final decision = await service.evaluate();

    expect(decision.access, SyncNetworkAccess.allowed);
    expect(decision.canSync, isTrue);
  });

  test('allows Ethernet automatically', () async {
    final service = _service(connectivity: [ConnectivityResult.ethernet]);

    final decision = await service.evaluate();

    expect(decision.access, SyncNetworkAccess.allowed);
  });

  test('prefers Wi-Fi when Wi-Fi and mobile are both reported', () async {
    final service = _service(
      connectivity: [ConnectivityResult.mobile, ConnectivityResult.wifi],
    );

    final decision = await service.evaluate();

    expect(decision.access, SyncNetworkAccess.allowed);
  });

  test('reports offline when no connectivity is available', () async {
    final service = _service(connectivity: [ConnectivityResult.none]);

    final decision = await service.evaluate();

    expect(decision.access, SyncNetworkAccess.offline);
    expect(decision.canSync, isFalse);
  });

  test(
    'requires consent when mobile data choice has never been made',
    () async {
      final service = _service(
        connectivity: [ConnectivityResult.mobile],
        mobileDataAllowed: null,
      );

      final decision = await service.evaluate();

      expect(decision.access, SyncNetworkAccess.mobileConsentRequired);
      expect(decision.requiresMobileConsent, isTrue);
    },
  );

  test('allows mobile data after consent', () async {
    final service = _service(
      connectivity: [ConnectivityResult.mobile],
      mobileDataAllowed: true,
    );

    final decision = await service.evaluate();

    expect(decision.access, SyncNetworkAccess.allowed);
  });

  test('does not sync over mobile data after denial', () async {
    final service = _service(
      connectivity: [ConnectivityResult.mobile],
      mobileDataAllowed: false,
    );

    final decision = await service.evaluate();

    expect(decision.access, SyncNetworkAccess.mobileDenied);
    expect(decision.canSync, isFalse);
  });

  test('persists mobile-data consent', () async {
    final writes = <String, bool>{};

    final service = SyncNetworkPolicyService.forTesting(
      checkConnectivity: () async => [ConnectivityResult.mobile],
      getBool: (key) async => writes[key],
      setBool: (key, value) async {
        writes[key] = value;
      },
      remove: (key) async {
        writes.remove(key);
      },
    );

    await service.allowMobileData();

    expect(
      writes[SyncNetworkPolicyService.mobileDataAllowedPreferenceKey],
      isTrue,
    );

    final decision = await service.evaluate();

    expect(decision.access, SyncNetworkAccess.allowed);
  });

  test('persists mobile-data denial', () async {
    final writes = <String, bool>{};

    final service = SyncNetworkPolicyService.forTesting(
      checkConnectivity: () async => [ConnectivityResult.mobile],
      getBool: (key) async => writes[key],
      setBool: (key, value) async {
        writes[key] = value;
      },
      remove: (key) async {
        writes.remove(key);
      },
    );

    await service.denyMobileData();

    expect(
      writes[SyncNetworkPolicyService.mobileDataAllowedPreferenceKey],
      isFalse,
    );

    final decision = await service.evaluate();

    expect(decision.access, SyncNetworkAccess.mobileDenied);
  });

  test('can reset the mobile-data choice', () async {
    final writes = <String, bool>{
      SyncNetworkPolicyService.mobileDataAllowedPreferenceKey: true,
    };

    final service = SyncNetworkPolicyService.forTesting(
      checkConnectivity: () async => [ConnectivityResult.mobile],
      getBool: (key) async => writes[key],
      setBool: (key, value) async {
        writes[key] = value;
      },
      remove: (key) async {
        writes.remove(key);
      },
    );

    await service.resetMobileDataChoice();

    expect(writes, isEmpty);

    final decision = await service.evaluate();

    expect(decision.access, SyncNetworkAccess.mobileConsentRequired);
  });

  test('does not assume an unknown transport is safe', () async {
    final service = _service(connectivity: [ConnectivityResult.other]);

    final decision = await service.evaluate();

    expect(decision.access, SyncNetworkAccess.unsupported);
  });
}

SyncNetworkPolicyService _service({
  required List<ConnectivityResult> connectivity,
  bool? mobileDataAllowed,
}) {
  return SyncNetworkPolicyService.forTesting(
    checkConnectivity: () async => connectivity,
    getBool: (_) async => mobileDataAllowed,
    setBool: (_, _) async {},
    remove: (_) async {},
  );
}
