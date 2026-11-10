// BUG-09: byte-exact synthetic MP3 files, so audio identity rules are tested
// against every tag layout without real music.
import 'dart:math';
import 'dart:typed_data';

import 'package:sonus_next/features/import/domain/services/audio_byte_source.dart';

/// MPEG-1 Layer III, 128 kbit/s, 44.1 kHz, no padding: 417 bytes a frame.
const int syntheticFrameLength = 417;

/// [frames] audio frames whose payload bytes come from [seed].
Uint8List syntheticAudio({int frames = 400, int seed = 1}) {
  final random = Random(seed);
  final bytes = Uint8List(frames * syntheticFrameLength);
  for (var f = 0; f < frames; f++) {
    final at = f * syntheticFrameLength;
    bytes
      ..[at] = 0xFF
      ..[at + 1] = 0xFB
      ..[at + 2] = 0x90
      ..[at + 3] = 0x00;
    for (var i = 4; i < syntheticFrameLength; i++) {
      bytes[at + i] = random.nextInt(256);
    }
  }
  return bytes;
}

List<int> _syncsafe(int value) => [
  (value >> 21) & 0x7F,
  (value >> 14) & 0x7F,
  (value >> 7) & 0x7F,
  value & 0x7F,
];

List<int> _text(String text) => text.codeUnits;

/// An ID3v2 tag of [major] version holding [body] (frames or padding).
List<int> id3v2Tag({
  int major = 3,
  List<int>? body,
  bool extendedHeader = false,
  bool footer = false,
  String title = 'Title',
}) {
  final content = <int>[
    if (extendedHeader) ...[
      // A v2.3 extended header: size 6, no CRC, padding size 0.
      0, 0, 0, 6, 0, 0, 0, 0, 0, 0,
    ],
    ...?body,
    if (body == null) ...[
      ..._text('TIT2'),
      0,
      0,
      0,
      title.length + 1,
      0,
      0,
      0,
      ..._text(title),
      ...List<int>.filled(64, 0),
    ],
  ];
  var flags = 0;
  if (extendedHeader) flags |= 0x40;
  if (footer) flags |= 0x10;
  return [
    ..._text('ID3'),
    major,
    0,
    flags,
    ..._syncsafe(content.length),
    ...content,
    if (footer) ...[
      ..._text('3DI'),
      major,
      0,
      flags,
      ..._syncsafe(content.length),
    ],
  ];
}

/// A 128-byte ID3v1 tag.
List<int> id3v1Tag({String title = 'Title'}) {
  final tag = List<int>.filled(128, 0);
  tag.setRange(0, 3, _text('TAG'));
  tag.setRange(3, 3 + title.length, _text(title));
  return tag;
}

/// An APEv2 tag (with header when [withHeader]) or an APEv1 tag.
List<int> apeTag({bool withHeader = true, int version = 2000}) {
  final items = _text('ape items: title=Title');
  final size = items.length + 32;
  List<int> block(bool isHeader) {
    var flags = 0;
    if (withHeader) flags |= 0x80000000;
    if (isHeader) flags |= 0x20000000;
    int le(int value, int byte) => (value >> (8 * byte)) & 0xFF;
    return [
      ..._text('APETAGEX'),
      for (var b = 0; b < 4; b++) le(version, b),
      for (var b = 0; b < 4; b++) le(size, b),
      1,
      0,
      0,
      0,
      for (var b = 0; b < 4; b++) le(flags, b),
      ...List<int>.filled(8, 0),
    ];
  }

  return [if (withHeader) ...block(true), ...items, ...block(false)];
}

/// A Lyrics3 v2 tag.
List<int> lyrics3v2Tag() {
  final body = _text('LYRICSBEGININD00002110LYR00005hello');
  return [
    ...body,
    ..._text(body.length.toString().padLeft(6, '0')),
    ..._text('LYRICS200'),
  ];
}

/// A Lyrics3 v1 tag.
List<int> lyrics3v1Tag() => _text('LYRICSBEGINsome lyricsLYRICSEND');

/// An ID3v2.4 tag appended at the end, found by its `3DI` footer.
List<int> appendedId3v24Tag() => id3v2Tag(major: 4, footer: true);

/// A file of [audio] wrapped in [leading] and [trailing] tags.
Uint8List syntheticMp3(
  Uint8List audio, {
  List<List<int>> leading = const [],
  int padding = 0,
  List<List<int>> trailing = const [],
}) => Uint8List.fromList([
  for (final tag in leading) ...tag,
  ...List<int>.filled(padding, 0),
  ...audio,
  for (final tag in trailing) ...tag,
]);

/// An in-memory [AudioByteSource] that records every read.
class MemoryAudioByteSource implements AudioByteSource {
  MemoryAudioByteSource(this.bytes);

  final Uint8List bytes;
  final List<int> readSizes = [];
  bool closed = false;

  int get bytesRead => readSizes.fold(0, (a, b) => a + b);

  int get largestRead => readSizes.fold(0, max);

  @override
  Future<int> length() async => bytes.length;

  /// Set by a test; when the file last changed.
  DateTime? lastModified;

  @override
  Future<DateTime?> modifiedAt() async => lastModified;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || offset > bytes.length) {
      throw RangeError.range(offset, 0, bytes.length);
    }
    final end = min(bytes.length, offset + count);
    readSizes.add(end - offset);
    return Uint8List.sublistView(bytes, offset, end);
  }

  @override
  Future<void> close() async => closed = true;
}
