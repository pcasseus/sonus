// App Update 1.2 patches, Checkpoint 3 (BUG-02): moving between Tracks,
// Library and Playlists, by tab or by swipe, makes one transition, keeps
// the tab and the current destination in step, and a swipe that starts on
// a horizontal pager inside a destination still reaches the next one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/shell/application/controllers/app_shell_controller.dart';
import 'package:sonus_next/features/shell/domain/models/app_destination.dart';
import 'package:sonus_next/features/shell/presentation/pages/app_shell_page.dart';

/// Every destination a plain page, except Library: a two-page horizontal
/// pager, as the Artist Roster is.
Widget _page(AppDestination destination, List<AppDestination> seen) {
  if (destination == AppDestination.home) {
    return Builder(
      builder: (context) {
        final shell = context.read<AppShellController>();
        if (seen.isEmpty) {
          seen.add(shell.currentDestination);
          shell.addListener(() => seen.add(shell.currentDestination));
        }
        return const Center(child: Text('home'));
      },
    );
  }
  if (destination == AppDestination.library) {
    return PageView(
      key: const ValueKey<String>('inner-pager'),
      // As the Roster's: a rebuilt Library starts on its first page.
      controller: PageController(keepPage: false),
      children: const [
        Center(child: Text('roster page 1')),
        Center(child: Text('roster page 2')),
      ],
    );
  }
  return Center(child: Text(destination.name));
}

void main() {
  late List<AppDestination> seen;

  Future<void> pumpShell(WidgetTester tester) async {
    seen = [];
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        home: AppShellPage(pageBuilder: (d) => _page(d, seen)),
      ),
    );
    await tester.pumpAndSettle();
  }

  TabController tabs(WidgetTester tester) =>
      tester.widget<TabBar>(find.byType(TabBar)).controller!;

  PageController shellPages(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView).first).controller!;

  /// Taps a destination's tab, scrolling the tab bar to it first (the
  /// later tabs start off-screen on a phone).
  Future<void> tapTab(WidgetTester tester, AppDestination destination) async {
    final tab = find.byKey(ValueKey<String>('app-tab-${destination.name}'));
    await tester.ensureVisible(tab);
    await tester.pump();
    await tester.tap(tab);
  }

  // The tab indicator still passes the tabs in between, as the approved
  // Navigation baselines record; changing that awaits a visual approval.
  testWidgets('a tab several destinations away: the current destination '
      'goes straight there, never through the ones between', (tester) async {
    await pumpShell(tester);

    await tapTab(tester, AppDestination.playlists);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(seen, [AppDestination.home, AppDestination.playlists]);
    expect(tabs(tester).index, AppDestination.playlists.index);
    expect(shellPages(tester).page, AppDestination.playlists.index);
    expect(find.text('playlists'), findsOneWidget);
  });

  testWidgets('Tracks → Library → Playlists by swipes, then back by tabs, '
      'stay in step', (tester) async {
    await pumpShell(tester);
    await tapTab(tester, AppDestination.tracks);
    await tester.pumpAndSettle();

    // Tracks to Library.
    await tester.fling(find.text('tracks'), const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(tabs(tester).index, AppDestination.library.index);
    expect(seen.last, AppDestination.library);

    await tapTab(tester, AppDestination.tracks);
    await tester.pumpAndSettle();
    expect(shellPages(tester).page, AppDestination.tracks.index);
    expect(tabs(tester).index, AppDestination.tracks.index);
    expect(seen.last, AppDestination.tracks);
  });

  testWidgets('swiping past the last page of a pager inside Library moves on '
      'to Playlists, and past its first page back to Tracks', (tester) async {
    await pumpShell(tester);
    await tapTab(tester, AppDestination.library);
    await tester.pumpAndSettle();

    // The inner pager takes the first swipe.
    await tester.fling(find.text('roster page 1'), const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('roster page 2'), findsOneWidget);
    expect(shellPages(tester).page, AppDestination.library.index);

    // At its last page, the swipe carries on to the next destination.
    await tester.drag(find.text('roster page 2'), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(shellPages(tester).page, AppDestination.playlists.index);
    expect(tabs(tester).index, AppDestination.playlists.index);
    expect(seen.last, AppDestination.playlists);

    // Back to Library, to its first page, then past it to Tracks.
    await tapTab(tester, AppDestination.library);
    await tester.pumpAndSettle();
    expect(find.text('roster page 1'), findsOneWidget);
    await tester.drag(find.text('roster page 1'), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(shellPages(tester).page, AppDestination.tracks.index);
    expect(seen.last, AppDestination.tracks);
  });

  testWidgets('a short overscroll on the inner pager settles back on Library', (
    tester,
  ) async {
    await pumpShell(tester);
    await tapTab(tester, AppDestination.library);
    await tester.pumpAndSettle();
    await tester.fling(find.text('roster page 1'), const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();

    await tester.drag(find.text('roster page 2'), const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(shellPages(tester).page, AppDestination.library.index);
    expect(seen.last, AppDestination.library);
  });
}
