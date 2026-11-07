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

void main() {
  setUpAll(loadBaselineFonts);

  Future<void> pump(
    WidgetTester tester, {
    required SonusAppearanceSpec spec,
    required PermanentDeletionImpact impact,
    double textScale = 1,
    String name = 'Zendaya',
  }) async {
    setDevice(tester);
    await tester.pumpWidget(
      MaterialApp(
        // A fresh app per case: no route of the previous case survives.
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: labTheme(spec),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => RepaintBoundary(
          key: labCaptureKey,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text(name)),
            body: Center(
              child: FilledButton(
                key: const ValueKey<String>('open'),
                onPressed: () => showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => PermanentDeletionSheet(
                    target: impact.target,
                    name: name,
                    loadPreview: (_) async => impact,
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

  final cases =
      <(String, SonusAppearanceSpec, PermanentDeletionImpact, double, bool)>[
        (
          'Release, After Hours',
          const SonusAppearanceSpec(themeId: SonusThemeId.afterHours),
          album,
          1,
          false,
        ),
        (
          'Confirmation, After Hours',
          const SonusAppearanceSpec(themeId: SonusThemeId.afterHours),
          album,
          1,
          true,
        ),
        (
          'Release, Daylight',
          const SonusAppearanceSpec(themeId: SonusThemeId.daylight),
          album,
          1,
          false,
        ),
        (
          'Blocked by the cloud, Monochrome',
          const SonusAppearanceSpec(themeId: SonusThemeId.monochrome),
          blocked,
          1,
          false,
        ),
        (
          'Artist with shared recordings, Neon Mixtape',
          const SonusAppearanceSpec(themeId: SonusThemeId.neonMixtape),
          artist,
          1,
          false,
        ),
        (
          'High contrast + bold',
          const SonusAppearanceSpec(
            themeId: SonusThemeId.afterHours,
            highContrast: true,
            boldText: true,
            lowEffects: true,
            reduceMotion: true,
          ),
          album,
          1,
          false,
        ),
        (
          'Large text (2x)',
          const SonusAppearanceSpec(themeId: SonusThemeId.evergreen),
          album,
          2,
          false,
        ),
        (
          'Confirmation, large text (2x)',
          const SonusAppearanceSpec(themeId: SonusThemeId.evergreen),
          album,
          2,
          true,
        ),
      ];

  testWidgets('permanent-deletion renders', (tester) async {
    final cells = <BoardCell>[];
    for (final (caption, spec, impact, scale, confirm) in cases) {
      await pump(tester, spec: spec, impact: impact, textScale: scale);
      if (confirm) {
        await tester.tap(_key('permanent-deletion-continue'));
        await tester.pumpAndSettle();
        await tester.enterText(
          _key('permanent-deletion-confirm-field'),
          'Zendaya',
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: caption);
      if (_out.isNotEmpty) {
        final (_, image) = await captureLab(tester, pixelRatio: 2);
        cells.add(BoardCell(caption, image));
      }
    }
    if (_out.isNotEmpty) {
      await writeBoard(
        tester,
        '$_out/permanent_deletion_board.png',
        'Permanent deletion (App Update 1.2)',
        [cells.sublist(0, 4), cells.sublist(4)],
      );
    }
  });
}
