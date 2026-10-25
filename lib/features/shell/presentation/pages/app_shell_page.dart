import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_brand_mark.dart';
import '../../../charts/presentation/pages/charts_page.dart';
import '../../../analytics/presentation/pages/listening_insights_page.dart';
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
  const AppShellPage({super.key});

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

    if (_tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SearchPage()),
      ),
    );
  }

  void _openImports() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ImportsPage()));
  }

  void _openSettings() {
    _selectDestination(AppDestination.settings);
  }

  Widget _buildDestinationPage(AppDestination destination) {
    final Widget page = switch (destination) {
      AppDestination.tracks => const TracksPage(),
      AppDestination.library => const LibraryPage(),
      AppDestination.home => const HomePage(),
      AppDestination.playlists => const PlaylistsPage(),
      AppDestination.settings => const SettingsPage(),
      AppDestination.hot100 => const ChartsPage(),
      AppDestination.insights => const ListeningInsightsPage(),
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
                  text: destination.label,
                ),
            ],
            onTap: (index) {
              _selectDestination(AppDestination.values[index]);
            },
          ),
        ),
        body: PageView(
          controller: _pageController,
          onPageChanged: _handlePageChanged,
          children: [
            for (final destination in AppDestination.values)
              _buildDestinationPage(destination),
          ],
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
