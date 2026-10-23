import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/features/recovery/application/services/backup_document_exporter.dart';

/// A document provider backed by a folder, with failure switches.
class _FolderDocuments implements BackupDocumentPlatform {
  _FolderDocuments(this.root);

  final Directory root;
  bool cancel = false;
  bool refuseReads = false;
  bool failWrite = false;
  bool failRead = false;
  List<int>? corruptWith;
  int? reportWritten;
  final deleted = <String>[];

  File _file(String uri) =>
      File(path.join(root.path, Uri.parse(uri).path.split('/').last));

  @override
  Future<String?> createDocument(String suggestedName) async {
    if (cancel) return null;
    await File(path.join(root.path, suggestedName)).create(exclusive: true);
    return 'content://docs/$suggestedName';
  }

  @override
  Future<int> writeDocument({required File source, required String uri}) async {
    if (failWrite) throw PlatformException(code: 'WRITE_FAILED');
    final bytes = corruptWith ?? await source.readAsBytes();
    await _file(uri).writeAsBytes(bytes, flush: true);
    return reportWritten ?? await source.length();
  }

  @override
  Future<({String sha256, int length})?> readBackDocument(String uri) async {
    if (refuseReads) return null;
    if (failRead) throw PlatformException(code: 'READ_BACK_FAILED');
    final bytes = await _file(uri).readAsBytes();
    return (sha256: sha256.convert(bytes).toString(), length: bytes.length);
  }

  @override
  Future<bool> deleteDocument(String uri) async {
    deleted.add(uri);
    await _file(uri).delete();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory documents;
  late File source;
  late _FolderDocuments platform;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_export_');
    documents = Directory(path.join(root.path, 'documents'));
    await documents.create();
    source = File(path.join(root.path, 'backup.sonusbackup'));
    await source.writeAsBytes(List.generate(4096, (i) => i % 251));
    platform = _FolderDocuments(documents);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<BackupExportResult> export() => BackupDocumentExporter(
    platform: platform,
  ).export(source: source, suggestedName: 'sonus.sonusbackup');

  test('an unreadable source never creates a destination document', () async {
    await source.delete();

    final result = await export();

    expect(result.outcome, BackupExportOutcome.failed);
    expect(result.isVerified, isFalse);
    expect(result.message, contains('could not be read'));
    expect(await documents.list().isEmpty, isTrue);
    expect(platform.deleted, isEmpty);
  });
  test('verified only when read-back SHA-256 and length match', () async {
    final result = await export();

    expect(result.outcome, BackupExportOutcome.verified);
    expect(result.isVerified, isTrue);
    expect(
      await File(path.join(documents.path, 'sonus.sonusbackup')).readAsBytes(),
      await source.readAsBytes(),
    );
    expect(platform.deleted, isEmpty);
  });

  test('cancelling the dialog saves nothing and is not success', () async {
    platform.cancel = true;

    final result = await export();

    expect(result.outcome, BackupExportOutcome.cancelled);
    expect(result.isVerified, isFalse);
    expect(await documents.list().isEmpty, isTrue);
  });

  test('corrupted saved bytes are detected and the document removed', () async {
    platform.corruptWith = List.filled(4096, 0);

    final result = await export();

    expect(result.outcome, BackupExportOutcome.failed);
    expect(result.documentRemoved, isTrue);
    expect(await documents.list().isEmpty, isTrue);
  });

  test('a short write is a failure', () async {
    platform.reportWritten = 10;

    final result = await export();

    expect(result.outcome, BackupExportOutcome.failed);
    expect(result.documentRemoved, isTrue);
  });

  test('a provider write error removes the created document', () async {
    platform.failWrite = true;

    final result = await export();

    expect(result.outcome, BackupExportOutcome.failed);
    expect(platform.deleted, hasLength(1));
  });

  test('a read-back error is a failure, never a success', () async {
    platform.failRead = true;

    final result = await export();

    expect(result.outcome, BackupExportOutcome.failed);
    expect(result.documentRemoved, isTrue);
  });

  test('providers that refuse reads are reported as unverified', () async {
    platform.refuseReads = true;

    final result = await export();

    expect(result.outcome, BackupExportOutcome.writtenUnverified);
    expect(result.isVerified, isFalse);
    expect(result.documentUri, isNotNull);
    expect(platform.deleted, isEmpty);
  });

  group('method channel platform', () {
    const channel = MethodChannel(
      MethodChannelBackupDocumentPlatform.channelName,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('maps READ_BACK_UNAVAILABLE to an unverifiable document', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'READ_BACK_UNAVAILABLE');
      });

      expect(
        await const MethodChannelBackupDocumentPlatform().readBackDocument(
          'content://x',
        ),
        isNull,
      );
    });

    test('passes the read-back digest and length through', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'readBackDocument');
        return {'sha256': 'ab' * 32, 'length': 7};
      });

      final result = await const MethodChannelBackupDocumentPlatform()
          .readBackDocument('content://x');

      expect(result!.sha256, 'ab' * 32);
      expect(result.length, 7);
    });

    test('a missing native channel fails the export closed', () async {
      final result = await const BackupDocumentExporter().export(
        source: source,
        suggestedName: 'x.sonusbackup',
      );

      expect(result.outcome, BackupExportOutcome.failed);
    });
  });
}
