import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/import/application/models/import_execution_summary.dart';
import 'package:sonus_next/features/import/presentation/pages/imports_page.dart';
import 'package:sonus_next/features/import/presentation/widgets/import_error_card.dart';
import 'package:sonus_next/features/import/presentation/widgets/import_folder_structure_card.dart';
import 'package:sonus_next/features/import/presentation/widgets/import_result_card.dart';
import 'package:sonus_next/features/import/presentation/widgets/import_source_card.dart';

// SN-48K3: import cards in every theme. Fictional values.
void main() {
  test('scan times read as a date, not a raw timestamp', () {
    expect(
      formatImportScanTime(DateTime(2026, 10, 5, 14, 7)),
      'October 5, 2026 at 14:07',
    );
  });

  for (final id in SonusThemeId.values) {
    testWidgets('${id.label} import cards fit 320dp at 2x text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 6000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: app!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                ImportSourceCard(
                  icon: Icons.audio_file_rounded,
                  title: 'Import one song',
                  description: 'Choose a single MP3 file.',
                  buttonLabel: 'Choose MP3',
                  onPressed: () {},
                ),
                ImportResultCard(
                  summary: const ImportExecutionSummary(
                    batchId: 'batch-1',
                    totalCount: 120,
                    importedCount: 100,
                    relinkedCount: 10,
                    skippedCount: 5,
                    failedCount: 5,
                  ),
                  reviewCount: 3,
                  onReview: () {},
                  onReset: () {},
                ),
                ImportErrorCard(
                  message: 'The selected folder could not be read.',
                  onReset: () {},
                ),
                const ImportFolderStructureCard(),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Import completed with issues'), findsOneWidget);
    });
  }
}
