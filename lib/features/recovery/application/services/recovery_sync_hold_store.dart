import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/recovery_sync_hold.dart';

typedef RecoveryDirectoryProvider = Future<Directory> Function();

/// Persists the recovery sync hold as a small JSON file.
///
/// Writes go to a temporary file that is flushed and then renamed over the
/// hold file, so a crash leaves either the old or the new hold, never a
/// partial one. An unreadable file is reported as a hold, never as absent.
class RecoverySyncHoldStore {
  const RecoverySyncHoldStore({required this.directory});

  static const fileName = 'sync_hold.json';

  final RecoveryDirectoryProvider directory;

  Future<File> _file() async =>
      File(path.join((await directory()).path, fileName));

  Future<RecoverySyncHoldState> read() async {
    final file = await _file();

    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return const NoRecoverySyncHold();
    }

    String? raw;

    try {
      raw = await file.readAsString();
      return ActiveRecoverySyncHold(RecoverySyncHold.fromJson(jsonDecode(raw)));
    } on FormatException {
      return UnreadableRecoverySyncHold(raw);
    } on FileSystemException {
      return UnreadableRecoverySyncHold(raw);
    }
  }

  Future<void> write(RecoverySyncHold hold) async {
    final file = await _file();
    await file.parent.create(recursive: true);

    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(hold.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  /// Restores exactly the given prior state.
  Future<void> restore(RecoverySyncHoldState state) async {
    switch (state) {
      case NoRecoverySyncHold():
        await clear();
      case ActiveRecoverySyncHold(:final hold):
        await write(hold);
      case UnreadableRecoverySyncHold(:final rawContent):
        final file = await _file();
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(rawContent ?? '', flush: true);
        await temporary.rename(file.path);
    }
  }

  Future<void> clear() async {
    final file = await _file();

    if (await file.exists()) {
      await file.delete();
    }
  }
}
