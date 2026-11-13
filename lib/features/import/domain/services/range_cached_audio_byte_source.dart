import 'dart:typed_data';

import 'audio_byte_source.dart';

/// Serves the many small reads near a file's start and end from one read
/// of each (App Update 1.2, BUG-09 scan cost).
///
/// On the phone each read through the Storage Access Framework opens the
/// document again, so a tag fingerprint's eight or so small reads (header,
/// tag window, the end-of-file tags) cost far more than their bytes. The
/// bytes returned are exactly the source's; only the number of reads
/// changes. A read outside both windows goes to the source unchanged.
class RangeCachedAudioByteSource implements AudioByteSource {
  RangeCachedAudioByteSource(
    this._source, {
    int? knownLength,
    this.headBytes = 32 * 1024,
    this.tailBytes = 8 * 1024,
  }) : _length = knownLength;

  final AudioByteSource _source;
  final int headBytes;
  final int tailBytes;

  int? _length;
  Uint8List? _head;
  Uint8List? _tail;
  int _tailStart = 0;

  @override
  Future<int> length() async => _length ??= await _source.length();

  @override
  Future<DateTime?> modifiedAt() => _source.modifiedAt();

  @override
  Future<Uint8List> read(int offset, int count) async {
    final length = await this.length();
    final end = offset + count > length ? length : offset + count;
    if (offset < 0 || offset >= end) return Uint8List(0);

    if (end <= headBytes) {
      final head = _head ??= await _source.read(
        0,
        length < headBytes ? length : headBytes,
      );
      if (end <= head.length) return Uint8List.sublistView(head, offset, end);
    }

    final tailStart = length > tailBytes ? length - tailBytes : 0;
    if (offset >= tailStart) {
      if (_tail == null) {
        _tail = await _source.read(tailStart, length - tailStart);
        _tailStart = tailStart;
      }
      final tail = _tail!;
      final from = offset - _tailStart;
      final to = end - _tailStart;
      if (to <= tail.length) return Uint8List.sublistView(tail, from, to);
    }

    return _source.read(offset, end - offset);
  }

  @override
  Future<void> close() => _source.close();
}
