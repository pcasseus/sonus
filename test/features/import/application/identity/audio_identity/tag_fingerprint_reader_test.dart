// App Update 1.2, BUG-09 Refinement B: a fingerprint of an MP3's tags tells
// text edits from artwork edits, notices same-size changes, ignores the
// audio, reads only a few small ranges, and refuses tags it cannot walk.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/identity/audio_identity/tag_fingerprint_reader.dart';

import '../../../../../support/synthetic_mp3.dart';

void main() {
  const reader = TagFingerprintReader();
  final audio = syntheticAudio();

  List<List<int>> frames({
    String title = 'Ill Show You',
    String artist = 'Justin Bieber',
    String album = 'Purpose',
    String track = '3',
    List<int>? image,
    int major = 3,
  }) => [
    id3v2Frame(major == 2 ? 'TT2' : 'TIT2', id3v2Text(title), major: major),
    id3v2Frame(major == 2 ? 'TP1' : 'TPE1', id3v2Text(artist), major: major),
    id3v2Frame(major == 2 ? 'TAL' : 'TALB', id3v2Text(album), major: major),
    id3v2Frame(major == 2 ? 'TRK' : 'TRCK', id3v2Text(track), major: major),
    if (image != null)
      id3v2Frame(
        major == 2 ? 'PIC' : 'APIC',
        id3v2Picture(image),
        major: major,
      ),
  ];

  Future<TagFingerprint?> fingerprint(
    List<List<int>> tagFrames, {
    int major = 3,
    Uint8List? withAudio,
    List<List<int>> trailing = const [],
    bool unsynchronised = false,
  }) => reader.read(
    MemoryAudioByteSource(
      syntheticMp3(
        withAudio ?? audio,
        leading: [
          id3v2TagWithFrames(
            tagFrames,
            major: major,
            unsynchronised: unsynchronised,
          ),
        ],
        trailing: trailing,
      ),
    ),
  );

  test('the same tags give the same fingerprint; any text edit changes the '
      'text part only', () async {
    final image = syntheticImage(30000);
    final original = (await fingerprint(frames(image: image)))!;

    expect((await fingerprint(frames(image: image)))!.value, original.value);
    for (final edited in [
      frames(title: "I'll Show You", image: image),
      frames(artist: 'Justin Biebor', image: image), // same size
      frames(album: 'Purpase', image: image), // same size
      frames(track: '2', image: image), // same size
    ]) {
      final changed = (await fingerprint(edited))!;
      expect(changed.text, isNot(original.text));
      expect(changed.pictures, original.pictures);
    }
  });

  test(
    'a same-size artwork replacement changes the picture part only',
    () async {
      final original = (await fingerprint(
        frames(image: syntheticImage(30000)),
      ))!;
      final replaced = (await fingerprint(
        frames(image: syntheticImage(30000, seed: 2)),
      ))!;

      expect(replaced.pictures, isNot(original.pictures));
      expect(replaced.text, original.text);
    },
  );

  test('artwork added or removed is seen', () async {
    final none = (await fingerprint(frames()))!;
    final added = (await fingerprint(frames(image: syntheticImage(5000))))!;
    expect(added.pictures, isNot(none.pictures));
  });

  test('the audio does not take part', () async {
    final a = (await fingerprint(frames()))!;
    final b = (await fingerprint(
      frames(),
      withAudio: syntheticAudio(seed: 9),
    ))!;
    expect(b.value, a.value);
  });

  test('every ID3v2 version, and trailing tags, take part', () async {
    for (final major in [2, 3, 4]) {
      final a = await fingerprint(frames(major: major), major: major);
      final b = await fingerprint(
        frames(major: major, title: 'Other'),
        major: major,
      );
      expect(a, isNotNull, reason: 'version 2.$major');
      expect(b!.text, isNot(a!.text), reason: 'version 2.$major');
    }

    final v1 = (await fingerprint(frames(), trailing: [id3v1Tag()]))!;
    final v1Edited = (await fingerprint(
      frames(),
      trailing: [id3v1Tag(title: 'Other')],
    ))!;
    expect(v1Edited.text, isNot(v1.text));
    expect(
      (await fingerprint(frames(), trailing: [apeTag(), id3v1Tag()]))!.text,
      isNot(v1.text),
    );
  });

  test('a tag with an extended header is walked past it', () async {
    Future<TagFingerprint?> withExtended(String title) => reader.read(
      MemoryAudioByteSource(
        syntheticMp3(
          audio,
          leading: [id3v2Tag(extendedHeader: true, title: title)],
        ),
      ),
    );
    final a = await withExtended('Title');
    final b = await withExtended('Other');
    expect(a, isNotNull);
    expect(b!.text, isNot(a!.text));
  });

  test('round-trips as text and refuses anything else', () async {
    final value = (await fingerprint(frames()))!.value;
    expect(value, startsWith('t1:'));
    expect(TagFingerprint.tryParse(value)!.value, value);
    expect(TagFingerprint.tryParse(null), isNull);
    expect(TagFingerprint.tryParse('t0:a:b'), isNull);
    expect(TagFingerprint.tryParse('t1:a'), isNull);
  });

  group('tags it cannot walk give no fingerprint', () {
    test('unsynchronised tags', () async {
      expect(await fingerprint(frames(), unsynchronised: true), isNull);
    });

    test('a frame running past its tag', () async {
      final broken = id3v2Frame('TIT2', id3v2Text('Title'));
      broken[4] = 0x7F; // size far beyond the tag
      expect(await fingerprint([broken]), isNull);
    });

    test('a frame id that is not one', () async {
      expect(
        await fingerprint([id3v2Frame('ti#2', id3v2Text('Title'))]),
        isNull,
      );
    });

    test('a file with no audio', () async {
      expect(
        await reader.read(MemoryAudioByteSource(Uint8List.fromList([1, 2]))),
        isNull,
      );
    });

    test('a read that fails', () async {
      expect(await reader.read(_FailingSource()), isNull);
    });
  });

  test('reads stay small even with large artwork', () async {
    final source = MemoryAudioByteSource(
      syntheticMp3(
        syntheticAudio(frames: 24000),
        leading: [id3v2TagWithFrames(frames(image: syntheticImage(2000000)))],
        trailing: [id3v1Tag()],
      ),
    );

    await reader.read(source);

    expect(source.bytes.length, greaterThan(12000000));
    // One 16 KiB window of the tag, the picture's last sample and the
    // trailing tag: never the audio.
    expect(source.bytesRead, lessThan(16 * 1024 + 2 * 4096 + 2048));
    expect(source.readSizes.length, lessThan(20));
  });
}

class _FailingSource extends MemoryAudioByteSource {
  _FailingSource() : super(Uint8List(0));

  @override
  Future<int> length() async => 1 << 20;

  @override
  Future<Uint8List> read(int offset, int count) =>
      Future.error(const FormatException('device read failed'));
}
