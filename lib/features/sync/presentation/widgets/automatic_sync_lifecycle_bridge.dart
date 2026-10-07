import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../account/application/controllers/account_controller.dart';
import '../../application/services/automatic_sync_coordinator.dart';

class AutomaticSyncLifecycleBridge extends StatefulWidget {
  const AutomaticSyncLifecycleBridge({super.key, required this.child});

  final Widget child;

  @override
  State<AutomaticSyncLifecycleBridge> createState() =>
      _AutomaticSyncLifecycleBridgeState();
}

class _AutomaticSyncLifecycleBridgeState
    extends State<AutomaticSyncLifecycleBridge>
    with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  AccountController? _accountController;

  String? _lastUserId;
  bool _initialUpdateScheduled = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) {
      _trigger();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final accountController = context.read<AccountController?>();

    if (!identical(_accountController, accountController)) {
      _accountController?.removeListener(_handleAccountChanged);
      _accountController = accountController;
      _accountController?.addListener(_handleAccountChanged);
    }

    if (!_initialUpdateScheduled) {
      _initialUpdateScheduled = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        _updateAccount();
        _trigger();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateAccount();
      _trigger();
    }
  }

  void _handleAccountChanged() {
    if (!mounted) {
      return;
    }

    final changed = _updateAccount();

    if (changed && _lastUserId != null) {
      _trigger();
    }
  }

  bool _updateAccount() {
    final coordinator = context.read<AutomaticSyncCoordinator?>();

    if (coordinator == null) {
      return false;
    }

    final userId = _accountController?.user?.id.trim();
    final normalizedUserId = userId == null || userId.isEmpty ? null : userId;

    if (_lastUserId == normalizedUserId) {
      return false;
    }

    _lastUserId = normalizedUserId;
    coordinator.updateUserId(normalizedUserId);

    return true;
  }

  void _trigger() {
    if (!mounted || _lastUserId == null) {
      return;
    }

    final coordinator = context.read<AutomaticSyncCoordinator?>();

    if (coordinator == null) {
      return;
    }

    unawaited(coordinator.trigger());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accountController?.removeListener(_handleAccountChanged);
    unawaited(_connectivitySubscription?.cancel());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
