import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/widgets/sonus_notice_card.dart';
import 'package:sonus_next/core/design/widgets/sonus_surface_card.dart';

// SN-48K3: shared notice and surface cards.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    SonusThemeId theme = SonusThemeId.concreteSpray,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: theme)),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  testWidgets('each tone has its own icon, not only a colour', (tester) async {
    final icons = <SonusNoticeTone, IconData>{};
    for (final tone in SonusNoticeTone.values) {
      await pump(tester, SonusNoticeCard(tone: tone, title: 'Fixture notice'));
      icons[tone] = tester.widget<Icon>(find.byType(Icon)).icon!;
    }

    expect(icons.values.toSet(), hasLength(SonusNoticeTone.values.length));
  });

  testWidgets('wording passes through unchanged and is announced', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      SonusNoticeCard(
        tone: SonusNoticeTone.warning,
        title: 'Restore paused',
        message: 'Cloud sync stays off until you review the restore.',
        actions: [FilledButton(onPressed: () {}, child: const Text('Review'))],
      ),
    );

    expect(
      find.text('Cloud sync stays off until you review the restore.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Restore paused')), findsOneWidget);
    handle.dispose();
  });

  for (final id in SonusThemeId.values) {
    testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
      await pump(
        tester,
        Column(
          children: [
            SonusNoticeCard(
              tone: SonusNoticeTone.error,
              title: 'An unusually long fixture title that must wrap cleanly',
              message: 'A fixture message long enough to wrap several lines.',
              actions: [
                FilledButton(onPressed: () {}, child: const Text('Try again')),
              ],
            ),
            const SonusSurfaceCard(child: Text('Fixture surface')),
          ],
        ),
        theme: id,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  }
}
