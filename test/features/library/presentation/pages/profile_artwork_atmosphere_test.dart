// Profile redesign: the Artist and Album Profiles paint the artwork's own
// colour. Checked on the pixels actually painted (not only the resolver):
// real page widgets, real palette extraction, a cool and a warm cover. The
// colour stays after scrolling, and menus opened from the page are tinted.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';

import '../../../../support/device_layout.dart';
import 'album_profile_page_test.dart' as album;
import 'artist_profile_page_test.dart' as artist;

/// A cover with two related tones, like real artwork (a flat square gives
/// the palette nothing to choose between).
Future<String> paintCover(String name, Color main, Color second) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 128, 128), Paint()..color = main);
  canvas.drawCircle(const Offset(80, 50), 36, Paint()..color = second);
  canvas.drawRect(
    const Rect.fromLTWH(0, 96, 128, 32),
    Paint()..color = Color.lerp(main, Colors.black, 0.4)!,
  );
  final image = await recorder.endRecording().toImage(128, 128);
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  final dir = await Directory.systemTemp.createTemp('sonus_profile_art');
  final file = File('${dir.path}/$name.png');
  await file.writeAsBytes(png.buffer.asUint8List());
  return file.path;
}

const coolMain = Color(0xFF3F7CB8);
const coolSecond = Color(0xFF8CC4EA);
const warmMain = Color(0xFFD0662A);
const warmSecond = Color(0xFFF2B07A);

HSLColor hsl(Color c) => HSLColor.fromColor(c);

Future<List<Color>> sample(WidgetTester tester, List<Offset> points) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('probe-root')),
  );
  final colours = <Color>[];
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (final p in points) {
      final i = ((p.dy.round() * image.width) + p.dx.round()) * 4;
      colours.add(
        Color.fromARGB(
          255,
          data.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        ),
      );
    }
  });
  return colours;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }
}

ThemeData theme() =>
    withRealRoboto(SonusThemeFactory.build(const SonusAppearanceSpec()));

/// Page edge samples, clear of text and artwork.
const edgePoints = [Offset(4, 300), Offset(4, 520), Offset(4, 760)];

void expectHue(List<Color> painted, {required bool cool, required String at}) {
  for (final colour in painted) {
    final h = hsl(colour);
    expect(h.saturation, greaterThan(0.25), reason: '$at saturation $colour');
    if (cool) {
      expect(h.hue, inInclusiveRange(185, 235), reason: '$at hue $colour');
    } else {
      expect(h.hue, inInclusiveRange(5, 45), reason: '$at hue $colour');
    }
  }
}

void main() {
  setUpAll(loadRealRoboto);

  for (final (name, cool, main, second) in [
    ('cool', true, coolMain, coolSecond),
    ('warm', false, warmMain, warmSecond),
  ]) {
    testWidgets('Artist Profile paints the $name artwork\'s colour, top to '
        'bottom and after scrolling, and its menu is tinted', (tester) async {
      setDevice(tester);
      late String path;
      await tester.runAsync(() async {
        path = await paintCover('artist_$name', main, second);
        await SonusArtworkPalette.shared.colorsFor(
          path,
          brightness: Brightness.dark,
        );
      });

      final repo = artist.FakeLibraryQueryRepository(
        artist: artist.createArtist(
          name: 'Probe Artist',
          headerArtworkPath: path,
        ),
        albums: [artist.createAlbum()],
        tracks: [
          for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'])
            artist.createTrack(songId: id, title: 'Song $id'),
        ],
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('probe-root'),
          child: artist.buildSubject(
            repository: repo,
            theme: theme(),
            // Editing offers the artwork menu.
            artistProfileEditingService:
                artist.FakeArtistProfileEditingService(),
            home: const ArtistProfilePage(
              artistId: 'artist-1',
              initialArtistName: 'Probe Artist',
            ),
          ),
        ),
      );
      await settle(tester);

      expectHue(await sample(tester, edgePoints), cool: cool, at: 'top');

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await settle(tester);
      expectHue(await sample(tester, edgePoints), cool: cool, at: 'scrolled');

      // A menu opened from the page takes the page's colours, not the
      // theme's charcoal.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1600));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('artist-profile-artwork-menu')),
      );
      await settle(tester);
      final menu = tester
          .widgetList<Material>(
            find.ancestor(
              of: find
                  .byWidgetPredicate((widget) => widget is PopupMenuItem)
                  .first,
              matching: find.byType(Material),
            ),
          )
          .map((m) => m.color)
          .whereType<Color>()
          .first;
      final themeSurface = theme().extension<SonusColors>()!.raisedSurface;
      expect(menu, isNot(themeSurface));
      final menuHue = hsl(menu).hue;
      expect(
        cool ? menuHue > 185 && menuHue < 235 : menuHue > 5 && menuHue < 45,
        isTrue,
        reason: 'menu $menu',
      );
    });

    testWidgets('Album Profile paints the $name edition cover\'s colour, '
        'also after scrolling', (tester) async {
      setDevice(tester);
      late String path;
      await tester.runAsync(() async {
        path = await paintCover('album_$name', main, second);
        await SonusArtworkPalette.shared.colorsFor(
          path,
          brightness: Brightness.dark,
        );
      });

      final repo = album.FakeEditionAwareLibraryQueryRepository(
        album: album.createAlbum(
          title: 'Probe Album',
          primaryEditionId: 'e-std',
          primaryEditionTitle: 'Standard',
        ),
        editions: [
          album.createLibraryEdition(
            editionId: 'e-std',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
            artworkPath: path,
          ),
        ],
        editionTracks: {
          'e-std': [
            for (var i = 1; i <= 14; i++)
              album.createTrack(
                songId: 's$i',
                title: 'Track $i',
                trackNumber: i,
                albumEditionId: 'e-std',
              ),
          ],
        },
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('probe-root'),
          child: album.buildSubject(repository: repo, theme: theme()),
        ),
      );
      await settle(tester);

      expectHue(
        await sample(tester, const [Offset(4, 520), Offset(4, 760)]),
        cool: cool,
        at: 'top',
      );

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
      await settle(tester);
      expectHue(await sample(tester, edgePoints), cool: cool, at: 'scrolled');
    });
  }
}
