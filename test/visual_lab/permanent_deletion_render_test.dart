// App Update 1.2: real Flutter renders of the permanent-deletion sheet and
// its confirmation, for review. Boards are written only with
// --dart-define=SONUS_LAB_OUT=<folder> (outside the repository); without
// it the same layouts are pumped and checked for overflow only. Synthetic
// impacts; no artwork.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';
import 'package:sonus_next/features/library/presentation/widgets/permanent_deletion/permanent_deletion_sheet.dart';

import '../features/library/presentation/widgets/permanent_deletion/permanent_deletion_sheet_test.dart'
    as sheet;
import '../support/device_layout.dart';
import 'support/lab_board.dart';
import 'support/lab_harness.dart';

const String _out = String.fromEnvironment('SONUS_LAB_OUT');

Finder _key(String key) => find.byKey(ValueKey<String>(key));

const _longName =
    'The Cheetah Girls 2 (Original Soundtrack) [Deluxe Edition] - 2026 '
    'Remaster';

class _Case {
  const _Case(
    this.caption,
    this.spec,
    this.impact, {
    this.scale = 1,
    this.confirm = false,
    this.keyboard = false,
    this.size = s26UltraSize,
    this.name = 'Zendaya',
    this.scrollTo,
  });

  final String caption;
  final SonusAppearanceSpec spec;
  final PermanentDeletionImpact impact;
  final double scale;
  final bool confirm;
  final bool keyboard;
  final Size size;
  final String name;
  final String? scrollTo;
}

void main() {
  setUpAll(loadBaselineFonts);

  Future<void> pump(WidgetTester tester, _Case c) async {
    setDevice(tester, size: c.size);
    await tester.pumpWidget(
      MaterialApp(
        // A fresh app per case: no route of the previous case survives.
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: labTheme(c.spec),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => RepaintBoundary(
          key: labCaptureKey,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(c.scale)),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Zendaya')),
            body: Center(
              child: FilledButton(
                key: const ValueKey<String>('open'),
                onPressed: () => showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => PermanentDeletionSheet(
                    target: c.impact.target,
                    name: c.name,
                    loadPreview: (_) async => c.impact,
                    delete: (i, _) async => i,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(_key('open'));
    await tester.pumpAndSettle();
    final scrollTo = c.scrollTo;
    if (scrollTo != null) {
      await tester.scrollUntilVisible(
        _key(scrollTo),
        120,
        scrollable: find
            .descendant(
              of: _key('permanent-deletion-sheet'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
    }
    if (c.confirm) {
      await tester.tap(_key('permanent-deletion-continue'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('permanent-deletion-confirm-field'), c.name);
      await tester.pumpAndSettle();
      if (c.keyboard) {
        tester.view.viewInsets = const FakeViewPadding(
          bottom: 300 * s26UltraRatio,
        );
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(_key('permanent-deletion-confirm-field'));
      await tester.pumpAndSettle();
    }
  }

  final album = sheet.impact();
  final blocked = sheet.impact(
    blockers: {PermanentDeletionBlocker.cloudDeletionUnavailable},
  );
  final artist = sheet.impact(
    target: const PermanentDeletionTarget.artist('artist_zendaya'),
    shared: const {'guest'},
    blockers: {PermanentDeletionBlocker.sharedRecordingsNotConfirmed},
  );
  const afterHours = SonusAppearanceSpec(themeId: SonusThemeId.afterHours);
  const evergreen = SonusAppearanceSpec(themeId: SonusThemeId.evergreen);

  final cases = [
    _Case('Release, 1x', afterHours, album),
    _Case('Confirmation, 1x', afterHours, album, confirm: true),
    _Case(
      'Cloud blocked (new wording)',
      const SonusAppearanceSpec(themeId: SonusThemeId.monochrome),
      blocked,
      scrollTo: 'permanent-deletion-cloud-unavailable',
    ),
    _Case(
      'Shared recordings',
      const SonusAppearanceSpec(themeId: SonusThemeId.neonMixtape),
      artist,
      scrollTo: 'permanent-deletion-include-shared',
    ),
    _Case('Release, 1.3x', evergreen, album, scale: 1.3),
    _Case('Confirmation, 1.3x', evergreen, album, scale: 1.3, confirm: true),
    _Case('Release, 2x', evergreen, album, scale: 2),
    _Case('Confirmation, 2x', evergreen, album, scale: 2, confirm: true),
    _Case(
      'Confirmation, 2x, keyboard open',
      evergreen,
      album,
      scale: 2,
      confirm: true,
      keyboard: true,
    ),
    _Case(
      'Narrow 320dp, 2x',
      afterHours,
      album,
      scale: 2,
      size: const Size(320, 640),
    ),
    _Case(
      'Narrow 320dp, 2x, confirmation',
      afterHours,
      album,
      scale: 2,
      size: const Size(320, 640),
      confirm: true,
    ),
    _Case(
      'Long name, 1.3x, confirmation',
      const SonusAppearanceSpec(
        themeId: SonusThemeId.afterHours,
        highContrast: true,
        boldText: true,
      ),
      album,
      scale: 1.3,
      confirm: true,
      name: _longName,
    ),
  ];

  testWidgets('permanent-deletion renders', (tester) async {
    final cells = <BoardCell>[];
    for (final c in cases) {
      await pump(tester, c);
      expect(tester.takeException(), isNull, reason: c.caption);
      if (_out.isNotEmpty) {
        final (_, image) = await captureLab(tester, pixelRatio: 2);
        cells.add(BoardCell(c.caption, image));
      }
      tester.view.resetViewInsets();
    }
    if (_out.isNotEmpty) {
      await writeBoard(
        tester,
        '$_out/permanent_deletion_board_v2.png',
        'Permanent deletion: large text, narrow screens, keyboard',
        [cells.sublist(0, 4), cells.sublist(4, 8), cells.sublist(8)],
      );
    }
  });
}
