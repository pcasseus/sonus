// Screenshot boards for the Artist Profile Lab: captures laid out in a
// labelled grid and written as PNG, outside the repository.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/device_layout.dart';

/// One picture on a board.
class BoardCell {
  BoardCell(this.caption, this.image, {this.source});

  final String caption;
  final ui.Image image;

  /// Part of [image] to draw (the whole image when null).
  final Rect? source;
}

/// Lays [rows] out (each cell scaled to [cellHeight] tall) under [title]
/// and writes the PNG to [path].
Future<void> writeBoard(
  WidgetTester tester,
  String path,
  String title,
  List<List<BoardCell>> rows, {
  double cellHeight = 1040,
}) async {
  const margin = 28.0, gap = 22.0, captionHeight = 44.0, titleHeight = 64.0;
  double widthOf(BoardCell c) {
    final src =
        c.source ??
        Rect.fromLTWH(
          0,
          0,
          c.image.width.toDouble(),
          c.image.height.toDouble(),
        );
    return src.width * cellHeight / src.height;
  }

  final rowWidths = [
    for (final row in rows)
      row.fold<double>(0, (w, c) => w + widthOf(c)) + gap * (row.length - 1),
  ];
  final width = margin * 2 + rowWidths.reduce((a, b) => a > b ? a : b);
  final height =
      margin * 2 +
      titleHeight +
      rows.length * (cellHeight + captionHeight + gap);

  ui.Paragraph text(String s, double size, Color colour, double maxWidth) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(fontFamily: realRobotoFamily, fontSize: size),
          )
          ..pushStyle(
            ui.TextStyle(
              color: colour,
              fontFamily: realRobotoFamily,
              fontSize: size,
            ),
          )
          ..addText(s);
    return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
  }

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    ui.Paint()..color = const Color(0xFF15171B),
  );
  canvas.drawParagraph(
    text(title, 30, const Color(0xFFF2F4F7), width - margin * 2),
    const Offset(margin, margin),
  );
  var y = margin + titleHeight;
  for (final row in rows) {
    var x = margin;
    for (final cell in row) {
      final w = widthOf(cell);
      canvas.drawParagraph(
        text(cell.caption, 22, const Color(0xFFB8BEC8), w),
        Offset(x, y + 6),
      );
      final src =
          cell.source ??
          Rect.fromLTWH(
            0,
            0,
            cell.image.width.toDouble(),
            cell.image.height.toDouble(),
          );
      canvas.drawImageRect(
        cell.image,
        src,
        Rect.fromLTWH(x, y + captionHeight, w, cellHeight),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      x += w + gap;
    }
    y += captionHeight + cellHeight + gap;
  }
  final picture = recorder.endRecording();
  await tester.runAsync(() async {
    final image = await picture.toImage(width.ceil(), height.ceil());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
  });
}

/// Decodes a PNG or JPEG file outside the fake async zone.
Future<ui.Image?> loadImageFile(WidgetTester tester, String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  return tester.runAsync(() async {
    final bytes = Uint8List.fromList(file.readAsBytesSync());
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  });
}
