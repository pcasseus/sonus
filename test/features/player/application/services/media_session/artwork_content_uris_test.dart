import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sonus_next/features/player/application/services/media_session/artwork_content_uris.dart';

void main() {
  final directory = p.join(p.separator, 'data', 'files', 'sonus', 'artwork');
  final existing = <String>{};

  ArtworkContentUris uris() => ArtworkContentUris(
    artworkDirectory: directory,
    fileExists: existing.contains,
  );

  setUp(existing.clear);

  test('managed artwork becomes a content URI', () {
    final file = p.join(directory, 'artwork_1a2b-c_3.jpg');
    existing.add(file);

    expect(
      uris().resolve(file).toString(),
      'content://com.sonus.sonus_next.artwork/artwork_1a2b-c_3.jpg',
    );
  });

  test('anything else gets no artwork', () {
    final elsewhere = p.join(p.separator, 'sdcard', 'Music', 'cover.jpg');
    final nested = p.join(directory, 'sub', 'artwork_a.jpg');
    final escaping = p.join(directory, '..', 'artwork_a.jpg');
    final oddName = p.join(directory, 'cover.jpg');
    final missing = p.join(directory, 'artwork_missing.jpg');
    existing.addAll([elsewhere, nested, escaping, oddName]);

    for (final path in [
      null,
      '',
      '   ',
      elsewhere,
      nested,
      escaping,
      oddName,
      missing,
    ]) {
      expect(uris().resolve(path), isNull, reason: '$path');
    }
  });
}
