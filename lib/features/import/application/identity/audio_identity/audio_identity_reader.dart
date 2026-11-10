import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../domain/services/audio_byte_source.dart';
import 'mp3_audio_region.dart';

/// The audio identity of one MP3 file (App Update 1.2, BUG-09).
class AudioIdentity {
  const AudioIdentity({
    required this.signature,
    required this.region,
    this.fullHash,
  });

  /// The rules that produce [signature] and [fullHash]. Bump when either
  /// changes, so stored values from older rules are not compared.
  static const int currentVersion = 1;

  /// `v1:<audio bytes>:<SHA-256 of the first and last 64 KiB of audio>`.
  /// Quick to read, and never sufficient alone to rebind a file.
  final String signature;

  /// SHA-256 of every audio byte; null until [AudioIdentityReader.fullHash]
  /// has read them.
  final String? fullHash;

  final Mp3AudioRegion region;

  int get version => currentVersion;

  AudioIdentity withFullHash(String hash) =>
      AudioIdentity(signature: signature, region: region, fullHash: hash);
}

/// Why no audio identity could be read.
enum AudioIdentityFailure {
  /// The file could not be opened or read.
  unreadable,

  /// The file's layout is not one the MP3 rules accept with confidence.
  unsupportedLayout,
}

/// An [AudioIdentity], or why there is none.
final class AudioIdentityResult {
  const AudioIdentityResult.read(AudioIdentity this.identity) : failure = null;

  const AudioIdentityResult.failed(AudioIdentityFailure this.failure)
    : identity = null;

  final AudioIdentity? identity;
  final AudioIdentityFailure? failure;
}

/// Reads audio identities with bounded memory.
///
/// - [read]: the tag-independent signature, from at most about 130 KiB.
/// - [fullHash]: SHA-256 of all audio bytes, streamed in [chunkSize]
///   pieces, so memory stays at one chunk whatever the file's size.
///
/// Tag editors rewrite only tags, so both stay the same when a file is
/// retagged, renamed, moved or rewritten, and change when the audio itself
/// does (a re-encode, a trim, a gain change).
class AudioIdentityReader {
  const AudioIdentityReader({this.chunkSize = defaultChunkSize});

  /// How much of each end of the audio the signature samples.
  static const int sampleSize = 64 * 1024;

  static const int defaultChunkSize = 1024 * 1024;

  final int chunkSize;

  Future<AudioIdentityResult> read(AudioByteSource source) async {
    final Mp3RegionResult located;
    try {
      located = await Mp3AudioRegionLocator.locate(source);
    } catch (error, stackTrace) {
      _log('locating the audio', error, stackTrace);
      return const AudioIdentityResult.failed(AudioIdentityFailure.unreadable);
    }
    final region = located.region;
    if (region == null) {
      return const AudioIdentityResult.failed(
        AudioIdentityFailure.unsupportedLayout,
      );
    }

    try {
      final digest = await _sampledDigest(source, region);
      return AudioIdentityResult.read(
        AudioIdentity(
          signature:
              'v${AudioIdentity.currentVersion}:${region.length}:$digest',
          region: region,
        ),
      );
    } catch (error, stackTrace) {
      _log('sampling the audio', error, stackTrace);
      return const AudioIdentityResult.failed(AudioIdentityFailure.unreadable);
    }
  }

  /// SHA-256 of every byte of [region]; null when the file cannot be read
  /// to the end (for example it changed or vanished meanwhile).
  Future<String?> fullHash(
    AudioByteSource source,
    Mp3AudioRegion region,
  ) async {
    try {
      final output = _DigestSink();
      final input = sha256.startChunkedConversion(output);
      var offset = region.start;
      while (offset < region.end) {
        final count = _min(chunkSize, region.end - offset);
        final bytes = await source.read(offset, count);
        if (bytes.length != count) return null;
        input.add(bytes);
        offset += count;
      }
      input.close();
      return output.value.toString();
    } catch (error, stackTrace) {
      _log('hashing the audio', error, stackTrace);
      return null;
    }
  }

  /// Logs the failure's type only: never the file's path or name.
  static void _log(String step, Object error, StackTrace stackTrace) =>
      developer.log(
        'Audio identity failed while $step (${error.runtimeType})',
        name: 'sonus.import.audio_identity',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );

  /// The whole audio when it is at most two samples long; otherwise its
  /// first and last [sampleSize] bytes.
  Future<String> _sampledDigest(
    AudioByteSource source,
    Mp3AudioRegion region,
  ) async {
    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);
    if (region.length <= 2 * sampleSize) {
      input.add(await _exactly(source, region.start, region.length));
    } else {
      input.add(await _exactly(source, region.start, sampleSize));
      input.add(await _exactly(source, region.end - sampleSize, sampleSize));
    }
    input.close();
    return output.value.toString();
  }

  static Future<Uint8List> _exactly(
    AudioByteSource source,
    int offset,
    int count,
  ) async {
    final bytes = await source.read(offset, count);
    if (bytes.length != count) {
      throw StateError('The file ended before its audio did.');
    }
    return bytes;
  }

  static int _min(int a, int b) => a < b ? a : b;
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
