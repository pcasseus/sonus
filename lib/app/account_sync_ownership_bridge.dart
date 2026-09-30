import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/database/app_database.dart';
import '../features/account/application/controllers/account_controller.dart';
import 'account_sync_ownership_attachment_coordinator.dart';
import 'account_sync_ownership_attachment_service.dart';

typedef SyncOwnershipAttachAction = Future<void> Function(String userId);

class AccountSyncOwnershipBridge extends StatefulWidget {
  const AccountSyncOwnershipBridge({
    super.key,
    required this.database,
    required this.child,
    this.attachUnownedOverride,
  });

  final AppDatabase? database;
  final Widget child;

  @visibleForTesting
  final SyncOwnershipAttachAction? attachUnownedOverride;

  @override
  State<AccountSyncOwnershipBridge> createState() =>
      _AccountSyncOwnershipBridgeState();
}

class _AccountSyncOwnershipBridgeState
    extends State<AccountSyncOwnershipBridge> {
  AppDatabase? _configuredDatabase;
  SyncOwnershipAttachAction? _configuredOverride;
  AccountSyncOwnershipAttachmentCoordinator? _coordinator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final accountController = context.watch<AccountController?>();

    _configureCoordinatorIfNeeded();

    _coordinator?.updateUserId(_normalizedUserId(accountController));
  }

  @override
  void didUpdateWidget(AccountSyncOwnershipBridge oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.database, widget.database) ||
        !identical(
          oldWidget.attachUnownedOverride,
          widget.attachUnownedOverride,
        )) {
      _configureCoordinator(force: true);
    }
  }

  void _configureCoordinatorIfNeeded() {
    final needsConfiguration =
        !identical(widget.database, _configuredDatabase) ||
        !identical(widget.attachUnownedOverride, _configuredOverride);

    if (needsConfiguration) {
      _configureCoordinator();
    }
  }

  void _configureCoordinator({bool force = false}) {
    if (!force &&
        identical(widget.database, _configuredDatabase) &&
        identical(widget.attachUnownedOverride, _configuredOverride)) {
      return;
    }

    _configuredDatabase = widget.database;
    _configuredOverride = widget.attachUnownedOverride;

    final override = widget.attachUnownedOverride;

    if (override != null) {
      _coordinator = AccountSyncOwnershipAttachmentCoordinator(
        attachUnowned: override,
      );
      return;
    }

    final database = widget.database;

    if (database == null) {
      _coordinator = null;
      return;
    }

    final service = AccountSyncOwnershipAttachmentService(
      appDatabase: database,
    );

    _coordinator = AccountSyncOwnershipAttachmentCoordinator(
      attachUnowned: (userId) async {
        await service.attachUnownedToUser(userId);
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String? _normalizedUserId(AccountController? controller) {
  final userId = controller?.user?.id.trim();

  if (userId == null || userId.isEmpty) {
    return null;
  }

  return userId;
}
