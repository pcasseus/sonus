// Roster portrait correction (device QA: Victorious Cast and FLO were cut
// off at both edges): artwork fills a frame only when that trims little;
// otherwise it is shown whole over a blurred copy of itself.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/widgets/sonus_framed_artwork.dart';

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// The Roster's featured frame on the Galaxy S26 Ultra (Option C).
const Size rosterFrame = Size(154, 260);

/// A solid PNG of the given size, for tests that need a real image.
Future<Uint8List> png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF8844CC),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  group('ArtworkFraming', () {
    void expectUndistorted(ArtworkFraming framing, double aspect) {
      expect(
        framing.size.width / framing.size.height,
        closeTo(aspect, 1e-9),
        reason: 'the image keeps its own shape',
      );
    }

    test('a square portrait in the tall Roster frame is shown whole', () {
      final framing = ArtworkFraming.of(imageAspect: 1, frame: rosterFrame);

      expect(framing.fills, isFalse);
      expect(framing.size, const Size(154, 154));
      expect(framing.trimmedPerSide(rosterFrame), 0);
      expectUndistorted(framing, 1);
    });

    test('a wide group photograph keeps everyone: shown whole, full width', () {
      for (final aspect in [16 / 9, 4 / 3, 3 / 1]) {
        final framing = ArtworkFraming.of(
          imageAspect: aspect,
          frame: rosterFrame,
        );
        expect(framing.fills, isFalse, reason: 'aspect $aspect');
        expect(framing.size.width, 154);
        expect(framing.trimmedPerSide(rosterFrame), 0);
        expectUndistorted(framing, aspect);
      }
    });

    test('an image close to the frame\'s shape fills it, trimming at most '
        '5% at each side', () {
      for (final aspect in [0.55, 0.592, 0.62, 0.65]) {
        final framing = ArtworkFraming.of(
          imageAspect: aspect,
          frame: rosterFrame,
        );
        expect(framing.fills, isTrue, reason: 'aspect $aspect');
        expect(framing.size.width, greaterThanOrEqualTo(154 - 1e-9));
        expect(framing.size.height, greaterThanOrEqualTo(260 - 1e-9));
        expect(framing.trimmedPerSide(rosterFrame), lessThanOrEqualTo(0.05));
        expectUndistorted(framing, aspect);
      }
    });

    test('subjects near the edges: no shape ever loses more than 5% at a '
        'side', () {
      for (var aspect = 0.2; aspect <= 4; aspect += 0.01) {
        for (final frame in [
          rosterFrame,
          const Size(110, 140),
          const Size(144, 219),
        ]) {
          final framing = ArtworkFraming.of(imageAspect: aspect, frame: frame);
          expect(
            framing.trimmedPerSide(frame),
            lessThanOrEqualTo(0.05 + 1e-9),
            reason: 'aspect $aspect in $frame',
          );
          expectUndistorted(framing, aspect);
        }
      }
    });

    test('a very tall image in a wide frame is shown whole, full height', () {
      const frame = Size(200, 100);
      final framing = ArtworkFraming.of(imageAspect: 0.5, frame: frame);

      expect(framing.fills, isFalse);
      expect(framing.size, const Size(50, 100));
    });

    test('an unusable shape or frame falls back to the frame itself', () {
      expect(
        ArtworkFraming.of(imageAspect: 0, frame: rosterFrame).size,
        rosterFrame,
      );
      expect(
        ArtworkFraming.of(imageAspect: double.nan, frame: rosterFrame).size,
        rosterFrame,
      );
    });
  });

  group('SonusFramedArtwork', () {
    Future<void> pumpFramed(
      WidgetTester tester,
      ImageProvider image, {
      Size frame = rosterFrame,
      double textScale = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Center(
              child: SizedBox.fromSize(
                size: frame,
                child: SonusFramedArtwork(
                  key: const ValueKey<String>('framed'),
                  image: image,
                  fill: const Color(0xFF101018),
                  fallback: const Text('initials'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(image, tester.element(byKey('framed'))),
      );
      await tester.pump();
      await tester.pump();
    }

    Rect pictureRect(WidgetTester tester) => tester.getRect(
      find.descendant(
        of: byKey(
          byKey('framed-artwork-whole').evaluate().isEmpty
              ? 'framed-artwork-filled'
              : 'framed-artwork-whole',
        ),
        matching: find.byType(Image),
      ),
    );

    testWidgets('a wide group photo is shown whole over a blur of itself', (
      tester,
    ) async {
      final bytes = (await tester.runAsync(() => png(320, 180)))!;
      await pumpFramed(tester, MemoryImage(bytes));

      expect(byKey('framed-artwork-whole'), findsOneWidget);
      expect(byKey('framed-artwork-backdrop'), findsOneWidget);
      final frame = tester.getRect(byKey('framed'));
      final picture = pictureRect(tester);
      expect(picture.width, closeTo(154, 0.01), reason: 'full width');
      expect(picture.height, closeTo(154 * 180 / 320, 0.01));
      expect(picture.center.dy, closeTo(frame.center.dy, 0.01));
      expect(frame.contains(picture.topLeft), isTrue, reason: 'not cropped');
      expect(
        frame.contains(picture.bottomRight - const Offset(1e-3, 1e-3)),
        isTrue,
      );
    });

    testWidgets('a square portrait is shown whole in the tall frame', (
      tester,
    ) async {
      final bytes = (await tester.runAsync(() => png(200, 200)))!;
      await pumpFramed(tester, MemoryImage(bytes));

      expect(byKey('framed-artwork-whole'), findsOneWidget);
      expect(pictureRect(tester).size, const Size(154, 154));
    });

    testWidgets('a portrait close to the frame\'s shape fills it, with no '
        'blur', (tester) async {
      final bytes = (await tester.runAsync(() => png(160, 260)))!;
      await pumpFramed(tester, MemoryImage(bytes));

      expect(byKey('framed-artwork-filled'), findsOneWidget);
      expect(byKey('framed-artwork-backdrop'), findsNothing);
      final picture = pictureRect(tester);
      expect(picture.height, closeTo(260, 0.01));
      expect(picture.width, closeTo(160, 0.01));
    });

    testWidgets('artwork that cannot be loaded shows the fallback', (
      tester,
    ) async {
      final broken = MemoryImage(Uint8List.fromList([1, 2, 3, 4]));
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.fromSize(
              size: rosterFrame,
              child: SonusFramedArtwork(
                key: const ValueKey<String>('framed'),
                image: broken,
                fill: const Color(0xFF101018),
                fallback: const Text('initials'),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          broken,
          tester.element(byKey('framed')),
          onError: (error, stackTrace) {},
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.text('initials'), findsOneWidget);
    });

    testWidgets('the small scrolling-layout frame and large text: a wide '
        'photo still fits whole', (tester) async {
      final bytes = (await tester.runAsync(() => png(400, 225)))!;
      await pumpFramed(
        tester,
        MemoryImage(bytes),
        frame: const Size(110, 140),
        textScale: 2,
      );

      expect(byKey('framed-artwork-whole'), findsOneWidget);
      expect(pictureRect(tester).width, closeTo(110, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the same decoded image serves the picture and the blur', (
      tester,
    ) async {
      final bytes = (await tester.runAsync(() => png(320, 180)))!;
      final image = MemoryImage(bytes);
      await pumpFramed(tester, image);

      final images = tester.widgetList<Image>(
        find.descendant(of: byKey('framed'), matching: find.byType(Image)),
      );
      expect(images, hasLength(2));
      expect(images.every((widget) => identical(widget.image, image)), isTrue);
    });
  });
}
