import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../application/controllers/account_controller.dart';
import '../../domain/repositories/account_repository.dart';

class AccountScope extends StatefulWidget {
  const AccountScope({
    super.key,
    required this.repository,
    required this.child,
  });

  final AccountRepository? repository;
  final Widget child;

  @override
  State<AccountScope> createState() => _AccountScopeState();
}

class _AccountScopeState extends State<AccountScope> {
  AccountController? _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(AccountScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.repository, widget.repository)) {
      _controller?.dispose();
      _createController();
    }
  }

  void _createController() {
    final repository = widget.repository;

    if (repository == null) {
      _controller = null;
      return;
    }

    final controller = AccountController(repository: repository);

    controller.initialize();
    _controller = controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (controller == null) {
      return widget.child;
    }

    return ChangeNotifierProvider<AccountController>.value(
      value: controller,
      child: widget.child,
    );
  }
}
