import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/recovery_sync_hold.dart';
import 'atomic_state_file.dart';

typedef RecoveryDirectoryProvider = Future<Directory> Function();

/// Persists the recovery sync hold as a small JSON file.
///
/// Writes go through [AtomicStateFile]: a flushed temporary unique to the
/// write is renamed over the hold file, so a crash leaves either the old or
/// the new hold, never a partial one. An unreadable file is reported as a
/// hold, never as absent.
class RecoverySyncHoldStore {
  const RecoverySyncHoldStore({
    required this.directory,
    this.stateFile = const AtomicStateFile(),
  });

  static const fileName = 'sync_hold.json';

  final RecoveryDirectoryProvider directory;
  final AtomicStateFile stateFile;

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
    await stateFile.writeString(await _file(), jsonEncode(hold.toJson()));
  }

  /// Restores exactly the given prior state.
  Future<void> restore(RecoverySyncHoldState state) async {
    switch (state) {
      case NoRecoverySyncHold():
        await clear();
      case ActiveRecoverySyncHold(:final hold):
        await write(hold);
      case UnreadableRecoverySyncHold(:final rawContent):
        await stateFile.writeString(await _file(), rawContent ?? '');
    }
  }

  Future<void> clear() async {
    await stateFile.delete(await _file());
  }
}
