import 'package:archive/archive_io.dart';

/// Limits decompressed output before allowing each write.
class BoundedBackupOutputStream extends OutputMemoryStream {
  BoundedBackupOutputStream({required this.maxBytes}) : assert(maxBytes >= 0);

  final int maxBytes;

  void _check(int additionalBytes) {
    if (additionalBytes < 0 ||
        length > maxBytes ||
        additionalBytes > maxBytes - length) {
      throw const FormatException(
        'Decompressed backup entry exceeds its byte limit.',
      );
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }

  @override
  void writeStream(InputStream stream) {
    const chunkSize = 64 * 1024;

    while (!stream.isEOS) {
      final bytes = stream.readBytes(chunkSize).toUint8List();

      if (bytes.isEmpty) {
        throw const FormatException('Backup input stream ended unexpectedly.');
      }

      writeBytes(bytes);
    }
  }
}
