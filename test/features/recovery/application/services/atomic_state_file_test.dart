import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/features/recovery/application/models/recovery_sync_hold.dart';
import 'package:sonus_next/features/recovery/application/services/atomic_state_file.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_hold_store.dart';
import 'package:sonus_next/features/recovery/application/services/restore_journal_store.dart';

/// Baseline finding (Windows, full suite): replacing restore_journal.json
/// failed with "Access is denied" (errno 5) while another process held the
/// file. Windows refuses to replace or delete a file another handle holds
/// without delete sharing; Dart cannot open such a handle itself, so the
/// contention is injected at the rename and delete seams.
FileSystemException _windowsError(int code) => FileSystemException(
  'Cannot rename file',
  'x',
  OSError(code == 5 ? 'Access is denied.' : 'Sharing violation.', code),
);

void main() {
  late Directory root;
  late File target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_state_file_');
    target = File(path.join(root.path, 'state.json'));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<List<String>> names() async => [
    for (final entity in await root.list().toList()) path.basename(entity.path),
  ]..sort();

  /// Renames for real after failing the first [failures] attempts.
  StateFileRename flakyRename(int failures, int code, List<String> sources) {
    var calls = 0;
    return (source, destination) async {
      sources.add(source.path);
      if (calls++ < failures) throw _windowsError(code);
      await source.rename(destination);
    };
  }

  AtomicStateFile subject({
    required StateFileRename rename,
    bool windows = true,
    StateFileDelete? delete,
  }) => AtomicStateFile(
    retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
    isWindows: () => windows,
    rename: rename,
    delete: delete,
  );

  test('writes complete content and leaves no temporary', () async {
    await const AtomicStateFile().writeString(target, '{"a":1}');
    await const AtomicStateFile().writeString(target, '{"a":2}');

    expect(await target.readAsString(), '{"a":2}');
    expect(await names(), ['state.json']);
  });

  for (final code in AtomicStateFile.windowsTransientErrors) {
    test('a transient Windows error $code is retried to success', () async {
      await target.writeAsString('old');
      final sources = <String>[];

      await subject(rename: flakyRename(2, code, sources)).writeString(
        target,
        'new',
      );

      expect(await target.readAsString(), 'new');
      expect(sources, hasLength(3));
      // Every attempt renames the same complete temporary.
      expect(sources.toSet(), hasLength(1));
      expect(await names(), ['state.json']);
    });
  }

  test('persistent contention fails after bounded attempts, old content intact', () async {
    await target.writeAsString('old');
    final sources = <String>[];

    await expectLater(
      subject(rename: flakyRename(1000, 5, sources)).writeString(target, 'new'),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.osError?.errorCode,
          'errno',
          5,
        ),
      ),
    );

    expect(sources, hasLength(4)); // 1 attempt + 3 bounded retries
    expect(await target.readAsString(), 'old');
    expect(await names(), ['state.json'], reason: 'temporary removed');
  });

  test('other errors are never retried', () async {
    await target.writeAsString('old');
    final sources = <String>[];

    await expectLater(
      subject(rename: flakyRename(1000, 2, sources)).writeString(target, 'new'),
      throwsA(isA<FileSystemException>()),
    );

    expect(sources, hasLength(1));
    expect(await target.readAsString(), 'old');
    expect(await names(), ['state.json']);
  });

  test('outside Windows, access denied is a real failure and not retried', () async {
    final sources = <String>[];

    await expectLater(
      subject(
        rename: flakyRename(1, 5, sources),
        windows: false,
      ).writeString(target, 'new'),
      throwsA(isA<FileSystemException>()),
    );

    expect(sources, hasLength(1));
  });

  test('each write uses its own temporary; a stale fixed .tmp cannot block it', () async {
    // Earlier versions always used "<file>.tmp". Something occupying that
    // name (here a directory, so it cannot be overwritten) no longer
    // affects writes.
    await Directory('${target.path}.tmp').create();
    final sources = <String>[];
    final writer = subject(rename: flakyRename(0, 5, sources));

    await writer.writeString(target, 'one');
    await writer.writeString(target, 'two');

    expect(await target.readAsString(), 'two');
    expect(sources.toSet(), hasLength(2));
    for (final source in sources) {
      expect(
        AtomicStateFile.isTemporaryName('state.json', path.basename(source)),
        isTrue,
      );
    }
  });

  test('delete retries transient contention and sweeps stale temporaries', () async {
    await target.writeAsString('x');
    final stale = File('${target.path}.0123456789abcdef.tmp');
    await stale.writeAsString('partial');
    await stale.setLastModified(DateTime.now().subtract(const Duration(hours: 2)));
    final recent = File('${target.path}.fedcba9876543210.tmp');
    await recent.writeAsString('in flight');
    final unrelated = File(path.join(root.path, 'other.json.tmp'));
    await unrelated.writeAsString('keep');

    var attempts = 0;
    await subject(
      rename: flakyRename(0, 5, []),
      delete: (file) async {
        if (attempts++ < 2) throw _windowsError(32);
        await file.delete();
      },
    ).delete(target);

    expect(attempts, 3);
    expect(await target.exists(), isFalse);
    expect(await stale.exists(), isFalse);
    expect(await recent.exists(), isTrue, reason: 'may belong to a writer');
    expect(await unrelated.exists(), isTrue);
  });

  group('stores use the contention-tolerant replacement', () {
    test('the restore journal survives transient contention', () async {
      final store = RestoreJournalStore(
        directory: () async => root,
        stateFile: subject(rename: flakyRename(2, 5, [])),
      );

      final journal = RestoreJournal(
        sessionId: 'session0',
        extractionDirectory: path.join(root.path, '.sonus_restore_session0'),
        reservedTokens: const ['restoresession0n0'],
        createdFiles: const [],
      );

      await store.write(journal);
      await store.write(journal.reserve('restoresession0n1'));

      expect((await store.read())!.reservedTokens, hasLength(2));
      await store.clear();
      expect(await store.read(), isNull);
      expect(await names(), isEmpty);
    });

    test('a failed journal write keeps the previous complete journal', () async {
      final good = RestoreJournalStore(directory: () async => root);
      final journal = RestoreJournal(
        sessionId: 'session0',
        extractionDirectory: path.join(root.path, '.sonus_restore_session0'),
        reservedTokens: const ['restoresession0n0'],
        createdFiles: const [],
      );
      await good.write(journal);

      final contended = RestoreJournalStore(
        directory: () async => root,
        stateFile: subject(rename: flakyRename(1000, 5, [])),
      );

      await expectLater(
        contended.write(journal.reserve('restoresession0n1')),
        throwsA(isA<FileSystemException>()),
      );

      expect((await good.read())!.reservedTokens, ['restoresession0n0']);
      expect(await names(), [RestoreJournalStore.fileName]);
    });

    test('the sync hold survives transient contention', () async {
      final store = RecoverySyncHoldStore(
        directory: () async => root,
        stateFile: subject(rename: flakyRename(2, 32, [])),
      );

      await store.write(
        RecoverySyncHold(
          holdId: 'h',
          backupId: 'b',
          createdAtUtc: DateTime.utc(2026, 10, 21),
          phase: RecoverySyncHoldPhase.restoring,
          backupAccountIds: const {},
          preRestore: null,
        ),
      );

      expect(await store.read(), isA<ActiveRecoverySyncHold>());
    });
  });
}
