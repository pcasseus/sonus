import 'dart:convert';
import 'dart:typed_data';

import '../../domain/services/audio_byte_source.dart';

/// Lyrics found inside an MP3's leading ID3v2 tag (App Update 1.3,
/// REF-1.3-07): unsynchronised text (USLT, ID3v2.2 ULT) and synchronised
/// text (SYLT, ID3v2.2 SLT) with millisecond timestamps, as LRC.
class EmbeddedLyrics {
  const EmbeddedLyrics({this.plain, this.syncedLrc});

  /// The unsynchronised lyrics, trimmed; null when there are none.
  final String? plain;

  /// The synchronised lyrics as LRC lines ("[mm:ss.xx]text"); null when
  /// there are none or they are timed in MPEG frames.
  final String? syncedLrc;

  bool get isEmpty => plain == null && syncedLrc == null;
}

/// Reads [EmbeddedLyrics] from the leading ID3v2.2, 2.3 or 2.4 tag.
///
/// Read-only and bounded: the tag header, each frame header, and only the
/// bodies of lyrics frames (at most [maxFrameBytes] each). Artwork and
/// other frames are stepped over, never read. Compressed or encrypted
/// frames are skipped. Unsynchronisation (tag-wide in 2.2/2.3, per frame
/// in 2.4) is undone. Never throws for a malformed tag: it returns what
/// it could read, or null.
abstract final class Id3LyricsReader {
  static const int maxFrameBytes = 512 * 1024;

  static Future<EmbeddedLyrics?> read(AudioByteSource source) async {
    try {
      return await _read(source);
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<EmbeddedLyrics?> _read(AudioByteSource source) async {
    final length = await source.length();
    if (length < 10) return null;
    final header = await source.read(0, 10);
    if (header.length < 10 ||
        header[0] != 0x49 || // I
        header[1] != 0x44 || // D
        header[2] != 0x33) {
      // 3
      return null;
    }
    final major = header[3];
    if (major < 2 || major > 4) return null;
    final flags = header[5];
    final tagSize = _syncsafe(header, 6);
    final tagEnd = (10 + tagSize).clamp(0, length);
    final tagUnsync = major < 4 && (flags & 0x80) != 0;

    var offset = 10;
    if (major >= 3 && (flags & 0x40) != 0) {
      // An extended header: its size (2.4 counts itself, 2.3 does not).
      final ext = await source.read(offset, 4);
      if (ext.length < 4) return null;
      offset += major == 4 ? _syncsafe(ext, 0) : _int32(ext, 0) + 4;
    }

    final headerSize = major == 2 ? 6 : 10;
    String? plain;
    String? synced;
    while (offset + headerSize <= tagEnd) {
      final frame = await source.read(offset, headerSize);
      if (frame.length < headerSize || frame[0] == 0) break; // padding
      final id = ascii.decode(
        frame.sublist(0, major == 2 ? 3 : 4),
        allowInvalid: true,
      );
      final size = switch (major) {
        2 => (frame[3] << 16) | (frame[4] << 8) | frame[5],
        3 => _int32(frame, 4),
        _ => _syncsafe(frame, 4),
      };
      final bodyStart = offset + headerSize;
      offset = bodyStart + size;
      if (size <= 0 || offset > tagEnd) break;

      final isPlain = id == 'USLT' || id == 'ULT';
      final isSynced = id == 'SYLT' || id == 'SLT';
      if (!isPlain && !isSynced) continue;
      if (size > maxFrameBytes) continue;
      if ((isPlain && plain != null) || (isSynced && synced != null)) {
        continue;
      }

      var bodyFrom = bodyStart;
      var bodySize = size;
      var unsync = tagUnsync;
      if (major == 4) {
        final format = frame[9];
        // Compressed, encrypted: not read.
        if ((format & 0x08) != 0 || (format & 0x04) != 0) continue;
        unsync = (format & 0x02) != 0;
        if ((format & 0x01) != 0) {
          // A data length indicator precedes the body.
          bodyFrom += 4;
          bodySize -= 4;
        }
      } else if (major == 3 && (frame[9] & 0xC0) != 0) {
        continue;
      }
      if (bodySize <= 0) continue;

      var body = await source.read(bodyFrom, bodySize);
      if (unsync) body = _undoUnsync(body);
      if (isPlain) {
        plain = _plain(body);
      } else {
        synced = _synced(body);
      }
      if (plain != null && synced != null) break;
    }

    final result = EmbeddedLyrics(plain: plain, syncedLrc: synced);
    return result.isEmpty ? null : result;
  }

  /// USLT: encoding, language (3), descriptor, text.
  static String? _plain(Uint8List body) {
    if (body.length < 5) return null;
    final encoding = body[0];
    var at = 4;
    at = _skipTerminated(body, at, encoding);
    final text = _decode(body.sublist(at.clamp(0, body.length)), encoding);
    final cleaned = text
        .replaceAll('\u0000', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// SYLT: encoding, language (3), timestamp format, content type,
  /// descriptor, then (text, 32-bit time) pairs. Only millisecond times
  /// (format 2) can be shown; MPEG-frame times need the stream's frame
  /// rate, so they are not read.
  static String? _synced(Uint8List body) {
    if (body.length < 7) return null;
    final encoding = body[0];
    if (body[4] != 2) return null;
    var at = _skipTerminated(body, 6, encoding);
    final lines = <String>[];
    while (at < body.length) {
      final end = _terminator(body, at, encoding);
      final text = _decode(
        body.sublist(at, end),
        encoding,
      ).replaceAll('\r\n', ' ').replaceAll(RegExp(r'[\r\n]'), ' ').trim();
      at = end + _terminatorLength(encoding);
      if (at + 4 > body.length) break;
      final ms = _int32(body, at);
      at += 4;
      if (text.isEmpty) continue;
      lines.add('[${_lrcTime(ms)}]$text');
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  static String _lrcTime(int ms) {
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    final hundredths = (ms % 1000) ~/ 10;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(minutes)}:${two(seconds)}.${two(hundredths)}';
  }

  static int _skipTerminated(Uint8List body, int at, int encoding) =>
      _terminator(body, at, encoding) + _terminatorLength(encoding);

  static int _terminatorLength(int encoding) =>
      encoding == 1 || encoding == 2 ? 2 : 1;

  /// The index of the terminator at or after [from], or the end.
  static int _terminator(Uint8List body, int from, int encoding) {
    if (encoding == 1 || encoding == 2) {
      for (var i = from; i + 1 < body.length; i += 2) {
        if (body[i] == 0 && body[i + 1] == 0) return i;
      }
      return body.length;
    }
    for (var i = from; i < body.length; i++) {
      if (body[i] == 0) return i;
    }
    return body.length;
  }

  static String _decode(Uint8List bytes, int encoding) {
    switch (encoding) {
      case 0:
        return latin1.decode(bytes);
      case 3:
        return utf8.decode(bytes, allowMalformed: true);
      case 1:
      case 2:
        var littleEndian = false;
        var start = 0;
        if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
          littleEndian = true;
          start = 2;
        } else if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
          start = 2;
        } else if (encoding == 1) {
          // UTF-16 without a byte order mark: the common writers use LE.
          littleEndian = true;
        }
        final units = <int>[
          for (var i = start; i + 1 < bytes.length; i += 2)
            littleEndian
                ? bytes[i] | (bytes[i + 1] << 8)
                : (bytes[i] << 8) | bytes[i + 1],
        ];
        return String.fromCharCodes(units);
      default:
        throw const FormatException('unknown ID3 text encoding');
    }
  }

  static Uint8List _undoUnsync(Uint8List bytes) {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < bytes.length; i++) {
      out.addByte(bytes[i]);
      if (bytes[i] == 0xFF && i + 1 < bytes.length && bytes[i + 1] == 0x00) {
        i++;
      }
    }
    return out.toBytes();
  }

  static int _syncsafe(Uint8List b, int at) =>
      ((b[at] & 0x7F) << 21) |
      ((b[at + 1] & 0x7F) << 14) |
      ((b[at + 2] & 0x7F) << 7) |
      (b[at + 3] & 0x7F);

  static int _int32(Uint8List b, int at) =>
      (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
}
