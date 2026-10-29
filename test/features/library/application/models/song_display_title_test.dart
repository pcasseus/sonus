import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/song_display_title.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  group('songDisplayTitle (SN-50 C-Q6/C-Q22)', () {
    test('a title without version metadata is unchanged', () {
      expect(songDisplayTitle(title: 'Paper Boats'), 'Paper Boats');
    });

    test('appends the stored version label', () {
      expect(
        songDisplayTitle(title: 'Paper Boats', versionLabel: 'Live'),
        'Paper Boats (Live)',
      );
    });

    test('reveals a qualifier the importer stripped, from characteristics', () {
      expect(
        songDisplayTitle(
          title: 'Paper Boats',
          characteristics: const [SongVersionCharacteristic.live],
        ),
        'Paper Boats (Live)',
      );
    });

    test('joins characteristics with describing words first', () {
      expect(
        songDisplayTitle(
          title: 'Paper Boats',
          characteristics: const [
            SongVersionCharacteristic.remix,
            SongVersionCharacteristic.acoustic,
          ],
        ),
        'Paper Boats (Acoustic Remix)',
      );
    });

    test('a label wins over characteristics', () {
      expect(
        songDisplayTitle(
          title: 'Paper Boats',
          versionLabel: 'Live at the Harbour',
          characteristics: const [SongVersionCharacteristic.live],
        ),
        'Paper Boats (Live at the Harbour)',
      );
    });

    test('Radio Edit does not also add Edit', () {
      expect(
        songDisplayTitle(
          title: 'Paper Boats',
          characteristics: const [
            SongVersionCharacteristic.edit,
            SongVersionCharacteristic.radioEdit,
          ],
        ),
        'Paper Boats (Radio Edit)',
      );
    });

    test('never repeats a qualifier the title already has', () {
      expect(
        songDisplayTitle(title: 'Paper Boats (LIVE)', versionLabel: 'live'),
        'Paper Boats (LIVE)',
      );
      expect(
        songDisplayTitle(
          title: 'Paper Boats (Live at the Harbour)',
          characteristics: const [SongVersionCharacteristic.live],
        ),
        'Paper Boats (Live at the Harbour)',
      );
      expect(
        songDisplayTitle(
          title: 'Paper Boats - Radio Edit',
          versionLabel: 'Radio Edit',
        ),
        'Paper Boats - Radio Edit',
      );
    });

    test('adds only the characteristics the title lacks', () {
      expect(
        songDisplayTitle(
          title: 'Paper Boats [Remix]',
          characteristics: const [
            SongVersionCharacteristic.remix,
            SongVersionCharacteristic.acoustic,
          ],
        ),
        'Paper Boats [Remix] (Acoustic)',
      );
    });

    test('a qualifier word in the plain title still gets the suffix', () {
      expect(
        songDisplayTitle(title: 'Live Forever', versionLabel: 'Live'),
        'Live Forever (Live)',
      );
      expect(
        songDisplayTitle(title: 'Alive (Demo)', versionLabel: 'Live'),
        'Alive (Demo) (Live)',
      );
    });

    test('a blank label falls back to characteristics', () {
      expect(
        songDisplayTitle(
          title: 'Paper Boats',
          versionLabel: '  ',
          characteristics: const [SongVersionCharacteristic.demo],
        ),
        'Paper Boats (Demo)',
      );
    });
  });
}
