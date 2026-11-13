import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../domain/services/audio_byte_source.dart';
import 'mp3_audio_region.dart';

/// A fingerprint of an MP3 file's tags (App Update 1.2, BUG-09 Refinement
/// B), in two parts: its text tags and its embedded pictures.
class TagFingerprint {
  const TagFingerprint({required this.text, required this.pictures});

  /// The rules that produce it; bump when they change.
  static const int currentVersion = 1;

  /// SHA-256 of every non-picture frame of the leading ID3v2 tags (title,
  /// artists, album, numbers, year, genre and anything else) and of every
  /// trailing tag (ID3v1, APE, Lyrics3, an appended ID3v2).
  final String text;

  /// SHA-256 over each embedded picture's frame header, size and the first
  /// and last [TagFingerprintReader.pictureSample] bytes of its data.
  final String pictures;

  /// `t1:<text>:<pictures>`.
  String get value => 't$currentVersion:$text:$pictures';

  /// Null for anything that is not a fingerprint of the current rules.
  static TagFingerprint? tryParse(String? value) {
    final parts = value?.split(':');
    if (parts == null ||
        parts.length != 3 ||
        parts[0] != 't$currentVersion' ||
        parts[1].isEmpty ||
        parts[2].isEmpty) {
      return null;
    }
    return TagFingerprint(text: parts[1], pictures: parts[2]);
  }
}

/// Reads [TagFingerprint]s with bounded reads (App Update 1.2, BUG-09
/// Refinement B), so a tag edit that keeps a file's size and modification
/// time is still noticed without hashing the audio:
///
/// - the leading ID3v2 tags (2.2, 2.3, 2.4) are walked frame by frame from
///   one buffered read of their first [window] bytes; text and other small
///   frames are hashed whole;
/// - pictures (APIC, PIC) are sampled: header, size, and the first and last
///   [pictureSample] bytes of their data. A replaced picture almost always
///   differs there (image headers, tables and end markers), even at the
///   same size; a picture changed only in its middle bytes is not seen;
/// - other large frames (over [wholeFrameLimit]) are sampled the same way;
/// - trailing tags are hashed whole when small, sampled when not.
///
/// A tag that cannot be walked with confidence (unsynchronised, or a frame
/// running past its tag) gives no fingerprint, never a guess: the scan then
/// relies on size and time as before.
class TagFingerprintReader {
  const TagFingerprintReader({
    this.window = 16 * 1024,
    this.wholeFrameLimit = 64 * 1024,
    this.pictureSample = 4 * 1024,
  });

  final int window;
  final int wholeFrameLimit;
  final int pictureSample;

  Future<TagFingerprint?> read(AudioByteSource source) async {
    try {
      return await _read(source);
    } catch (error, stackTrace) {
      developer.log(
        'Tag fingerprint failed (${error.runtimeType})',
        name: 'sonus.import.tag_fingerprint',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<TagFingerprint?> _read(AudioByteSource source) async {
    final length = await source.length();
    if (length < 18) return null;

    final text = <int>[];
    final pictures = <int>[];

    // Leading ID3v2 tags, walked directly: the audio is never read.
    var offset = 0;
    while (offset + 10 <= length) {
      final tagEnd = await _walkTag(source, offset, length, text, pictures);
      if (tagEnd == null) return null;
      if (tagEnd == offset) break; // no further tag
      offset = tagEnd;
    }
    // After the tags (and any zero padding) an MP3 begins with a frame.
    if (offset == 0 && !_startsWithFrameSync(await source.read(0, 2))) {
      return null;
    }

    // Trailing tags, found from their footers in a few small reads.
    final trailingStart = await Mp3AudioRegionLocator.trailingTagsStart(
      source,
      length: length,
      audioStart: offset,
    );
    if (trailingStart == null) return null;
    final trailing = length - trailingStart;
    if (trailing > 0) {
      text.addAll(utf8.encode('trailing:$trailing;'));
      await _addWholeOrSampled(source, trailingStart, trailing, text);
    }

    return TagFingerprint(
      text: sha256.convert(text).toString(),
      pictures: sha256.convert(pictures).toString(),
    );
  }

  /// Hashes one ID3v2 tag at [start]; where it ends, [start] for padding,
  /// or null when it cannot be walked with confidence.
  Future<int?> _walkTag(
    AudioByteSource source,
    int start,
    int limit,
    List<int> text,
    List<int> pictures,
  ) async {
    final header = await source.read(start, 10);
    if (header.length < 10 ||
        header[0] != 0x49 || // I
        header[1] != 0x44 || // D
        header[2] != 0x33) {
      // Not a tag: the zero padding before the audio.
      return start;
    }
    final major = header[3];
    final flags = header[5];
    final size = _syncsafe(header, 6);
    if (major < 2 || major > 4 || size == null) return null;
    // Unsynchronised frames need decoding before they can be walked.
    if (flags & 0x80 != 0) return null;
    final footer = major == 4 && flags & 0x10 != 0 ? 10 : 0;
    final tagEnd = start + 10 + size + footer;
    if (tagEnd > limit) return null;

    text.addAll(utf8.encode('id3v2.$major:$size;'));
    final buffer = _Window(source, start + 10, size, window);
    var cursor = 0;

    // The extended header is part of the tag; skip it.
    if (flags & 0x40 != 0 && major >= 3) {
      final ext = await buffer.read(0, 4);
      if (ext.length < 4) return null;
      final extSize = major == 4
          ? _syncsafe(ext, 0)
          : _uint32(ext, 0) + 4; // 2.3 does not count its own size field
      if (extSize == null || extSize > size) return null;
      cursor = extSize;
    }

    final headerLength = major == 2 ? 6 : 10;
    while (cursor + headerLength <= size) {
      final frameHeader = await buffer.read(cursor, headerLength);
      if (frameHeader[0] == 0) break; // padding
      final id = String.fromCharCodes(frameHeader, 0, major == 2 ? 3 : 4);
      if (!RegExp(r'^[A-Z0-9]{3,4}$').hasMatch(id)) return null;
      final frameSize = switch (major) {
        2 => frameHeader[3] << 16 | frameHeader[4] << 8 | frameHeader[5],
        3 => _uint32(frameHeader, 4),
        _ => _syncsafe(frameHeader, 4),
      };
      if (frameSize == null) return null;
      final bodyStart = cursor + headerLength;
      if (bodyStart + frameSize > size) return null;

      final isPicture = id == 'APIC' || id == 'PIC';
      final target = isPicture ? pictures : text;
      target
        ..addAll(utf8.encode('$id:$frameSize;'))
        ..addAll(frameHeader);
      if (!isPicture && frameSize <= wholeFrameLimit) {
        target.addAll(await buffer.read(bodyStart, frameSize));
      } else {
        final sample = pictureSample;
        target.addAll(await buffer.read(bodyStart, _min(sample, frameSize)));
        if (frameSize > sample) {
          target.addAll(
            await buffer.read(bodyStart + frameSize - sample, sample),
          );
        }
      }
      cursor = bodyStart + frameSize;
    }
    return tagEnd;
  }

  Future<void> _addWholeOrSampled(
    AudioByteSource source,
    int start,
    int count,
    List<int> into,
  ) async {
    if (count <= wholeFrameLimit) {
      into.addAll(await source.read(start, count));
      return;
    }
    into
      ..addAll(await source.read(start, pictureSample))
      ..addAll(await source.read(start + count - pictureSample, pictureSample));
  }

  static bool _startsWithFrameSync(Uint8List bytes) =>
      bytes.length == 2 && bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0;

  static int? _syncsafe(Uint8List bytes, int offset) {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final byte = bytes[offset + i];
      if (byte & 0x80 != 0) return null;
      value = (value << 7) | byte;
    }
    return value;
  }

  static int _uint32(Uint8List bytes, int offset) =>
      bytes[offset] << 24 |
      bytes[offset + 1] << 16 |
      bytes[offset + 2] << 8 |
      bytes[offset + 3];

  static int _min(int a, int b) => a < b ? a : b;
}

/// One buffered read of a tag's first [window] bytes, so most tags cost a
/// single read; anything beyond is read directly.
class _Window {
  _Window(this._source, this._start, this._size, this._window);

  final AudioByteSource _source;
  final int _start;
  final int _size;
  final int _window;
  Uint8List? _buffer;

  /// [count] bytes at [offset] within the tag body.
  Future<Uint8List> read(int offset, int count) async {
    if (offset + count > _size) {
      throw RangeError('A frame runs past its tag.');
    }
    if (offset + count <= _window) {
      final buffer = _buffer ??= await _source.read(
        _start,
        _size < _window ? _size : _window,
      );
      if (offset + count > buffer.length) {
        throw RangeError('The file ended inside its tag.');
      }
      return Uint8List.sublistView(buffer, offset, offset + count);
    }
    final bytes = await _source.read(_start + offset, count);
    if (bytes.length != count) {
      throw RangeError('The file ended inside its tag.');
    }
    return bytes;
  }
}
