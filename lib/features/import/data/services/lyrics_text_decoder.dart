import 'dart:convert';
import 'dart:typed_data';

/// Decodes a lyrics file's bytes (App Update 1.3, REF-1.3-07).
///
/// Lyrics files come from many tools: UTF-8 with or without a byte order
/// mark, UTF-16 (common from Windows editors, always with a byte order
/// mark), or a legacy single-byte encoding. In order:
///
/// 1. a UTF-16 LE or BE byte order mark: UTF-16;
/// 2. valid UTF-8 (a UTF-8 byte order mark is dropped);
/// 3. otherwise Latin-1, so "Ü" stays "Ü" instead of becoming U+FFFD.
///
/// Never throws for any input.
abstract final class LyricsTextDecoder {
  static String decode(Uint8List bytes) {
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return _utf16(bytes, 2, littleEndian: true);
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return _utf16(bytes, 2, littleEndian: false);
      }
    }
    final start =
        bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? 3
        : 0;
    final body = Uint8List.sublistView(bytes, start);
    try {
      return utf8.decode(body);
    } on FormatException {
      return latin1.decode(body);
    }
  }

  static String _utf16(
    Uint8List bytes,
    int start, {
    required bool littleEndian,
  }) {
    final data = ByteData.sublistView(bytes, start);
    final units = <int>[
      for (var i = 0; i + 1 < data.lengthInBytes; i += 2)
        data.getUint16(i, littleEndian ? Endian.little : Endian.big),
    ];
    // String.fromCharCodes keeps surrogate pairs and never throws.
    return String.fromCharCodes(units);
  }
}
