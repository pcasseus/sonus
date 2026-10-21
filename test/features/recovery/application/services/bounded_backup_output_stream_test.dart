import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/recovery/application/services/bounded_backup_output_stream.dart';

void main() {
  test('accepts output at the exact byte limit', () {
    final output = BoundedBackupOutputStream(maxBytes: 4);

    output.writeBytes([1, 2, 3]);
    output.writeByte(4);

    expect(output.length, 4);
    expect(output.getBytes(), [1, 2, 3, 4]);
  });

  test('rejects output exceeding the byte limit', () {
    final output = BoundedBackupOutputStream(maxBytes: 3);

    output.writeBytes([1, 2]);

    expect(() => output.writeBytes([3, 4]), throwsFormatException);

    expect(output.getBytes(), [1, 2]);
  });

  test('rejects back-reference expansion beyond the limit', () {
    final output = BoundedBackupOutputStream(maxBytes: 3);

    output.writeByte(65);

    expect(() => output.writeBackReference(1, 3), throwsFormatException);
  });

  test('rejects an oversized input stream', () {
    final output = BoundedBackupOutputStream(maxBytes: 2);
    final source = InputMemoryStream([1, 2, 3]);

    expect(() => output.writeStream(source), throwsFormatException);
  });
}
