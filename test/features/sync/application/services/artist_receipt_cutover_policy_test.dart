import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/application/services/artist_receipt_cutover_policy.dart';

void main() {
  test('receipt-aware production cutover remains disabled', () {
    expect(ArtistReceiptCutoverPolicy.enabled, isFalse);
  });
}
