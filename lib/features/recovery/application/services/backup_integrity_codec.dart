import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/backup_data_payload.dart';
import '../models/backup_manifest.dart';
import 'backup_json_codec.dart';

class BackupIntegrityCodec {
  const BackupIntegrityCodec({this.jsonCodec = const BackupJsonCodec()});

  final BackupJsonCodec jsonCodec;

  String encode({
    required BackupManifest manifest,
    required BackupDataPayload payload,
  }) {
    final document = jsonCodec.encode(manifest: manifest, payload: payload);

    final digest = sha256.convert(utf8.encode(document)).toString();

    return jsonEncode({
      'integrityVersion': 1,
      'algorithm': 'sha256',
      'digest': digest,
      'document': document,
    });
  }

  DecodedBackup decode(String source) {
    final Object? decoded;

    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Invalid backup integrity envelope.');
    }

    if (decoded is! Map<String, dynamic> ||
        decoded.length != 4 ||
        decoded['integrityVersion'] != 1 ||
        decoded['algorithm'] != 'sha256' ||
        decoded['digest'] is! String ||
        decoded['document'] is! String) {
      throw const FormatException('Invalid backup integrity envelope.');
    }

    final expected = decoded['digest'] as String;
    final document = decoded['document'] as String;

    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      throw const FormatException('Invalid backup SHA-256 digest.');
    }

    final actual = sha256.convert(utf8.encode(document)).toString();

    if (actual != expected) {
      throw const FormatException('Backup integrity verification failed.');
    }

    return jsonCodec.decode(document);
  }
}
