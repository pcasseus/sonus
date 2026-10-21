import 'dart:convert';

import '../models/backup_data_payload.dart';
import '../models/backup_manifest.dart';

class DecodedBackup {
  const DecodedBackup({required this.manifest, required this.payload});

  final BackupManifest manifest;
  final BackupDataPayload payload;
}

class BackupJsonCodec {
  const BackupJsonCodec();

  String encode({
    required BackupManifest manifest,
    required BackupDataPayload payload,
  }) {
    manifest.validate();
    payload.validateAgainst(manifest);

    final orderedTables = payload.tables.keys.toList()..sort();

    return jsonEncode({
      'manifest': manifest.toJson(),
      'payload': {
        for (final table in orderedTables)
          table: [
            for (final row in payload.tables[table]!)
              {for (final key in (row.keys.toList()..sort())) key: row[key]},
          ],
      },
    });
  }

  DecodedBackup decode(String source) {
    final Object? decoded;

    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Invalid backup JSON.');
    }

    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        !decoded.containsKey('manifest') ||
        !decoded.containsKey('payload')) {
      throw const FormatException('Invalid backup document structure.');
    }

    final rawManifest = decoded['manifest'];
    final rawPayload = decoded['payload'];

    if (rawManifest is! Map<String, dynamic> ||
        rawPayload is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup document sections.');
    }

    final manifest = BackupManifest.fromJson(rawManifest);
    final tables = <String, List<Map<String, Object?>>>{};

    for (final entry in rawPayload.entries) {
      final value = entry.value;

      if (value is! List) {
        throw FormatException('Invalid row collection for ${entry.key}.');
      }

      final rows = <Map<String, Object?>>[];

      for (final item in value) {
        if (item is! Map<String, dynamic>) {
          throw FormatException('Invalid row structure for ${entry.key}.');
        }

        rows.add(Map<String, Object?>.from(item));
      }

      tables[entry.key] = rows;
    }

    final payload = BackupDataPayload(tables: tables);
    payload.validateAgainst(manifest);

    return DecodedBackup(manifest: manifest, payload: payload);
  }
}
