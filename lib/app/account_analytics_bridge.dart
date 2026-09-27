import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../features/account/application/controllers/account_controller.dart';
import '../features/analytics/application/controllers/playback_analytics_controller.dart';
import '../features/analytics/application/services/analytics_account_attachment_service.dart';
import '../features/analytics/domain/repositories/playback_session_repository.dart';
import '../features/analytics/domain/repositories/qualified_play_repository.dart';
import '../features/analytics/presentation/scopes/analytics_scope.dart';
import 'account_analytics_attachment_coordinator.dart';

class AccountAnalyticsBridge extends StatefulWidget {
  const AccountAnalyticsBridge({super.key, required this.child});

  final Widget child;

  @override
  State<AccountAnalyticsBridge> createState() => _AccountAnalyticsBridgeState();
}

class _AccountAnalyticsBridgeState extends State<AccountAnalyticsBridge> {
  AccountController? _accountController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _accountController = context.watch<AccountController?>();
  }

  String? _currentUserId() {
    return _normalizedUserId(_accountController);
  }

  @override
  Widget build(BuildContext context) {
    return AnalyticsScope(
      userIdProvider: _currentUserId,
      child: _AnalyticsAccountAttachmentBridge(child: widget.child),
    );
  }
}

class _AnalyticsAccountAttachmentBridge extends StatefulWidget {
  const _AnalyticsAccountAttachmentBridge({required this.child});

  final Widget child;

  @override
  State<_AnalyticsAccountAttachmentBridge> createState() =>
      _AnalyticsAccountAttachmentBridgeState();
}

class _AnalyticsAccountAttachmentBridgeState
    extends State<_AnalyticsAccountAttachmentBridge> {
  PlaybackAnalyticsController? _analyticsController;
  PlaybackSessionRepository? _playbackSessions;
  QualifiedPlayRepository? _qualifiedPlays;

  AccountAnalyticsAttachmentCoordinator? _coordinator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final accountController = context.watch<AccountController?>();
    final analyticsController = context.watch<PlaybackAnalyticsController?>();
    final playbackSessions = context.watch<PlaybackSessionRepository?>();
    final qualifiedPlays = context.watch<QualifiedPlayRepository?>();

    final analyticsDependenciesChanged =
        !identical(analyticsController, _analyticsController) ||
        !identical(playbackSessions, _playbackSessions) ||
        !identical(qualifiedPlays, _qualifiedPlays);

    _analyticsController = analyticsController;
    _playbackSessions = playbackSessions;
    _qualifiedPlays = qualifiedPlays;

    if (analyticsController == null ||
        playbackSessions == null ||
        qualifiedPlays == null) {
      _coordinator = null;
      return;
    }

    if (_coordinator == null || analyticsDependenciesChanged) {
      final attachmentService = AnalyticsAccountAttachmentService(
        playbackSessions: playbackSessions,
        qualifiedPlays: qualifiedPlays,
      );

      _coordinator = AccountAnalyticsAttachmentCoordinator(
        attachActiveSession: analyticsController.attachActiveSessionToUser,
        attachHistoricalAnalytics: attachmentService.attachUnownedToUser,
      );
    }

    _coordinator!.updateUserId(_normalizedUserId(accountController));
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
