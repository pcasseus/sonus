import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_brand_mark.dart';
import '../../../charts/presentation/pages/charts_page.dart';
import '../../../analytics/presentation/pages/pulse_insights_page.dart';
import '../../../home/presentation/pages/home_page.dart';
import '../../../import/presentation/pages/imports_page.dart';
import '../../../library/presentation/pages/library_page.dart';
import '../../../library/presentation/pages/tracks_page.dart';
import '../../../playlists/presentation/pages/playlists_page.dart';
import '../../../search/presentation/pages/search_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../application/controllers/app_shell_controller.dart';
import '../../domain/models/app_destination.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({super.key, this.pageBuilder});

  /// Replaces the destination pages, for tests of pages inside the shell.
  @visibleForTesting
  final Widget Function(AppDestination destination)? pageBuilder;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage>
    with SingleTickerProviderStateMixin {
  late final AppShellController _shellController;
  late final PageController _pageController;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();

    _shellController = AppShellController();

    _pageController = PageController(
      initialPage: _shellController.currentIndex,
    );

    _tabController = TabController(
      length: AppDestination.values.length,
      vsync: this,
      initialIndex: _shellController.currentIndex,
    );
    _tabController.addListener(_handleTabChange);
  }

  void _selectDestination(AppDestination destination) {
    final motion = SonusTheme.of(context).motion;

    _shellController.selectDestination(destination);

    if (_tabController.index != destination.index) {
      _tabController.animateTo(
        destination.index,
        duration: motion.reduced ? Duration.zero : kTabScrollDuration,
      );
    }

    if (!_pageController.hasClients) {
      return;
    }

    // Reduced motion switches destinations without sliding through the
    // pages in between.
    if (motion.reduced) {
      _pageController.jumpToPage(destination.index);
      return;
    }

    _animatingTo = destination.index;
    _pageController.animateToPage(
      destination.index,
      duration: motion.medium,
      // Not the theme's curve: an overshooting curve would drag the
      // PageView past its first or last page.
      curve: Curves.easeOutCubic,
    );
  }

  /// App Update 1.2 (BUG-02): the destination a tab tap is sliding to.
  /// The slide passes the pages in between, which report themselves as it
  /// goes; they must not make the current destination pass back through
  /// them (each one briefly became "current"). Cleared on arrival, or when
  /// the listener takes over with a drag.
  int? _animatingTo;

  /// Each tab's label, to centre the selected tab once it has settled.
  final Map<AppDestination, GlobalKey> _tabLabels = {
    for (final destination in AppDestination.values) destination: GlobalKey(),
  };

  /// App Update 1.2 (BUG-02): the tab bar centres the selected tab when
  /// the index changes, while the selected label is still turning bold
  /// and the others back to regular, so tab widths are still changing and
  /// it settles off centre (by about 0.6 to 0.7 dp, either way, depending
  /// on how the change was made). Once the change is complete and the
  /// final labels are laid out, the selected tab is centred on its real
  /// width (or as near as the bar's ends allow).
  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    final label = _tabLabels[AppDestination.values[_tabController.index]]!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = label.currentContext;
      if (!mounted || context == null || _tabController.indexIsChanging) {
        return;
      }
      final motion = SonusTheme.of(this.context).motion;
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: motion.short,
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _handlePageChanged(int index) {
    final target = _animatingTo;
    if (target != null) {
      // Neither the current destination nor the tab indicator follows the
      // pages the slide passes: the tab already went to the target.
      if (index != target) return;
      _animatingTo = null;
    }

    _shellController.selectIndex(index);

    if (_tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  /// App Update 1.2 (BUG-02): a horizontal list or pager inside a
  /// destination (the Artist Roster's pages, a Home rail) holds the swipe,
  /// so at its first or last item the swipe went nowhere and the next
  /// destination could not be reached from there. Its overscroll now moves
  /// the destinations on, and when the drag ends they settle on the
  /// nearest one, as a swipe anywhere else does.
  bool _handOff = false;

  bool _handleNestedScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) return false;

    if (notification.depth == 0) {
      // The destinations themselves: a drag takes over from a tab slide.
      if (notification is ScrollStartNotification &&
          notification.dragDetails != null) {
        _animatingTo = null;
      }
      return false;
    }

    if (!_pageController.hasClients) return false;
    final position = _pageController.position;

    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      _animatingTo = null;
      _handOff = true;
      position.jumpTo(
        (position.pixels + notification.overscroll).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    } else if (_handOff && notification is ScrollEndNotification) {
      _handOff = false;
      final page = (_pageController.page ?? 0).round();
      final motion = SonusTheme.of(context).motion;
      if (motion.reduced) {
        _pageController.jumpToPage(page);
      } else {
        unawaited(
          _pageController.animateToPage(
            page,
            duration: motion.short,
            curve: Curves.easeOutCubic,
          ),
        );
      }
    }
    return false;
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SearchPage()),
      ),
    );
  }

  void _openImports() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ImportsPage()));
  }

  void _openSettings() {
    _selectDestination(AppDestination.settings);
  }

  Widget _buildDestinationPage(AppDestination destination) {
    final custom = widget.pageBuilder;
    final Widget page = custom != null
        ? custom(destination)
        : switch (destination) {
            AppDestination.tracks => const TracksPage(),
            AppDestination.library => const LibraryPage(),
            AppDestination.home => const HomePage(),
            AppDestination.playlists => const PlaylistsPage(),
            AppDestination.settings => const SettingsPage(),
            AppDestination.hot100 => const ChartsPage(),
            // Sonus Pulse 2.0 replaces the Monthly/Year layouts (which remain
            // available elsewhere, e.g. Monthly in Listening settings).
            AppDestination.insights => const PulseInsightsPage(),
          };

    return KeyedSubtree(
      key: PageStorageKey<String>('app-page-${destination.name}'),
      child: page,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppShellController>.value(
      value: _shellController,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: const _SonusAppTitle(),
          actions: [
            IconButton(
              key: const ValueKey<String>('shell-search-button'),
              tooltip: 'Search',
              onPressed: _openSearch,
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              key: const ValueKey<String>('shell-import-button'),
              tooltip: 'Imports',
              onPressed: _openImports,
              icon: const Icon(Icons.add_rounded),
            ),
            IconButton(
              key: const ValueKey<String>('shell-settings-button'),
              tooltip: 'Settings',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_rounded),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: [
              for (final destination in AppDestination.values)
                Tab(
                  key: ValueKey<String>('app-tab-${destination.name}'),
                  // As Tab(text:) builds it, keyed so it can be centred.
                  child: KeyedSubtree(
                    key: _tabLabels[destination],
                    child: Text(
                      destination.label,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ),
            ],
            onTap: (index) {
              _selectDestination(AppDestination.values[index]);
            },
          ),
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: _handleNestedScroll,
          child: PageView(
            controller: _pageController,
            onPageChanged: _handlePageChanged,
            children: [
              for (final destination in AppDestination.values)
                _buildDestinationPage(destination),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    _shellController.dispose();

    super.dispose();
  }
}

class _SonusAppTitle extends StatelessWidget {
  const _SonusAppTitle();

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The wordmark beside it already reads "Sonus", so the mark is
        // hidden from screen readers to avoid announcing the name twice.
        const ExcludeSemantics(
          child: SonusBrandMark(
            key: ValueKey<String>('sonus-app-mark'),
            concept: SonusBrandConcept.selected,
            style: SonusBrandMarkStyle.theme,
            size: 30,
          ),
        ),
        const SizedBox(width: 8),
        // Display headings are larger than the default title; on narrow
        // screens or with large text the wordmark shrinks rather than
        // overflowing the actions.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Sonus',
              key: const ValueKey<String>('sonus-app-title'),
              style: tokens.text.sectionHeading.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
