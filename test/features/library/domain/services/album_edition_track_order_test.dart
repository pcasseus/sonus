import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/domain/services/album_edition_track_order.dart';

void main() {
  // SN-50 A-Q8A: one rule for Release Studio and the Album page.
  group('spansMultipleDiscs', () {
    test('needs more than one distinct disc', () {
      expect(spansMultipleDiscs(const []), isFalse);
      expect(spansMultipleDiscs(const [1, 1, 1]), isFalse);
      expect(spansMultipleDiscs(const [1, 2]), isTrue);
    });

    test('an edition entirely on another disc is still one disc', () {
      expect(spansMultipleDiscs(const [2, 2]), isFalse);
    });

    test('an unknown disc counts as disc 1', () {
      expect(spansMultipleDiscs(const [0, 1]), isFalse);
      expect(spansMultipleDiscs(const [0, 2]), isTrue);
    });
  });
}
