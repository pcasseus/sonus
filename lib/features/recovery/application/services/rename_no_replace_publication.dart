import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../models/backup_failure.dart';
import 'backup_publication.dart';

typedef _RenameAt2Native =
    Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<Uint8>, Uint32);
typedef _RenameAt2 = int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int);
typedef _MallocNative = Pointer<Uint8> Function(IntPtr);
typedef _Malloc = Pointer<Uint8> Function(int);
typedef _FreeNative = Void Function(Pointer<Uint8>);
typedef _Free = void Function(Pointer<Uint8>);
typedef _ErrnoNative = Pointer<Int32> Function();
typedef _Errno = Pointer<Int32> Function();

/// Publishes with the kernel's atomic `renameat2(RENAME_NOREPLACE)`.
///
/// The rename either moves the verified candidate to the final name in one
/// step or fails with `EEXIST`; an existing file is never replaced and a
/// partial file is never visible under the final name. Both paths must be
/// on the same filesystem (the publisher stages beside the destination).
///
/// Android's libc exposes `renameat2` from Android 11 (API 30). Where it
/// is missing this fails closed instead of falling back to a check-then-
/// rename. Hard links are not an option: Android 10+ SELinux denies
/// `link()` on app data files (EACCES, verified on an API 34 emulator).
class RenameNoReplacePublication implements BackupPublication {
  const RenameNoReplacePublication();

  static const _atFdCwd = -100;
  static const _renameNoReplace = 1;
  static const _eexist = 17;

  static _Bindings? _cached;

  static _Bindings? _bindings() {
    if (_cached != null) return _cached;

    final libc = DynamicLibrary.process();

    if (!libc.providesSymbol('renameat2') ||
        !libc.providesSymbol('__errno') ||
        !libc.providesSymbol('malloc') ||
        !libc.providesSymbol('free')) {
      return null;
    }

    return _cached = _Bindings(
      renameAt2: libc.lookupFunction<_RenameAt2Native, _RenameAt2>(
        'renameat2',
        isLeaf: true,
      ),
      errno: libc.lookupFunction<_ErrnoNative, _Errno>('__errno', isLeaf: true),
      malloc: libc.lookupFunction<_MallocNative, _Malloc>('malloc'),
      free: libc.lookupFunction<_FreeNative, _Free>('free'),
    );
  }

  /// Whether this device supports atomic no-replace publication.
  static bool get isSupported => Platform.isAndroid && _bindings() != null;

  @override
  Future<void> publishNoReplace({
    required File source,
    required File destination,
  }) async {
    final bindings = Platform.isAndroid ? _bindings() : null;

    if (bindings == null) {
      throw UnsupportedError(
        'Atomic no-replace publication requires Android 11 or later.',
      );
    }

    final from = bindings.cString(source.path);
    final to = bindings.cString(destination.path);

    try {
      final result = bindings.renameAt2(
        _atFdCwd,
        from,
        _atFdCwd,
        to,
        _renameNoReplace,
      );

      if (result == 0) return;

      final errno = bindings.errno().value;

      if (errno == _eexist) {
        throw BackupDestinationExistsError();
      }

      throw BackupException(
        BackupFailureCode.publicationFailed,
        'Atomic backup publication failed: $errno',
      );
    } finally {
      bindings.free(from);
      bindings.free(to);
    }
  }
}

class _Bindings {
  _Bindings({
    required this.renameAt2,
    required this.errno,
    required this.malloc,
    required this.free,
  });

  final _RenameAt2 renameAt2;
  final _Errno errno;
  final _Malloc malloc;
  final _Free free;

  Pointer<Uint8> cString(String value) {
    final bytes = utf8.encode(value);
    final pointer = malloc(bytes.length + 1);

    if (pointer == nullptr) {
      throw const OutOfMemoryError();
    }

    pointer.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;

    return pointer;
  }
}
