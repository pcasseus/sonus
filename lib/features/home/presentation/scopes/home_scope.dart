import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../analytics/application/services/analytics_entity_ranking_service.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../application/services/home_data_service.dart';
import '../controllers/home_controller.dart';

class HomeScope extends StatefulWidget {
  const HomeScope({super.key, required this.child, this.now});

  final Widget child;
  final HomeControllerNow? now;

  @override
  State<HomeScope> createState() => _HomeScopeState();
}

class _HomeScopeState extends State<HomeScope> {
  LibraryQueryRepository? _library;
  QualifiedPlayRepository? _qualifiedPlays;
  HomeController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final library = context.watch<LibraryQueryRepository?>();
    final qualifiedPlays = context.watch<QualifiedPlayRepository?>();

    if (identical(library, _library) &&
        identical(qualifiedPlays, _qualifiedPlays)) {
      return;
    }

    _library = library;
    _qualifiedPlays = qualifiedPlays;

    _recreateController();
  }

  @override
  void didUpdateWidget(HomeScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.now, widget.now)) {
      _recreateController();
    }
  }

  void _recreateController() {
    final previousController = _controller;
    _controller = null;

    previousController?.dispose();

    final library = _library;
    final qualifiedPlays = _qualifiedPlays;

    if (library == null || qualifiedPlays == null) {
      return;
    }

    final service = HomeDataService(
      library: library,
      analyticsRankings: AnalyticsEntityRankingService(
        qualifiedPlays: qualifiedPlays,
      ),
    );

    final controller = HomeController(service: service, now: widget.now);

    _controller = controller;

    unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HomeController?>.value(
      value: _controller,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
