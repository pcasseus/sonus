import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_text_scale.dart';
import 'package:sonus_next/core/design/widgets/sonus_track_tile.dart';

// Register R21: one large-text threshold. Rows keep their normal layout at
// exactly 1.3 (Android's "Large" step) and switch just above it.
void main() {
  Future<void> pump(WidgetTester tester, double scale) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const Scaffold(
            body: SonusTrackTile(
              title: 'Song',
              leadingNumber: '7',
              showArtwork: false,
            ),
          ),
        ),
      ),
    );
  }

  test('the threshold is 1.3', () {
    expect(sonusLargeTextScale, 1.3);
  });

  testWidgets('at exactly 1.3 the row keeps its normal layout', (tester) async {
    await pump(tester, sonusLargeTextScale);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('just above 1.3 the row switches to large text', (tester) async {
    await pump(tester, sonusLargeTextScale + 0.01);
    expect(find.text('7'), findsNothing);
  });
}
