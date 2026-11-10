// App Update 1.2, BUG-09: an MP3's audio identity ignores every tag a tag
// editor writes, changes whenever the audio does, never reads more than it
// must, and refuses files it cannot read with confidence.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/identity/audio_identity/audio_identity_reader.dart';
import 'package:sonus_next/features/import/application/identity/audio_identity/mp3_audio_region.dart';

import '../../../../../support/synthetic_mp3.dart';

void main() {
  const reader = AudioIdentityReader();

  Future<Mp3RegionResult> locate(Uint8List bytes) =>
      Mp3AudioRegionLocator.locate(MemoryAudioByteSource(bytes));

  Future<AudioIdentity> identify(Uint8List bytes) async {
    final source = MemoryAudioByteSource(bytes);
    final result = await reader.read(source);
    expect(result.failure, isNull);
    final identity = result.identity!;
    return identity.withFullHash(
      (await reader.fullHash(source, identity.region))!,
    );
  }

  final audio = syntheticAudio();

  group('the audio is found behind every tag', () {
    final layouts = <String, (List<List<int>>, int, List<List<int>>)>{
      'no tags': (const [], 0, const []),
      'ID3v2.2': ([id3v2Tag(major: 2)], 0, const []),
      'ID3v2.3': ([id3v2Tag()], 0, const []),
      'ID3v2.4': ([id3v2Tag(major: 4)], 0, const []),
      'ID3v2.3 with an extended header': (
        [id3v2Tag(extendedHeader: true)],
        0,
        const [],
      ),
      'ID3v2.4 with a footer': (
        [id3v2Tag(major: 4, footer: true)],
        0,
        const [],
      ),
      'two ID3v2 tags': ([id3v2Tag(), id3v2Tag(major: 4)], 0, const []),
      'padding after the tag': ([id3v2Tag()], 2048, const []),
      'ID3v1': (const [], 0, [id3v1Tag()]),
      'APEv2 with a header': (const [], 0, [apeTag()]),
      'APEv1 without a header': (
        const [],
        0,
        [apeTag(withHeader: false, version: 1000)],
      ),
      'Lyrics3 v2 then ID3v1': (const [], 0, [lyrics3v2Tag(), id3v1Tag()]),
      'Lyrics3 v1 then ID3v1': (const [], 0, [lyrics3v1Tag(), id3v1Tag()]),
      'an appended ID3v2.4 tag': (const [], 0, [appendedId3v24Tag()]),
      'everything at once': (
        [id3v2Tag(major: 4, extendedHeader: true), id3v2Tag()],
        512,
        [apeTag(), lyrics3v2Tag(), id3v1Tag()],
      ),
    };

    for (final MapEntry(key: name, value: (leading, padding, trailing))
        in layouts.entries) {
      test(name, () async {
        final leadingLength =
            leading.fold<int>(0, (n, tag) => n + tag.length) + padding;
        final file = syntheticMp3(
          audio,
          leading: leading,
          padding: padding,
          trailing: trailing,
        );

        final region = (await locate(file)).region;
        expect(
          region,
          Mp3AudioRegion(
            start: leadingLength,
            end: leadingLength + audio.length,
          ),
        );
      });
    }
  });

  group('retagging keeps the identity; changing the audio does not', () {
    test('the same audio under any tags has one identity', () async {
      final plain = await identify(syntheticMp3(audio));
      final retagged = await identify(
        syntheticMp3(
          audio,
          leading: [id3v2Tag(major: 4, title: 'I’ll Show You')],
          padding: 300,
          trailing: [
            apeTag(),
            id3v1Tag(title: 'Ill Show You'),
          ],
        ),
      );
      final otherTitle = await identify(
        syntheticMp3(audio, leading: [id3v2Tag(title: "I'll Show You")]),
      );

      expect(retagged.signature, plain.signature);
      expect(retagged.fullHash, plain.fullHash);
      expect(otherTitle.signature, plain.signature);
      expect(otherTitle.fullHash, plain.fullHash);
    });

    test('a changed byte in the middle keeps the sample but not the full '
        'hash, which is why the sample alone never rebinds a file', () async {
      final changed = Uint8List.fromList(audio);
      changed[audio.length ~/ 2] ^= 0x01;

      final original = await identify(syntheticMp3(audio));
      final edited = await identify(syntheticMp3(changed));

      expect(edited.signature, original.signature);
      expect(edited.fullHash, isNot(original.fullHash));
    });

    test('a changed byte near either end changes the signature', () async {
      for (final at in [10, audio.length - 10]) {
        final changed = Uint8List.fromList(audio)..[at] ^= 0x01;
        expect(
          (await identify(syntheticMp3(changed))).signature,
          isNot((await identify(syntheticMp3(audio))).signature),
        );
      }
    });

    test('different recordings, and trimmed audio, differ', () async {
      final original = await identify(syntheticMp3(audio));
      final other = await identify(syntheticMp3(syntheticAudio(seed: 2)));
      final trimmed = await identify(
        syntheticMp3(Uint8List.sublistView(audio, 0, audio.length - 417)),
      );

      expect(other.signature, isNot(original.signature));
      expect(trimmed.signature, isNot(original.signature));
      expect(trimmed.fullHash, isNot(original.fullHash));
    });

    test('short audio is hashed whole', () async {
      final short = syntheticAudio(frames: 20);
      final identity = await identify(syntheticMp3(short));
      expect(identity.signature, startsWith('v1:${short.length}:'));
    });
  });

  group('unreadable or unusual files are refused, never guessed', () {
    Future<AudioIdentityFailure?> failureOf(Uint8List bytes) async =>
        (await reader.read(MemoryAudioByteSource(bytes))).failure;

    test('a tag header that breaks the specification', () async {
      final tag = id3v2Tag();
      tag[6] = 0x80; // not syncsafe
      expect(
        await failureOf(syntheticMp3(audio, leading: [tag])),
        AudioIdentityFailure.unsupportedLayout,
      );

      final unknownVersion = id3v2Tag()..[3] = 9;
      expect(
        await failureOf(syntheticMp3(audio, leading: [unknownVersion])),
        AudioIdentityFailure.unsupportedLayout,
      );
    });

    test('a tag larger than the file', () async {
      final tag = id3v2Tag();
      tag.setRange(6, 10, [0x7F, 0x7F, 0x7F, 0x7F]);
      expect(
        await failureOf(syntheticMp3(audio, leading: [tag])),
        AudioIdentityFailure.unsupportedLayout,
      );
      final ape = apeTag();
      ape[ape.length - 32 + 15] = 0x7F; // size far beyond the file
      expect(
        await failureOf(syntheticMp3(audio, trailing: [ape])),
        AudioIdentityFailure.unsupportedLayout,
      );
    });

    test('no audio frames, one frame, or a truncated file', () async {
      final random = Random(7);
      final noise = Uint8List.fromList(
        List.generate(20000, (_) => random.nextInt(256))..[0] = 0x00,
      );
      expect(await failureOf(noise), AudioIdentityFailure.unsupportedLayout);
      expect(
        await failureOf(syntheticMp3(syntheticAudio(frames: 1))),
        AudioIdentityFailure.unsupportedLayout,
      );
      expect(
        await failureOf(Uint8List.fromList(id3v2Tag())),
        AudioIdentityFailure.unsupportedLayout,
      );
      expect(
        await failureOf(Uint8List(5)),
        AudioIdentityFailure.unsupportedLayout,
      );
    });

    test('free-format and reserved frame headers', () async {
      final free = Uint8List.fromList(audio);
      for (var f = 0; f < 2; f++) {
        free[f * syntheticFrameLength + 2] = 0x00; // bitrate index 0
      }
      expect(await failureOf(free), AudioIdentityFailure.unsupportedLayout);

      final reserved = Uint8List.fromList(audio)..[2] = 0x9C; // rate index 3
      expect(await failureOf(reserved), AudioIdentityFailure.unsupportedLayout);
    });

    test('a read that fails is unreadable, not a match', () async {
      final result = await reader.read(_FailingSource());
      expect(result.failure, AudioIdentityFailure.unreadable);
    });

    test('a file that shrinks while it is hashed has no full hash', () async {
      final source = MemoryAudioByteSource(syntheticMp3(audio));
      final identity = (await reader.read(source)).identity!;
      final shorter = MemoryAudioByteSource(
        Uint8List.sublistView(source.bytes, 0, source.bytes.length - 1000),
      );
      expect(await reader.fullHash(shorter, identity.region), isNull);
    });
  });

  group('reads are bounded', () {
    test('the signature reads about 130 KiB of a 20 MB file', () async {
      final big = syntheticMp3(
        syntheticAudio(frames: 48000),
        leading: [id3v2Tag()],
        trailing: [id3v1Tag()],
      );
      final source = MemoryAudioByteSource(big);
      await reader.read(source);

      expect(big.length, greaterThan(20000000));
      expect(source.bytesRead, lessThan(2 * 64 * 1024 + 70 * 1024));
    });

    test('the full hash streams in chunks, never the whole file', () async {
      final big = syntheticMp3(syntheticAudio(frames: 24000));
      final source = MemoryAudioByteSource(big);
      const chunked = AudioIdentityReader(chunkSize: 256 * 1024);
      final identity = (await chunked.read(source)).identity!;
      source.readSizes.clear();

      await chunked.fullHash(source, identity.region);

      expect(source.largestRead, 256 * 1024);
      expect(source.bytesRead, identity.region.length);
    });
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
