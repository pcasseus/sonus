import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

enum BackupExportOutcome {
  /// Saved and read back with an identical SHA-256 and length.
  verified,

  /// Saved, but the storage provider does not allow reading it back.
  writtenUnverified,

  /// The user closed the save dialog; nothing was saved.
  cancelled,

  /// Saving or verification failed; the incomplete document was removed.
  failed,
}

class BackupExportResult {
  const BackupExportResult({
    required this.outcome,
    this.documentUri,
    this.documentRemoved = false,
    this.message,
  });

  final BackupExportOutcome outcome;
  final String? documentUri;

  /// Whether a document created by this export was deleted again.
  final bool documentRemoved;

  final String? message;

  bool get isVerified => outcome == BackupExportOutcome.verified;
}

/// Platform access to user-chosen documents (Android Storage Access
/// Framework through `BackupDocumentChannel.kt`).
abstract interface class BackupDocumentPlatform {
  /// Opens the system save dialog. Returns null when the user cancels.
  Future<String?> createDocument(String suggestedName);

  /// Streams [source] into the document and returns the bytes written.
  Future<int> writeDocument({required File source, required String uri});

  /// Reads the document back. Returns null when the provider refuses reads.
  Future<({String sha256, int length})?> readBackDocument(String uri);

  Future<bool> deleteDocument(String uri);
}

class MethodChannelBackupDocumentPlatform implements BackupDocumentPlatform {
  const MethodChannelBackupDocumentPlatform({
    this.channel = const MethodChannel(channelName),
  });

  static const channelName = 'com.sonus.sonus_next/backup_export';

  final MethodChannel channel;

  @override
  Future<String?> createDocument(String suggestedName) =>
      channel.invokeMethod<String>('createDocument', {
        'suggestedName': suggestedName,
      });

  @override
  Future<int> writeDocument({required File source, required String uri}) async {
    final written = await channel.invokeMethod<int>('writeDocument', {
      'source': source.path,
      'uri': uri,
    });

    if (written == null) {
      throw PlatformException(code: 'WRITE_FAILED');
    }

    return written;
  }

  @override
  Future<({String sha256, int length})?> readBackDocument(String uri) async {
    try {
      final result = await channel.invokeMapMethod<String, Object?>(
        'readBackDocument',
        {'uri': uri},
      );

      final digest = result?['sha256'];
      final length = result?['length'];

      if (digest is! String || length is! int) {
        throw PlatformException(code: 'READ_BACK_FAILED');
      }

      return (sha256: digest, length: length);
    } on PlatformException catch (error) {
      if (error.code == 'READ_BACK_UNAVAILABLE') return null;
      rethrow;
    }
  }

  @override
  Future<bool> deleteDocument(String uri) async =>
      await channel.invokeMethod<bool>('deleteDocument', {'uri': uri}) ??
      false;
}

/// Saves a backup outside the app and proves the saved bytes are intact.
///
/// Success is reported only when the document reads back with the same
/// SHA-256 and length as the verified source. A cancelled dialog is never
/// reported as saved, and a document that fails verification is deleted.
class BackupDocumentExporter {
  const BackupDocumentExporter({
    this.platform = const MethodChannelBackupDocumentPlatform(),
  });

  final BackupDocumentPlatform platform;

  Future<BackupExportResult> export({
    required File source,
    required String suggestedName,
  }) async {
    final String? uri;

    try {
      uri = await platform.createDocument(suggestedName);
    } on PlatformException catch (error) {
      return BackupExportResult(
        outcome: BackupExportOutcome.failed,
        message: error.message ?? 'The save dialog could not be opened.',
      );
    } on MissingPluginException {
      return const BackupExportResult(
        outcome: BackupExportOutcome.failed,
        message: 'Saving to a device location is unavailable.',
      );
    }

    if (uri == null) {
      return const BackupExportResult(outcome: BackupExportOutcome.cancelled);
    }

    final expectedLength = await source.length();
    final expectedDigest = (await sha256.bind(source.openRead()).first)
        .toString();

    try {
      final written = await platform.writeDocument(source: source, uri: uri);

      if (written != expectedLength) {
        return await _fail(uri, 'The saved backup is incomplete.');
      }
    } catch (_) {
      return _fail(uri, 'The backup could not be saved there.');
    }

    final ({String sha256, int length})? readBack;

    try {
      readBack = await platform.readBackDocument(uri);
    } catch (_) {
      return _fail(uri, 'The saved backup could not be read back.');
    }

    if (readBack == null) {
      return BackupExportResult(
        outcome: BackupExportOutcome.writtenUnverified,
        documentUri: uri,
        message:
            'Saved, but this storage location does not let Sonus read the '
            'file back to confirm it.',
      );
    }

    if (readBack.length != expectedLength ||
        readBack.sha256 != expectedDigest) {
      return _fail(uri, 'The saved backup does not match the original.');
    }

    return BackupExportResult(
      outcome: BackupExportOutcome.verified,
      documentUri: uri,
    );
  }

  Future<BackupExportResult> _fail(String uri, String message) async {
    var removed = false;

    try {
      removed = await platform.deleteDocument(uri);
    } catch (_) {
      removed = false;
    }

    return BackupExportResult(
      outcome: BackupExportOutcome.failed,
      documentUri: removed ? null : uri,
      documentRemoved: removed,
      message: message,
    );
  }
}
