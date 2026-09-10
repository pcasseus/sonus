import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';

void main() {
  test('imported and relinked results count as success', () {
    const imported = ImportResult(
      status: ImportResultStatus.imported,
      filePath: 'song.mp3',
      songId: 'song_1',
    );

    const relinked = ImportResult(
      status: ImportResultStatus.relinked,
      filePath: 'song.mp3',
      songId: 'song_1',
    );

    expect(imported.succeeded, isTrue);
    expect(relinked.succeeded, isTrue);
    expect(imported.failed, isFalse);
  });

  test('failed result carries structured failure', () {
    const result = ImportResult(
      status: ImportResultStatus.failed,
      filePath: 'song.mp3',
      failure: ImportFailure(
        type: ImportFailureType.metadataUnreadable,
        message: 'Could not read audio metadata.',
      ),
    );

    expect(result.failed, isTrue);
    expect(result.succeeded, isFalse);
    expect(result.failure?.type, ImportFailureType.metadataUnreadable);
  });
}
