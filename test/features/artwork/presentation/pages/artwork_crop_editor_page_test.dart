import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_crop.dart';
import 'package:sonus_next/features/artwork/presentation/pages/artwork_crop_editor_page.dart';

Future<Uint8List> pngOf(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  late Uint8List landscape;

  setUpAll(() async {
    landscape = await pngOf(800, 400);
  });

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  /// Opens the editor from a button and returns the decision once popped.
  Future<ArtworkCropDecision? Function()> open(
    WidgetTester tester, {
    ArtworkCropTarget target = ArtworkCropTarget.albumEdition,
    CropRect? initialRect,
    bool canReset = false,
    Size size = const Size(411, 900),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    ArtworkCropDecision? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ArtworkCropDecision>(
                MaterialPageRoute(
                  builder: (_) => ArtworkCropEditorPage(
                    imagePath: 'unused.png',
                    target: target,
                    initialRect: initialRect,
                    canReset: canReset,
                    previewName: 'Madison Beer',
                    imageProvider: MemoryImage(landscape),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Let the real image decode.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump();
    return () => result;
  }

  testWidgets('saving a cover returns a centered square crop', (tester) async {
    final result = await open(tester);

    expect(key('artwork-crop-viewport'), findsOneWidget);
    await tester.tap(key('artwork-crop-save'));
    await tester.pumpAndSettle();

    final saved = result() as ArtworkCropSave;
    // An 800x400 image: the square uses the full height, centered.
    expect(saved.rect, CropRect(left: 0.25, top: 0, width: 0.5, height: 1));
  });

  testWidgets('dragging moves the crop and the edge is respected', (
    tester,
  ) async {
    final result = await open(tester);

    await tester.drag(key('artwork-crop-viewport'), const Offset(5000, 0));
    await tester.pump();
    await tester.tap(key('artwork-crop-save'));
    await tester.pumpAndSettle();

    final saved = result() as ArtworkCropSave;
    expect(saved.rect.left, 0);
  });

  testWidgets('the zoom slider and nudges are alternatives to gestures', (
    tester,
  ) async {
    final result = await open(tester);

    final slider = tester.widget<Slider>(key('artwork-crop-zoom'));
    slider.onChanged!(2);
    await tester.pump();
    await tester.tap(key('artwork-crop-right'));
    await tester.pump();
    await tester.tap(key('artwork-crop-save'));
    await tester.pumpAndSettle();

    final saved = result() as ArtworkCropSave;
    expect(saved.rect.width, closeTo(0.25, 1e-9));
    // "Move image right" shows more of the left: the crop moved left.
    expect(saved.rect.left + saved.rect.width / 2, lessThan(0.5));
  });

  testWidgets('a banner is wide and previews the name and fade', (
    tester,
  ) async {
    final result = await open(tester, target: ArtworkCropTarget.artistBanner);

    expect(find.text('Madison Beer'), findsOneWidget);
    await tester.tap(key('artwork-crop-save'));
    await tester.pumpAndSettle();

    final rect = (result() as ArtworkCropSave).rect;
    expect((rect.width * 800) / (rect.height * 400), closeTo(4 / 3, 1e-6));
  });

  testWidgets('reset is offered only when re-cropping', (tester) async {
    await open(tester);
    expect(key('artwork-crop-reset'), findsNothing);
  });

  testWidgets('re-cropping opens at the saved crop and can reset', (
    tester,
  ) async {
    final saved = CropRect(left: 0, top: 0, width: 0.5, height: 1);
    final result = await open(tester, initialRect: saved, canReset: true);

    await tester.tap(key('artwork-crop-save'));
    await tester.pumpAndSettle();
    expect((result() as ArtworkCropSave).rect, saved);

    final again = await open(tester, initialRect: saved, canReset: true);
    await tester.ensureVisible(key('artwork-crop-reset'));
    await tester.tap(key('artwork-crop-reset'));
    await tester.pumpAndSettle();
    expect(again(), isA<ArtworkCropReset>());
  });

  testWidgets('fits 320dp at 2x text', (tester) async {
    await open(
      tester,
      target: ArtworkCropTarget.artistPortrait,
      size: const Size(320, 700),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(key('artwork-crop-save'), findsOneWidget);
  });
}
