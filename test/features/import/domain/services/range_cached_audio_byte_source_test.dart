// App Update 1.2, BUG-09 scan cost: the range cache returns exactly the
// source's bytes, so a tag fingerprint is unchanged, in far fewer reads.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/identity/audio_identity/tag_fingerprint_reader.dart';
import 'package:sonus_next/features/import/domain/services/range_cached_audio_byte_source.dart';

import '../../../../support/synthetic_mp3.dart';

void main() {
  Uint8List file({
    int pictureBytes = 60000,
    List<List<int>> trailing = const [],
  }) => syntheticMp3(
    syntheticAudio(frames: 2000),
    leading: [
      id3v2TagWithFrames([
        id3v2Frame('TIT2', id3v2Text('Title')),
        id3v2Frame('TPE1', id3v2Text('Artist')),
        if (pictureBytes > 0)
          id3v2Frame('APIC', id3v2Picture(syntheticImage(pictureBytes))),
      ]),
    ],
    trailing: trailing,
  );

  test('every range reads exactly the source bytes', () async {
    final bytes = file(trailing: [apeTag(), id3v1Tag()]);
    final random = Random(3);
    final cached = RangeCachedAudioByteSource(
      MemoryAudioByteSource(bytes),
      headBytes: 4096,
      tailBytes: 2048,
    );
    final ranges = [
      (0, 10),
      (0, 4096),
      (4090, 20),
      (bytes.length - 128, 128),
      (bytes.length - 3000, 3000),
      (bytes.length - 5, 50), // past the end
      (bytes.length + 10, 4), // beyond the end
      for (var i = 0; i < 200; i++)
        (random.nextInt(bytes.length), random.nextInt(9000)),
    ];
    for (final (offset, count) in ranges) {
      final end = min(bytes.length, offset + count);
      final expected = offset >= bytes.length
          ? Uint8List(0)
          : Uint8List.sublistView(bytes, offset, end);
      expect(
        await cached.read(offset, count),
        expected,
        reason: '$offset+$count',
      );
    }
  });

  test('a known length is used without asking the source', () async {
    final source = _CountingLength(file());
    final cached = RangeCachedAudioByteSource(
      source,
      knownLength: source.bytes.length,
    );
    expect(await cached.length(), source.bytes.length);
    expect(source.lengthCalls, 0);
  });

  test(
    'a tag fingerprint is the same through the cache, in a few reads',
    () async {
      const reader = TagFingerprintReader();
      for (final bytes in [
        file(),
        file(pictureBytes: 0),
        file(pictureBytes: 2000000, trailing: [lyrics3v2Tag(), id3v1Tag()]),
        file(trailing: [apeTag(), appendedId3v24Tag()]),
      ]) {
        final direct = MemoryAudioByteSource(bytes);
        final viaCache = MemoryAudioByteSource(bytes);
        final plain = await reader.read(direct);
        final cached = await reader.read(
          RangeCachedAudioByteSource(viaCache, knownLength: bytes.length),
        );

        expect(cached?.value, plain?.value);
        expect(plain, isNotNull);
        expect(viaCache.readSizes.length, lessThan(direct.readSizes.length));
        // Header, tag window and the end tags share a read each (on the
        // phone each read reopens the document); was 9 on the first file.
        expect(viaCache.readSizes.length, lessThanOrEqualTo(5));
      }
    },
  );
}

class _CountingLength extends MemoryAudioByteSource {
  _CountingLength(super.bytes);

  int lengthCalls = 0;

  @override
  Future<int> length() {
    lengthCalls++;
    return super.length();
  }
}
