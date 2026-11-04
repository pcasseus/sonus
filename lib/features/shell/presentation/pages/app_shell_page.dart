import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_brand_mark.dart';
import '../../../../core/navigation/shell_chrome.dart';
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

  /// Replaces the destination pages, for tests of the shell itself.
  @visibleForTesting
  final Widget Function(AppDestination destination)? pageBuilder;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage>
    with TickerProviderStateMixin {
  late final AppShellController _shellController;
  late final PageController _pageController;
  late final TabController _tabController;

  /// Whether the top bar is shown: the Artist Roster takes the whole
  /// screen (ShellImmersive) and can bring the bar back over itself.
  late final ShellChromeController _chrome;

  /// 1 while the top bar is laid out above the pages, 0 once it has
  /// folded away for an immersive destination.
  late final AnimationController _bar;

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

    _chrome = ShellChromeController(
      current: _shellController.currentDestination,
    )..addListener(_followChrome);
    _bar = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 220),
    );
  }

  void _followChrome() {
    final target = _chrome.showsBar ? 1.0 : 0.0;
    if (_bar.value == target) return;
    final motion = SonusTheme.of(context).motion;
    if (motion.reduced || MediaQuery.disableAnimationsOf(context)) {
      _bar.value = target;
    } else {
      _bar.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  void _selectDestination(AppDestination destination) {
    final motion = SonusTheme.of(context).motion;

    _shellController.selectDestination(destination);
    _chrome
      ..setCurrent(destination)
      ..conceal();

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

    _pageController.animateToPage(
      destination.index,
      duration: motion.medium,
      // Not the theme's curve: an overshooting curve would drag the
      // PageView past its first or last page.
      curve: Curves.easeOutCubic,
    );
  }

  void _handlePageChanged(int index) {
    _shellController.selectIndex(index);
    _chrome.setCurrent(AppDestination.values[index]);

    if (_tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  void _openSearch() {
    _chrome.conceal();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SearchPage()),
      ),
    );
  }

  void _openImports() {
    _chrome.conceal();
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
      child: ShellChromeScope(
        controller: _chrome,
        destination: destination,
        child: page,
      ),
    );
  }

  PreferredSizeWidget _buildTopBar() {
    return AppBar(
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
              text: destination.label,
            ),
        ],
        onTap: (index) {
          _selectDestination(AppDestination.values[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topBar = _buildTopBar();
    final pages = PageView(
      controller: _pageController,
      onPageChanged: _handlePageChanged,
      children: [
        for (final destination in AppDestination.values)
          _buildDestinationPage(destination),
      ],
    );

    return ChangeNotifierProvider<AppShellController>.value(
      value: _shellController,
      child: AnimatedBuilder(
        animation: Listenable.merge([_chrome, _bar]),
        builder: (context, _) {
          final shown = _bar.value;
          final revealed = _chrome.revealed;
          return PopScope(
            // Back hides a bar brought over the Roster before anything else.
            canPop: !revealed,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _chrome.conceal();
            },
            child: Scaffold(
              appBar: shown <= 0
                  ? null
                  : _FoldingTopBar(shown: shown, child: topBar),
              body: Stack(
                children: [
                  Positioned.fill(child: pages),
                  if (revealed) ...[
                    Positioned.fill(
                      child: Semantics(
                        button: true,
                        label: 'Hide Sonus navigation',
                        excludeSemantics: true,
                        child: GestureDetector(
                          key: const ValueKey<String>('shell-revealed-scrim'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _chrome.conceal,
                          child: const ColoredBox(color: Color(0x66000000)),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Material(
                        key: const ValueKey<String>('shell-revealed-bar'),
                        elevation: 6,
                        child: SizedBox(
                          height:
                              topBar.preferredSize.height +
                              MediaQuery.paddingOf(context).top,
                          child: topBar,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _chrome
      ..removeListener(_followChrome)
      ..dispose();
    _bar.dispose();
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

/// The top bar while it folds away (or back): it slides up under the
/// status bar as the pages grow to the top of the screen.
class _FoldingTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _FoldingTopBar({required this.shown, required this.child});

  /// 1 fully shown, 0 folded away.
  final double shown;
  final PreferredSizeWidget child;

  @override
  Size get preferredSize => Size.fromHeight(child.preferredSize.height * shown);

  @override
  Widget build(BuildContext context) {
    if (shown >= 1) return child;
    final full = child.preferredSize.height + MediaQuery.paddingOf(context).top;
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.bottomCenter,
        minHeight: full,
        maxHeight: full,
        child: child,
      ),
    );
  }
}
