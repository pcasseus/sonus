import 'dart:typed_data';

import '../../../domain/services/audio_byte_source.dart';

/// Where an MP3 file's audio frames are: everything that is not a tag.
class Mp3AudioRegion {
  const Mp3AudioRegion({required this.start, required this.end});

  /// The first byte of the first audio frame.
  final int start;

  /// One past the last audio byte.
  final int end;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is Mp3AudioRegion && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Mp3AudioRegion($start..$end)';
}

/// Why a file's audio could not be located with confidence.
enum Mp3RegionFailure {
  /// Shorter than a tag header and two frames.
  tooShort,

  /// An ID3v2 header that does not follow the specification.
  malformedId3v2,

  /// A trailing tag whose size points outside the file.
  malformedTrailingTag,

  /// After the tags, no pair of valid MPEG audio frames.
  noAudioFrames,
}

/// The result of [Mp3AudioRegionLocator.locate]: a region or a failure.
final class Mp3RegionResult {
  const Mp3RegionResult.found(Mp3AudioRegion this.region) : failure = null;

  const Mp3RegionResult.failed(Mp3RegionFailure this.failure) : region = null;

  final Mp3AudioRegion? region;
  final Mp3RegionFailure? failure;
}

/// Finds an MP3's audio frames by stepping over every tag a tag editor
/// writes (App Update 1.2, BUG-09):
///
/// - leading ID3v2.2, 2.3 and 2.4 tags, one or more, with any extended
///   header (it is counted in the tag's size) and a 2.4 footer;
/// - zero padding after them;
/// - at the end, in any order: ID3v1 (`TAG`, 128 bytes), APEv1/APEv2
///   (`APETAGEX`), Lyrics3 v1 and v2, and an appended ID3v2.4 tag (`3DI`).
///
/// The audio must then begin with two consecutive valid MPEG audio frame
/// headers. Anything else is a [Mp3RegionFailure], never a guess, so an
/// unusual file is sent to review instead of being matched.
///
/// Reads are bounded: a few small ranges, never the audio itself.
abstract final class Mp3AudioRegionLocator {
  /// How far zero padding after the leading tags is skipped.
  static const int maxLeadingPadding = 64 * 1024;

  static Future<Mp3RegionResult> locate(AudioByteSource source) async {
    final length = await source.length();
    if (length < 10 + 8) {
      return const Mp3RegionResult.failed(Mp3RegionFailure.tooShort);
    }

    // Leading ID3v2 tags.
    var start = 0;
    while (start + 10 <= length) {
      final header = await source.read(start, 10);
      if (!_isId3v2Identifier(header, 'ID3')) break;
      final size = _id3v2TagSize(header);
      if (size == null) {
        return const Mp3RegionResult.failed(Mp3RegionFailure.malformedId3v2);
      }
      start += size;
      if (start > length) {
        return const Mp3RegionResult.failed(Mp3RegionFailure.malformedId3v2);
      }
    }

    // Trailing tags.
    final end = await _trailingEnd(source, length, start);
    if (end == null) {
      return const Mp3RegionResult.failed(
        Mp3RegionFailure.malformedTrailingTag,
      );
    }

    // Zero padding, then the first frame.
    final padding = await source.read(
      start,
      _min(maxLeadingPadding, end - start),
    );
    var skipped = 0;
    while (skipped < padding.length && padding[skipped] == 0) {
      skipped++;
    }
    start += skipped;

    if (!await _startsWithTwoFrames(source, start, end)) {
      return const Mp3RegionResult.failed(Mp3RegionFailure.noAudioFrames);
    }
    return Mp3RegionResult.found(Mp3AudioRegion(start: start, end: end));
  }

  /// Steps back over every tag at the end; null when one is malformed.
  static Future<int?> _trailingEnd(
    AudioByteSource source,
    int length,
    int start,
  ) async {
    var end = length;

    // ID3v1 is only ever the very last 128 bytes.
    if (end - start >= 128) {
      final tag = await source.read(end - 128, 3);
      if (_ascii(tag, 0, 3) == 'TAG') end -= 128;
    }

    // The others may come in any order; each is recognised by its footer.
    for (var guard = 0; guard < 8; guard++) {
      final next = await _stepOverTrailingTag(source, start, end);
      if (next == null) return null;
      if (next == end) return end;
      end = next;
    }
    return null;
  }

  /// The end before one trailing tag, [end] itself when there is none, or
  /// null when a tag is malformed.
  static Future<int?> _stepOverTrailingTag(
    AudioByteSource source,
    int start,
    int end,
  ) async {
    final available = end - start;

    // APEv1 / APEv2: a 32-byte footer, `APETAGEX`.
    if (available >= 32) {
      final footer = await source.read(end - 32, 32);
      if (_ascii(footer, 0, 8) == 'APETAGEX') {
        final size = _uint32le(footer, 12);
        final flags = _uint32le(footer, 20);
        final hasHeader = flags & 0x80000000 != 0;
        final total = size + (hasHeader ? 32 : 0);
        if (size < 32 || total > available) return null;
        return end - total;
      }
    }

    // An appended ID3v2.4 tag: a 10-byte footer, `3DI`.
    if (available >= 10) {
      final footer = await source.read(end - 10, 10);
      if (_isId3v2Identifier(footer, '3DI')) {
        final size = _syncsafe(footer, 6);
        if (size == null) return null;
        final total = size + 20;
        if (total > available) return null;
        return end - total;
      }
    }

    // Lyrics3 v2: a six-digit size, then `LYRICS200`.
    if (available >= 15) {
      final footer = await source.read(end - 15, 15);
      final marker = _ascii(footer, 6, 9);
      if (marker == 'LYRICS200') {
        final size = int.tryParse(_ascii(footer, 0, 6));
        if (size == null || size + 15 > available) return null;
        return end - size - 15;
      }
      if (marker == 'LYRICSEND') {
        // Lyrics3 v1: no size; `LYRICSBEGIN` within 5,100 bytes before.
        final window = _min(5100 + 11, available);
        final bytes = await source.read(end - window, window);
        final text = String.fromCharCodes(bytes);
        final begin = text.lastIndexOf('LYRICSBEGIN');
        if (begin < 0) return null;
        return end - window + begin;
      }
    }

    return end;
  }

  static Future<bool> _startsWithTwoFrames(
    AudioByteSource source,
    int start,
    int end,
  ) async {
    if (end - start < 8) return false;
    final first = _MpegFrameHeader.parse(await source.read(start, 4));
    if (first == null) return false;
    final second = start + first.frameLength;
    if (second + 4 > end) return false;
    return _MpegFrameHeader.parse(await source.read(second, 4)) != null;
  }

  static bool _isId3v2Identifier(Uint8List header, String identifier) {
    if (header.length < 10 || _ascii(header, 0, 3) != identifier) {
      return false;
    }
    return true;
  }

  /// The whole tag's size, header and footer included; null when the
  /// header breaks the specification.
  static int? _id3v2TagSize(Uint8List header) {
    final major = header[3];
    final revision = header[4];
    if (major < 2 || major > 4 || revision == 0xFF) return null;
    final size = _syncsafe(header, 6);
    if (size == null) return null;
    final hasFooter = major == 4 && header[5] & 0x10 != 0;
    return 10 + size + (hasFooter ? 10 : 0);
  }

  static int? _syncsafe(Uint8List bytes, int offset) {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final byte = bytes[offset + i];
      if (byte & 0x80 != 0) return null;
      value = (value << 7) | byte;
    }
    return value;
  }

  static int _uint32le(Uint8List bytes, int offset) =>
      bytes[offset] |
      bytes[offset + 1] << 8 |
      bytes[offset + 2] << 16 |
      bytes[offset + 3] << 24;

  static String _ascii(Uint8List bytes, int offset, int count) =>
      offset + count > bytes.length
      ? ''
      : String.fromCharCodes(bytes, offset, offset + count);

  static int _min(int a, int b) => a < b ? a : b;
}

/// An MPEG-1, 2 or 2.5 audio frame header (Layers I to III).
class _MpegFrameHeader {
  const _MpegFrameHeader(this.frameLength);

  final int frameLength;

  static const _bitrates = <String, List<int>>{
    '1-1': [
      0,
      32,
      64,
      96,
      128,
      160,
      192,
      224,
      256,
      288,
      320,
      352,
      384,
      416,
      448,
    ],
    '1-2': [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
    '1-3': [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
    '2-1': [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
    '2-2': [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    '2-3': [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  };

  static const _sampleRates = <int, List<int>>{
    1: [44100, 48000, 32000],
    2: [22050, 24000, 16000],
    25: [11025, 12000, 8000],
  };

  /// Null unless [bytes] start with a valid header of a known frame size
  /// (free-format and reserved values are refused).
  static _MpegFrameHeader? parse(Uint8List bytes) {
    if (bytes.length < 4) return null;
    if (bytes[0] != 0xFF || bytes[1] & 0xE0 != 0xE0) return null;

    final version = switch ((bytes[1] >> 3) & 0x03) {
      0 => 25,
      2 => 2,
      3 => 1,
      _ => null,
    };
    final layer = switch ((bytes[1] >> 1) & 0x03) {
      1 => 3,
      2 => 2,
      3 => 1,
      _ => null,
    };
    final bitrateIndex = (bytes[2] >> 4) & 0x0F;
    final sampleRateIndex = (bytes[2] >> 2) & 0x03;
    final padding = (bytes[2] >> 1) & 0x01;
    if (version == null ||
        layer == null ||
        bitrateIndex == 0 ||
        bitrateIndex == 15 ||
        sampleRateIndex == 3 ||
        bytes[3] & 0x03 == 2) {
      return null;
    }

    final table = '${version == 1 ? 1 : 2}-$layer';
    final bitrate = _bitrates[table]![bitrateIndex] * 1000;
    final sampleRate = _sampleRates[version]![sampleRateIndex];

    final length = switch (layer) {
      1 => (12 * bitrate ~/ sampleRate + padding) * 4,
      2 => 144 * bitrate ~/ sampleRate + padding,
      _ => (version == 1 ? 144 : 72) * bitrate ~/ sampleRate + padding,
    };
    return length < 4 ? null : _MpegFrameHeader(length);
  }
}
