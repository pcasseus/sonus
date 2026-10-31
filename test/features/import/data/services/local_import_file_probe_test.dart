// SN-50 §4: a read-only check tells a missing file from one Sonus may no
// longer read. Fakes only; the real SAF behaviour is a device check (M-6).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/saf.dart';

import 'package:sonus_next/features/import/data/services/local_import_file_probe.dart';
import 'package:sonus_next/features/import/data/services/media_metadata_reader.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_file_failure.dart';
import 'package:sonus_next/features/import/domain/services/import_file_probe.dart';

const _tree =
    'content://com.android.externalstorage.documents/tree/primary%3AMusic';
const _file = '$_tree/document/primary%3AMusic%2Fsong.mp3';

/// Answers SAF calls from fixed values and records every call, so a test
/// can prove nothing but reads happened.
class _FakeSaf extends Saf {
  _FakeSaf({this.found = true, this.permissions = const [], this.failure});

  final bool found;
  final List<SafPersistedPermission> permissions;
  final Exception? failure;
  final calls = <String>[];

  @override
  Future<bool> exists(String uri) async {
    calls.add('exists');
    if (failure case final failure?) throw failure;
    return found;
  }

  @override
  Future<List<SafPersistedPermission>> persistedPermissions() async {
    calls.add('persistedPermissions');
    return permissions;
  }

  @override
  Future<void> copyToLocalFile(
    String srcUri,
    String destPath, {
    SafProgressCallback? onProgress,
  }) async {
    calls.add('copyToLocalFile');
    if (failure case final failure?) throw failure;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected SAF call ${invocation.memberName}');
}

SafPersistedPermission _grant({bool read = true}) => SafPersistedPermission(
  uri: _tree,
  read: read,
  write: false,
  persistedTime: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalImportFileProbe', () {
    Future<ImportFileState> probe(_FakeSaf? saf, [String path = _file]) =>
        LocalImportFileProbe(saf: saf).probe(path);

    test('a document that exists is present', () async {
      final saf = _FakeSaf();

      expect(await probe(saf), ImportFileState.present);
      expect(saf.calls, ['exists']);
    });

    test(
      'a document gone from a folder Sonus can still read is missing',
      () async {
        final saf = _FakeSaf(found: false, permissions: [_grant()]);

        expect(await probe(saf), ImportFileState.missing);
      },
    );

    test('a document under no read grant is a lost permission, not '
        'missing', () async {
      expect(
        await probe(_FakeSaf(found: false)),
        ImportFileState.permissionLost,
      );
      expect(
        await probe(_FakeSaf(found: false, permissions: [_grant(read: false)])),
        ImportFileState.permissionLost,
      );
    });

    test('typed SAF failures map to their state', () async {
      expect(
        await probe(
          _FakeSaf(failure: const SafPermissionException(_file, 'no')),
        ),
        ImportFileState.permissionLost,
      );
      expect(
        await probe(_FakeSaf(failure: const SafNotFoundException(_file, 'no'))),
        ImportFileState.missing,
      );
      expect(
        await probe(_FakeSaf(failure: const SafIoException(_file, 'io'))),
        ImportFileState.unknown,
      );
    });

    test('a content URI without SAF is unknown', () async {
      expect(await probe(null), ImportFileState.unknown);
    });

    test('a plain path is checked for existence only', () async {
      final directory = await Directory.systemTemp.createTemp('sonus_probe_');
      addTearDown(() => directory.delete(recursive: true));
      final present = File('${directory.path}/song.mp3');
      await present.writeAsBytes(const [0]);

      expect(await probe(null, present.path), ImportFileState.present);
      expect(
        await probe(null, '${directory.path}/gone.mp3'),
        ImportFileState.missing,
      );
      expect(await present.readAsBytes(), const [0]);
    });
  });

  group('MediaMetadataReader typed failures', () {
    late Directory temporary;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('sonus_reader_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => temporary.path,
          );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await temporary.delete(recursive: true);
    });

    ImportCandidate candidate(String path) => ImportCandidate(
      filePath: path,
      normalizedPath: path.toLowerCase(),
      discoveredAt: DateTime.utc(2026, 10, 30),
    );

    test('a content URI that is gone is ImportFileMissing', () async {
      final saf = _FakeSaf(failure: const SafNotFoundException(_file, 'gone'));

      await expectLater(
        MediaMetadataReader(saf: saf).read(candidate(_file)),
        throwsA(isA<ImportFileMissing>()),
      );
      expect(saf.calls, ['copyToLocalFile']);
    });

    test('a revoked folder is ImportFileAccessDenied', () async {
      final saf = _FakeSaf(
        failure: const SafPermissionException(_file, 'revoked'),
      );

      await expectLater(
        MediaMetadataReader(saf: saf).read(candidate(_file)),
        throwsA(isA<ImportFileAccessDenied>()),
      );
    });

    test('the temporary copy is cleaned up after a failure', () async {
      final saf = _FakeSaf(failure: const SafNotFoundException(_file, 'gone'));

      await expectLater(
        MediaMetadataReader(saf: saf).read(candidate(_file)),
        throwsA(isA<ImportFileMissing>()),
      );
      final cache = Directory('${temporary.path}/sonus_import_metadata');
      expect(cache.listSync(), isEmpty);
    });

    test('a plain path that does not exist is ImportFileMissing', () async {
      await expectLater(
        const MediaMetadataReader().read(
          candidate('${temporary.path}/gone.mp3'),
        ),
        throwsA(isA<ImportFileMissing>()),
      );
    });
  });
}
