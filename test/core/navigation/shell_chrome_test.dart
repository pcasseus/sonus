// The app shell's top bar folds away for a destination that takes the
// whole screen (the Artist Roster), and can be brought back over it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/navigation/shell_chrome.dart';
import 'package:sonus_next/features/shell/domain/models/app_destination.dart';
import 'package:sonus_next/features/shell/presentation/pages/app_shell_page.dart';

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

void main() {
  group('ShellChromeController', () {
    test('a destination is immersive while it holds a request', () {
      final chrome = ShellChromeController(current: 'library');
      addTearDown(chrome.dispose);
      expect(chrome.showsBar, isTrue);

      // Requests arrive through ShellImmersive; simulate two holders.
      final holders = [Object(), Object()];
      for (final _ in holders) {
        chrome.debugRequest('library');
      }
      expect(chrome.immersive, isTrue);
      expect(chrome.showsBar, isFalse);

      chrome.debugRelease('library');
      expect(chrome.immersive, isTrue, reason: 'one holder left');
      chrome.debugRelease('library');
      expect(chrome.immersive, isFalse);
    });

    test('reveal works only over an immersive destination and ends with '
        'a change of destination', () {
      final chrome = ShellChromeController(current: 'home');
      addTearDown(chrome.dispose);

      chrome.reveal();
      expect(chrome.revealed, isFalse, reason: 'the bar is already there');

      chrome
        ..debugRequest('library')
        ..setCurrent('library')
        ..reveal();
      expect(chrome.revealed, isTrue);
      expect(chrome.showsBar, isFalse, reason: 'over the page, not above it');

      chrome.setCurrent('home');
      expect(chrome.revealed, isFalse);
      expect(chrome.showsBar, isTrue);
    });

    test('a request after the shell has gone is ignored', () {
      final chrome = ShellChromeController(current: 'library')..dispose();
      expect(() => chrome.debugRequest('library'), returnsNormally);
      expect(() => chrome.debugRelease('library'), returnsNormally);
    });
  });

  group('the app shell', () {
    Widget shell({bool reduceMotion = false}) => MaterialApp(
      theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: AppShellPage(
        pageBuilder: (destination) => destination == AppDestination.home
            ? const _FullScreenPage()
            : Center(child: Text('${destination.label} page')),
      ),
    );

    testWidgets('folds its bar away while an immersive destination is shown '
        'and brings it back elsewhere', (tester) async {
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();

      expect(byKey('app-tab-home'), findsNothing);
      expect(tester.getTopLeft(byKey('full-screen-page')).dy, 0);

      // Swiping on to the next destination brings the bar back.
      await tester.fling(
        byKey('full-screen-page'),
        const Offset(-400, 0),
        2000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Hot 100 page'), findsOneWidget);
      expect(byKey('app-tab-home'), findsOneWidget);
    });

    testWidgets('the bar comes back over the page, and Back or a tap outside '
        'hides it', (tester) async {
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();
      final before = tester.getRect(byKey('full-screen-page'));

      await tester.tap(byKey('full-screen-show-bar'));
      await tester.pumpAndSettle();
      expect(byKey('shell-revealed-bar'), findsOneWidget);
      expect(byKey('app-tab-home'), findsOneWidget);
      expect(
        tester.getRect(byKey('full-screen-page')),
        before,
        reason: 'over the page, which keeps its layout',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(byKey('shell-revealed-bar'), findsNothing);
      expect(byKey('full-screen-page'), findsOneWidget, reason: 'not popped');

      await tester.tap(byKey('full-screen-show-bar'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 500));
      await tester.pumpAndSettle();
      expect(byKey('shell-revealed-bar'), findsNothing);
    });

    testWidgets('a tab from the revealed bar goes there with the bar', (
      tester,
    ) async {
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();

      await tester.tap(byKey('full-screen-show-bar'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('app-tab-hot100'));
      await tester.pumpAndSettle();

      expect(find.text('Hot 100 page'), findsOneWidget);
      expect(byKey('shell-revealed-bar'), findsNothing);
      expect(byKey('app-tab-home'), findsOneWidget);
    });

    testWidgets('the revealed bar keeps its actions', (tester) async {
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();

      await tester.tap(byKey('full-screen-show-bar'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('shell-settings-button'));
      await tester.pumpAndSettle();

      expect(find.text('Settings page'), findsOneWidget);
      expect(byKey('shell-revealed-bar'), findsNothing);
    });

    testWidgets('with reduced motion the bar folds away at once', (
      tester,
    ) async {
      await tester.pumpWidget(shell(reduceMotion: true));
      await tester.pump();
      await tester.pump();

      expect(byKey('app-tab-home'), findsNothing);
    });

    testWidgets('outside a shell, ShellImmersive does nothing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ShellImmersive(child: Text('alone'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('alone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FullScreenPage extends StatelessWidget {
  const _FullScreenPage();

  @override
  Widget build(BuildContext context) {
    return ShellImmersive(
      child: Container(
        key: const ValueKey<String>('full-screen-page'),
        color: Colors.indigo,
        alignment: Alignment.center,
        child: TextButton(
          key: const ValueKey<String>('full-screen-show-bar'),
          onPressed: ShellChromeScope.revealOf(context),
          child: const Text('Show navigation'),
        ),
      ),
    );
  }
}
