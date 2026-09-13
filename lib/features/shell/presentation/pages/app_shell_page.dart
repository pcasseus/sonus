import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../import/presentation/pages/imports_page.dart';
import '../../../library/presentation/pages/library_page.dart';
import '../../../library/presentation/pages/tracks_page.dart';
import '../../../search/presentation/pages/search_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../application/controllers/app_shell_controller.dart';
import '../../domain/models/app_destination.dart';
import '../widgets/app_destination_placeholder.dart';
import '../widgets/shell_playback_slot.dart';

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
    _shellController.selectDestination(destination);

    if (_tabController.index != destination.index) {
      _tabController.animateTo(destination.index);
    }

    if (!_pageController.hasClients) {
      return;
    }

    _pageController.animateToPage(
      destination.index,
      duration: const Duration(milliseconds: 250),
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SearchPage()));
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
    final Widget page = switch (destination) {
      AppDestination.tracks => const TracksPage(),
      AppDestination.library => const LibraryPage(),
      AppDestination.settings => const SettingsPage(),
      AppDestination.home || AppDestination.hot100 => AppDestinationPlaceholder(
        destination: destination,
      ),
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
        bottomNavigationBar: const ShellPlaybackSlot(),
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
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.graphic_eq_rounded, key: ValueKey<String>('sonus-app-mark')),
        SizedBox(width: 8),
        Text('Sonus', key: ValueKey<String>('sonus-app-title')),
      ],
    );
  }
}
