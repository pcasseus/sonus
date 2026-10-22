import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/recovery/application/services/restore_journal_store.dart';

import '../../../../support/recovery_fixtures.dart';

/// A05: the restore journal is treated as untrusted input. Cleanup deletes
/// only files provably created by the journal's own session inside managed
/// artwork storage, and only that session's extraction folder.
void main() {
  sqfliteFfiInit();

  late Directory root;
  late Directory artworkDir;
  late Directory recoveryDir;
  late Directory outside;
  late AppDatabase database;
  late RestoreJournalStore store;
  late RestoreJournalRecovery recovery;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_journal_');
    final support = Directory(path.join(root.path, 'support', 'sonus'));
    artworkDir = Directory(path.join(support.path, 'artwork'));
    recoveryDir = Directory(path.join(support.path, 'recovery'));
    outside = Directory(path.join(root.path, 'user-files'));
    await artworkDir.create(recursive: true);
    await recoveryDir.create(recursive: true);
    await outside.create(recursive: true);

    database = fileAppDatabase(root, 'journal.db');
    store = RestoreJournalStore(directory: () async => recoveryDir);
    recovery = RestoreJournalRecovery(
      journalStore: store,
      artworkDirectory: () async => artworkDir,
    );
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> fileAt(
    Directory directory,
    String name, [
    List<int>? bytes,
  ]) async {
    final file = File(path.join(directory.path, name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes ?? [1, 2, 3]);
    return file;
  }

  Future<RestoreJournalCleanup?> recover(RestoreJournal journal) async {
    await store.write(journal);
    return recovery.recover(await database.database);
  }

  RestoreJournal journal({
    String sessionId = 'sessionA',
    String? extraction,
    List<String> tokens = const ['restoresessionAn0'],
    List<String> created = const [],
  }) => RestoreJournal(
    sessionId: sessionId,
    extractionDirectory:
        extraction ?? path.join(recoveryDir.path, '.sonus_restore_$sessionId'),
    reservedTokens: tokens,
    createdFiles: created,
  );

  test(
    'a well-formed journal still removes its own files and folder',
    () async {
      final orphan = await fileAt(artworkDir, 'artwork_restoresessionAn0.jpg');
      final reservedOnly = await fileAt(
        artworkDir,
        'artwork_restoresessionAn1.png',
      );
      final extraction = Directory(
        path.join(recoveryDir.path, '.sonus_restore_sessionA'),
      );
      await fileAt(extraction, 'data/backup.json');

      final cleanup = await recover(
        journal(
          tokens: const ['restoresessionAn0', 'restoresessionAn1'],
          created: [orphan.path],
        ),
      );

      expect(await orphan.exists(), isFalse);
      expect(await reservedOnly.exists(), isFalse);
      expect(await extraction.exists(), isFalse);
      expect(cleanup!.rejectedEntries, isEmpty);
      expect(await store.read(), isNull);
    },
  );

  test('a referenced file is kept even when the journal lists it', () async {
    final installed = await fileAt(artworkDir, 'artwork_restoresessionAn0.jpg');
    await seedConnectedLibrary(
      await database.database,
      key: 'a',
      artworkPath: installed.path,
    );

    final cleanup = await recover(journal(created: [installed.path]));

    expect(await installed.exists(), isTrue);
    expect(cleanup!.keptReferencedFiles, [installed.path]);
  });

  test('a listed file outside managed artwork is never deleted', () async {
    final precious = await fileAt(outside, 'artwork_restoresessionAn0.jpg');

    final cleanup = await recover(journal(created: [precious.path]));

    expect(await precious.readAsBytes(), [1, 2, 3]);
    expect(cleanup!.deletedFiles, isEmpty);
    expect(cleanup.rejectedEntries, contains(precious.path));
  });

  test(
    'a traversal path that escapes artwork storage is never deleted',
    () async {
      final precious = await fileAt(outside, 'artwork_restoresessionAn0.jpg');
      final traversal = path.join(
        artworkDir.path,
        '..',
        '..',
        '..',
        'user-files',
        'artwork_restoresessionAn0.jpg',
      );
      expect(File(traversal).existsSync(), isTrue);

      final cleanup = await recover(journal(created: [traversal]));

      expect(await precious.exists(), isTrue);
      expect(cleanup!.rejectedEntries, contains(traversal));
    },
  );

  test('a relative path is never deleted', () async {
    final cleanup = await recover(
      journal(created: ['artwork_restoresessionAn0.jpg']),
    );

    expect(cleanup!.deletedFiles, isEmpty);
    expect(cleanup.rejectedEntries, ['artwork_restoresessionAn0.jpg']);
  });

  test('unrelated artwork in managed storage is never deleted', () async {
    // Unreferenced, but not created by this session.
    final userArtwork = await fileAt(artworkDir, 'artwork_0f3c9a.jpg');
    final otherSession = await fileAt(
      artworkDir,
      'artwork_restoresessionBn0.jpg',
    );

    final cleanup = await recover(
      journal(created: [userArtwork.path, otherSession.path]),
    );

    expect(await userArtwork.exists(), isTrue);
    expect(await otherSession.exists(), isTrue);
    expect(
      cleanup!.rejectedEntries,
      containsAll([userArtwork.path, otherSession.path]),
    );
  });

  test('broad or foreign reserved tokens match nothing', () async {
    final userArtwork = await fileAt(artworkDir, 'artwork_0f3c9a.jpg');
    final other = await fileAt(artworkDir, 'artwork_restoresessionBn0.jpg');

    final cleanup = await recover(
      journal(tokens: const ['', 'artwork', 'restore', 'restoresessionBn0']),
    );

    expect(await userArtwork.exists(), isTrue);
    expect(await other.exists(), isTrue);
    expect(cleanup!.deletedFiles, isEmpty);
    expect(cleanup.rejectedEntries, hasLength(4));
  });

  test('an invalid session identifier disables every deletion', () async {
    final extraction = Directory(
      path.join(recoveryDir.path, '.sonus_restore_'),
    );
    await extraction.create();
    final file = await fileAt(artworkDir, 'artwork_restoren0.jpg');

    for (final sessionId in ['', '../x', 'a/b', 'session A']) {
      await recover(
        journal(
          sessionId: sessionId,
          extraction: extraction.path,
          tokens: ['restore${sessionId}n0'],
          created: [file.path],
        ),
      );
    }

    expect(await extraction.exists(), isTrue);
    expect(await file.exists(), isTrue);
  });

  test('an extraction folder outside the recovery directory is kept', () async {
    final foreign = Directory(
      path.join(outside.path, '.sonus_restore_sessionA'),
    );
    await fileAt(foreign, 'keep.txt');

    final cleanup = await recover(journal(extraction: foreign.path));

    expect(await File(path.join(foreign.path, 'keep.txt')).exists(), isTrue);
    expect(cleanup!.rejectedEntries, contains(foreign.path));
  });

  test("another session's extraction folder is kept", () async {
    final other = Directory(
      path.join(recoveryDir.path, '.sonus_restore_sessionB'),
    );
    await fileAt(other, 'keep.txt');

    final cleanup = await recover(journal(extraction: other.path));

    expect(await other.exists(), isTrue);
    expect(cleanup!.rejectedEntries, contains(other.path));
  });

  test('an extraction path with traversal is kept', () async {
    final foreign = Directory(
      path.join(outside.path, '.sonus_restore_sessionA'),
    );
    await fileAt(foreign, 'keep.txt');
    final traversal = path.join(
      recoveryDir.path,
      '..',
      '..',
      '..',
      'user-files',
      '.sonus_restore_sessionA',
    );

    await recover(journal(extraction: traversal));

    expect(await File(path.join(foreign.path, 'keep.txt')).exists(), isTrue);
  });

  group('links are never followed', () {
    Future<bool> tryLink(String linkPath, String target) async {
      try {
        await Link(linkPath).create(target);
        return true;
      } on FileSystemException {
        // Windows without developer mode cannot create symbolic links.
        return false;
      }
    }

    test('a linked artwork file is neither deleted nor followed', () async {
      final precious = await fileAt(outside, 'precious.jpg');
      final linkPath = path.join(
        artworkDir.path,
        'artwork_restoresessionAn0.jpg',
      );

      if (!await tryLink(linkPath, precious.path)) {
        markTestSkipped('Symbolic links are unavailable on this host.');
        return;
      }

      final cleanup = await recover(journal(created: [linkPath]));

      expect(await precious.readAsBytes(), [1, 2, 3]);
      expect(Link(linkPath).existsSync(), isTrue);
      expect(cleanup!.deletedFiles, isEmpty);
    });

    test('a file reached through a linked folder is not deleted', () async {
      final elsewhere = Directory(path.join(outside.path, 'elsewhere'));
      final precious = await fileAt(elsewhere, 'artwork_restoresessionAn0.jpg');
      final linkedFolder = path.join(artworkDir.path, 'linked');

      if (!await tryLink(linkedFolder, elsewhere.path)) {
        markTestSkipped('Symbolic links are unavailable on this host.');
        return;
      }

      final throughLink = path.join(
        linkedFolder,
        'artwork_restoresessionAn0.jpg',
      );
      await recover(journal(created: [throughLink]));

      expect(await precious.exists(), isTrue);
    });

    test(
      'a linked alias back into artwork cannot delete referenced artwork',
      () async {
        final installed = await fileAt(
          artworkDir,
          'artwork_restoresessionAn0.jpg',
        );

        await seedConnectedLibrary(
          await database.database,
          key: 'a',
          artworkPath: installed.path,
        );

        final alias = path.join(root.path, 'artwork-alias');

        if (!await tryLink(alias, artworkDir.path)) {
          markTestSkipped('Symbolic links are unavailable on this host.');
          return;
        }

        final throughAlias = path.join(alias, path.basename(installed.path));

        final cleanup = await recover(journal(created: [throughAlias]));

        expect(await installed.exists(), isTrue);
        expect(await installed.readAsBytes(), [1, 2, 3]);
        expect(cleanup!.rejectedEntries, contains(throughAlias));
        expect(cleanup.keptReferencedFiles, contains(installed.path));
      },
    );
    test('a linked extraction folder is not deleted through', () async {
      final target = Directory(path.join(outside.path, 'target'));
      await fileAt(target, 'keep.txt');
      final linkPath = path.join(recoveryDir.path, '.sonus_restore_sessionA');

      if (!await tryLink(linkPath, target.path)) {
        markTestSkipped('Symbolic links are unavailable on this host.');
        return;
      }

      await recover(journal(extraction: linkPath));

      expect(await File(path.join(target.path, 'keep.txt')).exists(), isTrue);
    });
  });
}
