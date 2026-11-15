import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/lyrics/id3_lyrics_reader.dart';
import 'package:sonus_next/features/import/domain/services/audio_byte_source.dart';

/// App Update 1.3 (REF-1.3-07): lyrics inside an MP3's ID3v2 tag.
class _Bytes implements AudioByteSource {
  _Bytes(this.bytes);

  final Uint8List bytes;
  final reads = <(int, int)>[];

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<DateTime?> modifiedAt() async => null;

  @override
  Future<Uint8List> read(int offset, int count) async {
    reads.add((offset, count));
    final end = (offset + count).clamp(0, bytes.length);
    return Uint8List.sublistView(bytes, offset.clamp(0, end), end);
  }

  @override
  Future<void> close() async {}
}

List<int> _syncsafe(int n) => [
  (n >> 21) & 0x7F,
  (n >> 14) & 0x7F,
  (n >> 7) & 0x7F,
  n & 0x7F,
];

List<int> _int32(int n) => [
  (n >> 24) & 0xFF,
  (n >> 16) & 0xFF,
  (n >> 8) & 0xFF,
  n & 0xFF,
];

/// An ID3v2.[major] tag with [frames], then fake audio.
Uint8List _tag(int major, List<List<int>> frames, {int flags = 0}) {
  final body = [for (final frame in frames) ...frame];
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    major,
    0,
    flags,
    ..._syncsafe(body.length),
    ...body,
    0xFF, 0xFB, 0x90, 0x00, // audio
  ]);
}

List<int> _frame(int major, String id, List<int> body, {int format = 0}) => [
  ...ascii.encode(id),
  ...(major == 4 ? _syncsafe(body.length) : _int32(body.length)),
  0,
  format,
  ...body,
];

List<int> _frame22(String id, List<int> body) => [
  ...ascii.encode(id),
  (body.length >> 16) & 0xFF,
  (body.length >> 8) & 0xFF,
  body.length & 0xFF,
  ...body,
];

List<int> _utf16le(String text) => [
  0xFF,
  0xFE,
  for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
];

/// USLT/ULT: encoding, "eng", descriptor + terminator, text.
List<int> _uslt(int encoding, String text, {String descriptor = ''}) =>
    switch (encoding) {
      0 => [
        0,
        ...ascii.encode('eng'),
        ...latin1.encode(descriptor),
        0,
        ...latin1.encode(text),
      ],
      3 => [
        3,
        ...ascii.encode('eng'),
        ...utf8.encode(descriptor),
        0,
        ...utf8.encode(text),
      ],
      _ => [
        1,
        ...ascii.encode('eng'),
        ..._utf16le(descriptor),
        0,
        0,
        ..._utf16le(text),
      ],
    };

/// SYLT: UTF-8, "eng", [format], lyrics content, no descriptor, lines.
List<int> _sylt(List<(String, int)> lines, {int format = 2}) => [
  3,
  ...ascii.encode('eng'),
  format,
  1,
  0,
  for (final (text, ms) in lines) ...[...utf8.encode(text), 0, ..._int32(ms)],
];

/// ID3 unsynchronisation: a zero after every FF that is followed by a
/// byte of E0 or more, or by zero.
List<int> _unsync(List<int> bytes) => [
  for (var i = 0; i < bytes.length; i++) ...[
    bytes[i],
    if (bytes[i] == 0xFF &&
        (i + 1 == bytes.length || bytes[i + 1] >= 0xE0 || bytes[i + 1] == 0x00))
      0x00,
  ],
];

Future<EmbeddedLyrics?> _read(Uint8List bytes) =>
    Id3LyricsReader.read(_Bytes(bytes));

void main() {
  test('ID3v2.3 USLT in Latin-1', () async {
    final lyrics = await _read(
      _tag(3, [_frame(3, 'USLT', _uslt(0, 'Où es-tu\r\nÜ'))]),
    );
    expect(lyrics!.plain, 'Où es-tu\nÜ');
    expect(lyrics.syncedLrc, isNull);
  });

  test('ID3v2.4 USLT in UTF-8 with a descriptor', () async {
    final lyrics = await _read(
      _tag(4, [
        _frame(4, 'USLT', _uslt(3, 'Hold me close 🎵', descriptor: 'Lyrics')),
      ]),
    );
    expect(lyrics!.plain, 'Hold me close 🎵');
  });

  test('UTF-16 with a byte order mark', () async {
    final lyrics = await _read(
      _tag(3, [_frame(3, 'USLT', _uslt(1, 'Ça va', descriptor: 'd'))]),
    );
    expect(lyrics!.plain, 'Ça va');
  });

  test('SYLT in milliseconds becomes LRC', () async {
    final lyrics = await _read(
      _tag(3, [
        _frame(3, 'SYLT', _sylt([('First', 12340), ('Second', 75000)])),
      ]),
    );
    expect(lyrics!.syncedLrc, '[00:12.34]First\n[01:15.00]Second');
  });

  test('SYLT timed in MPEG frames is not read', () async {
    final lyrics = await _read(
      _tag(3, [
        _frame(3, 'SYLT', _sylt([('Line', 10)], format: 1)),
      ]),
    );
    expect(lyrics, isNull);
  });

  test('both kinds together, after artwork whose body is never read', () async {
    final artwork = List<int>.filled(200000, 7);
    final source = _Bytes(
      _tag(3, [
        _frame(3, 'APIC', artwork),
        _frame(3, 'USLT', _uslt(3, 'Plain words')),
        _frame(3, 'SYLT', _sylt([('Timed', 1000)])),
      ]),
    );
    final lyrics = await Id3LyricsReader.read(source);
    expect(lyrics!.plain, 'Plain words');
    expect(lyrics.syncedLrc, '[00:01.00]Timed');
    expect(
      source.reads.every((read) => read.$2 < artwork.length),
      isTrue,
      reason: 'the artwork is stepped over',
    );
  });

  test('ID3v2.2 ULT and SLT', () async {
    final lyrics = await _read(
      _tag(2, [
        _frame22('ULT', _uslt(0, 'Old tag')),
        _frame22('SLT', _sylt([('Old timed', 2500)])),
      ]),
    );
    expect(lyrics!.plain, 'Old tag');
    expect(lyrics.syncedLrc, '[00:02.50]Old timed');
  });

  test('ID3v2.4 frame unsynchronisation is undone', () async {
    // "ÿ" (0xFF) in Latin-1 is written 0xFF 0x00 when unsynchronised.
    final body = [0, ...ascii.encode('eng'), 0, 0x41, 0xFF, 0x00, 0x42];
    final lyrics = await _read(
      _tag(4, [_frame(4, 'USLT', body, format: 0x02)]),
    );
    expect(lyrics!.plain, 'AÿB');
  });

  test('a long ID3v2.4 frame: its size is syncsafe', () async {
    final words = List.filled(60, 'words').join(' ');
    final lyrics = await _read(_tag(4, [_frame(4, 'USLT', _uslt(3, words))]));
    expect(lyrics!.plain, words);
  });

  test('unsynchronised UTF-16, per frame (2.4) and per tag (2.3)', () async {
    // "ÿA" in UTF-16LE is FF FE | FF 00 | 41 00: unsynchronisation adds a
    // zero after each FF, which would shift every following character.
    final body = _unsync(_uslt(1, 'ÿA'));
    final perFrame = await _read(
      _tag(4, [_frame(4, 'USLT', body, format: 0x02)]),
    );
    expect(perFrame!.plain, 'ÿA');
    final perTag = await _read(_tag(3, [_frame(3, 'USLT', body)], flags: 0x80));
    expect(perTag!.plain, 'ÿA');
  });

  test('compressed or encrypted frames are skipped', () async {
    final lyrics = await _read(
      _tag(4, [_frame(4, 'USLT', _uslt(3, 'Hidden'), format: 0x08)]),
    );
    expect(lyrics, isNull);
  });

  test('no tag, an unknown version, or a broken tag: null, never a '
      'throw', () async {
    expect(await _read(Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00])), isNull);
    final v5 = _tag(3, [_frame(3, 'USLT', _uslt(0, 'x'))])..[3] = 5;
    expect(await _read(v5), isNull);
    // A frame size running past the tag.
    final broken = _tag(3, [_frame(3, 'USLT', _uslt(0, 'Too long'))]);
    broken.setRange(14, 18, _int32(1 << 20));
    expect(await _read(broken), isNull);
    // An unknown text encoding.
    final odd = _tag(3, [
      _frame(3, 'USLT', [9, ...ascii.encode('eng'), 0, 0x41]),
    ]);
    expect(await _read(odd), isNull);
  });

  test('empty lyrics frames give nothing', () async {
    final lyrics = await _read(_tag(3, [_frame(3, 'USLT', _uslt(3, '   '))]));
    expect(lyrics, isNull);
  });
}
