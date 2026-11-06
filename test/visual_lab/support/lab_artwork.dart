// Generated artwork for the Artist Profile Lab.
//
// The repository is public: no real cover or artist photo is ever used
// here. Every picture is drawn from a formula (photo-like banners with a
// figure, window light and bokeh; abstract covers) and written by the PNG
// encoder of the protected baselines.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../visual_baselines/support/generated_artwork.dart';

/// The artwork families the lab is rendered with.
enum LabVariant {
  cool('Cool'),
  warm('Warm'),
  neutral('Neutral'),
  bright('Near-white');

  const LabVariant(this.label);
  final String label;
}

typedef _Rgb = (double, double, double);

class _Family {
  const _Family(this.dark, this.light, this.figure, this.hair);
  final _Rgb dark;
  final _Rgb light;
  final _Rgb figure;
  final _Rgb hair;
}

const Map<LabVariant, _Family> _families = {
  LabVariant.cool: _Family(
    (0.05, 0.12, 0.30),
    (0.55, 0.78, 0.95),
    (0.86, 0.72, 0.64),
    (0.07, 0.06, 0.08),
  ),
  LabVariant.warm: _Family(
    (0.30, 0.09, 0.05),
    (0.98, 0.72, 0.46),
    (0.80, 0.58, 0.46),
    (0.16, 0.08, 0.05),
  ),
  // Greys only: artwork with no colour worth following.
  LabVariant.neutral: _Family(
    (0.16, 0.16, 0.17),
    (0.74, 0.74, 0.73),
    (0.62, 0.62, 0.61),
    (0.08, 0.08, 0.08),
  ),
  // A pale, almost white studio photo.
  LabVariant.bright: _Family(
    (0.80, 0.80, 0.82),
    (0.98, 0.97, 0.95),
    (0.90, 0.86, 0.82),
    (0.42, 0.40, 0.40),
  ),
};

/// Every lab picture, written once per test isolate.
class LabArtworkFiles {
  LabArtworkFiles._(this._paths);

  static LabArtworkFiles? _instance;

  static LabArtworkFiles ensure() {
    final existing = _instance;
    if (existing != null) return existing;
    final dir = Directory.systemTemp.createTempSync('sonus_profile_lab_art');
    final paths = <String, String>{};
    void write(String name, Uint8List bytes) {
      final file = File('${dir.path}${Platform.pathSeparator}$name.png')
        ..writeAsBytesSync(bytes, flush: true);
      paths[name] = file.path;
    }

    for (final v in LabVariant.values) {
      write('banner_${v.name}', _banner(v, 360, 240));
      write('portrait_${v.name}', _banner(v, 200, 200, portrait: true));
    }
    write('cover_cool', encodeArtwork(BaselineArtwork.coolCover));
    write('cover_warm', encodeArtwork(BaselineArtwork.warmCover));
    write('cover_neutral', encodeArtwork(BaselineArtwork.neutralCover));
    for (final (i, hue) in const [(0, 275.0), (1, 175.0), (2, 335.0)]) {
      write('cover_hue_$i', _abstractCover(hue, i));
    }
    write('partner_0', encodeArtwork(BaselineArtwork.warmPortrait));
    write('partner_1', encodeArtwork(BaselineArtwork.coolPortrait));
    write('partner_2', encodeArtwork(BaselineArtwork.neutralPortrait));
    return _instance = LabArtworkFiles._(paths);
  }

  final Map<String, String> _paths;

  String banner(LabVariant v) => _paths['banner_${v.name}']!;
  String portrait(LabVariant v) => _paths['portrait_${v.name}']!;
  String cover(String name) => _paths['cover_$name']!;
  String partner(int i) => _paths['partner_$i']!;

  List<String> get all => _paths.values.toList(growable: false);
}

_Rgb _mix(_Rgb a, _Rgb b, double t) => (
  a.$1 + (b.$1 - a.$1) * t,
  a.$2 + (b.$2 - a.$2) * t,
  a.$3 + (b.$3 - a.$3) * t,
);

double _smooth(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

int _byte(double v) => (v.clamp(0.0, 1.0) * 255).round();

/// A photo-like picture: a lit backdrop with window-light bands and bokeh,
/// and a head-and-shoulders figure with dark hair, slightly right of
/// centre (or centred, as a portrait).
Uint8List _banner(LabVariant v, int w, int h, {bool portrait = false}) {
  final f = _families[v]!;
  final rgb = Uint8List(w * h * 3);
  final aspect = w / h;
  final cx = portrait ? 0.5 : 0.56;
  for (var py = 0; py < h; py++) {
    for (var px = 0; px < w; px++) {
      final x = px / (w - 1), y = py / (h - 1);
      // Ground: light from the upper left.
      var c = _mix(
        f.light,
        f.dark,
        _smooth(0.0, 1.2, (1 - x) * 0.3 + y * 0.9 + x * 0.25),
      );
      // Window light: soft horizontal bands in the upper half.
      final band = 0.5 + 0.5 * math.sin(y * math.pi * 9 + 0.6);
      c = _mix(c, f.light, band * 0.22 * (1 - _smooth(0.2, 0.6, y)));
      // Bokeh: a few soft bright discs.
      for (final (bx, by, r) in const [
        (0.12, 0.22, 0.07),
        (0.85, 0.15, 0.05),
        (0.92, 0.62, 0.08),
        (0.06, 0.70, 0.05),
      ]) {
        final d = math.sqrt(
          math.pow((x - bx) * aspect, 2) + math.pow(y - by, 2),
        );
        c = _mix(c, f.light, (1 - _smooth(r * 0.6, r, d)) * 0.35);
      }
      // Figure: hair behind, then face and shoulders.
      final dx = (x - cx) * aspect;
      final head = math.sqrt(dx * dx + math.pow((y - 0.42) * 0.85, 2));
      final hair = math.sqrt(dx * dx * 0.8 + math.pow((y - 0.47) * 0.62, 2));
      final shoulders = math.sqrt(
        math.pow(dx * 0.62, 2) + math.pow(y - 1.12, 2),
      );
      final hairMask = 1 - _smooth(0.22, 0.25, hair);
      c = _mix(c, f.hair, hairMask * _smooth(0.05, 0.4, y + 0.2));
      final skin = math.max(
        1 - _smooth(0.15, 0.165, head),
        1 - _smooth(0.40, 0.42, shoulders),
      );
      final lit = _mix(f.figure, f.dark, _smooth(0.3, 1.1, y + dx * 0.6));
      c = _mix(c, lit, skin);
      final i = (py * w + px) * 3;
      rgb[i] = _byte(c.$1);
      rgb[i + 1] = _byte(c.$2);
      rgb[i + 2] = _byte(c.$3);
    }
  }
  return encodePngRgb(w, h, rgb);
}

_Rgb _hsl(double hue, double s, double l) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final hp = (hue % 360) / 60;
  final x = c * (1 - (hp % 2 - 1).abs());
  final (r, g, b) = switch (hp.floor()) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  final m = l - c / 2;
  return (r + m, g + m, b + m);
}

/// An abstract cover: a two-tone diagonal field with a soft orb.
Uint8List _abstractCover(double hue, int seed) {
  const size = 200;
  final rgb = Uint8List(size * size * 3);
  final a = _hsl(hue, 0.55, 0.22), b = _hsl(hue + 30, 0.65, 0.62);
  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      final x = px / (size - 1), y = py / (size - 1);
      var c = _mix(a, b, _smooth(0.1, 0.95, x * 0.5 + (1 - y) * 0.5));
      final d = math.sqrt(
        math.pow(x - (0.3 + seed * 0.2), 2) + math.pow(y - 0.4, 2),
      );
      c = _mix(c, (1.0, 0.96, 0.9), (1 - _smooth(0.1, 0.22, d)) * 0.7);
      final i = (py * size + px) * 3;
      rgb[i] = _byte(c.$1);
      rgb[i + 1] = _byte(c.$2);
      rgb[i + 2] = _byte(c.$3);
    }
  }
  return encodePngRgb(size, size, rgb);
}
