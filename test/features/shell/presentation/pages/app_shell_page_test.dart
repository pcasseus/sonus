import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/shell/presentation/pages/app_shell_page.dart';

void main() {
  Widget buildSubject() {
    return const MaterialApp(home: AppShellPage());
  }

  testWidgets('shows all five primary destinations', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Hot 100'), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('opens search from the global top bar', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('shell-search-button')));

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('search-page')), findsOneWidget);
  });

  testWidgets('opens imports from the global top bar', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('shell-import-button')));

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('imports-page')), findsOneWidget);
  });

  testWidgets('settings button selects settings destination', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(
      find.byKey(const ValueKey<String>('shell-settings-button')),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-account-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a tab changes the visible destination', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-tracks')));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-tracks')),
      findsOneWidget,
    );
  });

  testWidgets('swiping changes the visible destination', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.drag(find.byType(PageView), const Offset(-500, 0));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-hot100')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the playback slot mounted across destinations', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    expect(
      find.byKey(const ValueKey<String>('shell-playback-slot')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-library')));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('shell-playback-slot')),
      findsOneWidget,
    );
  });

  testWidgets('returns to the selected destination after closing search', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-tracks')));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-tracks')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('shell-search-button')));

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('search-page')), findsOneWidget);

    Navigator.of(
      tester.element(find.byKey(const ValueKey<String>('search-page'))),
    ).pop();

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-tracks')),
      findsOneWidget,
    );
  });

  testWidgets('returns to the selected destination after closing imports', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-library')));

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('shell-import-button')));

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('imports-page')), findsOneWidget);

    Navigator.of(
      tester.element(find.byKey(const ValueKey<String>('imports-page'))),
    ).pop();

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-library')),
      findsOneWidget,
    );
  });
}
