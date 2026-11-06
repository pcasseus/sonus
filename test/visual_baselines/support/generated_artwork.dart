// Generated fixture artwork for the protected visual baselines.
//
// The GitHub repository is public, so real covers and artist photos are
// never used here. Every picture is drawn from a formula and encoded by the
// small PNG writer below, so the bytes are identical on every run and on
// every machine (no engine rasterisation is involved).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// The kinds of generated picture: three colour families (cool, warm,
/// neutral), each as an album-style cover and as an artist-style portrait.
enum BaselineArtwork {
  coolCover,
  warmCover,
  neutralCover,
  coolPortrait,
  warmPortrait,
  neutralPortrait,
}

/// Writes every [BaselineArtwork] as a PNG into one temporary folder, once
/// per test isolate, and returns their paths.
class BaselineArtworkFiles {
  BaselineArtworkFiles._(this.directory, this._paths);

  static BaselineArtworkFiles? _instance;

  /// The files, created on first use.
  static BaselineArtworkFiles ensure() {
    final existing = _instance;
    if (existing != null) return existing;
    final directory = Directory.systemTemp.createTempSync('sonus_baseline_art');
    final paths = <BaselineArtwork, String>{};
    for (final art in BaselineArtwork.values) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}${art.name}.png',
      );
      file.writeAsBytesSync(encodeArtwork(art), flush: true);
      paths[art] = file.path;
    }
    return _instance = BaselineArtworkFiles._(directory, paths);
  }

  final Directory directory;
  final Map<BaselineArtwork, String> _paths;

  String path(BaselineArtwork art) => _paths[art]!;

  List<String> get allPaths => _paths.values.toList(growable: false);

  /// A cover and a portrait in turn, cycling through the colour families,
  /// with every fifth slot left without artwork (initials or placeholders).
  String? coverFor(int index) => index % 5 == 4
      ? null
      : path(
          const [
            BaselineArtwork.coolCover,
            BaselineArtwork.warmCover,
            BaselineArtwork.neutralCover,
          ][index % 3],
        );

  String? portraitFor(int index) => index % 5 == 4
      ? null
      : path(
          const [
            BaselineArtwork.coolPortrait,
            BaselineArtwork.warmPortrait,
            BaselineArtwork.neutralPortrait,
          ][index % 3],
        );
}

const int _size = 256;

/// The PNG bytes of [art] (256 x 256, RGB).
Uint8List encodeArtwork(BaselineArtwork art) {
  final rgb = Uint8List(_size * _size * 3);
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      final (r, g, b) = _pixel(art, x / (_size - 1), y / (_size - 1));
      final i = (y * _size + x) * 3;
      rgb[i] = _byte(r);
      rgb[i + 1] = _byte(g);
      rgb[i + 2] = _byte(b);
    }
  }
  return encodePngRgb(_size, _size, rgb);
}

int _byte(double v) => (v.clamp(0.0, 1.0) * 255).round();

typedef _Rgb = (double, double, double);

_Rgb _mix(_Rgb a, _Rgb b, double t) => (
  a.$1 + (b.$1 - a.$1) * t,
  a.$2 + (b.$2 - a.$2) * t,
  a.$3 + (b.$3 - a.$3) * t,
);

double _smooth(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

const _Rgb _coolA = (0.05, 0.12, 0.38);
const _Rgb _coolB = (0.25, 0.70, 0.95);
const _Rgb _warmA = (0.45, 0.08, 0.06);
const _Rgb _warmB = (0.98, 0.62, 0.22);
const _Rgb _neutralA = (0.20, 0.23, 0.28);
const _Rgb _neutralB = (0.80, 0.76, 0.68);

(_Rgb, _Rgb) _family(BaselineArtwork art) => switch (art) {
  BaselineArtwork.coolCover || BaselineArtwork.coolPortrait => (_coolA, _coolB),
  BaselineArtwork.warmCover || BaselineArtwork.warmPortrait => (_warmA, _warmB),
  BaselineArtwork.neutralCover ||
  BaselineArtwork.neutralPortrait => (_neutralA, _neutralB),
};

_Rgb _pixel(BaselineArtwork art, double x, double y) {
  final (dark, light) = _family(art);
  // A diagonal gradient as the ground.
  var colour = _mix(dark, light, (x * 0.6 + y * 0.4).clamp(0.0, 1.0));
  switch (art) {
    case BaselineArtwork.coolCover:
      // A bright sun and soft horizontal bands.
      final sun = math.sqrt(math.pow(x - 0.7, 2) + math.pow(y - 0.3, 2));
      colour = _mix(colour, (0.95, 0.97, 1.0), 1 - _smooth(0.12, 0.16, sun));
      final band = 0.5 + 0.5 * math.sin(y * math.pi * 10);
      colour = _mix(colour, dark, band * 0.18 * _smooth(0.55, 0.65, y));
    case BaselineArtwork.warmCover:
      // Concentric rings around the lower left.
      final d = math.sqrt(math.pow(x - 0.25, 2) + math.pow(y - 0.8, 2));
      final ring = 0.5 + 0.5 * math.cos(d * math.pi * 14);
      colour = _mix(colour, (1.0, 0.86, 0.55), ring * 0.35);
    case BaselineArtwork.neutralCover:
      // A grid of soft squares.
      final cx = (x * 4) % 1, cy = (y * 4) % 1;
      final inside =
          _smooth(0.08, 0.12, cx) *
          (1 - _smooth(0.88, 0.92, cx)) *
          _smooth(0.08, 0.12, cy) *
          (1 - _smooth(0.88, 0.92, cy));
      colour = _mix(colour, light, inside * 0.25);
    case BaselineArtwork.coolPortrait ||
        BaselineArtwork.warmPortrait ||
        BaselineArtwork.neutralPortrait:
      // A head and shoulders silhouette in a contrasting tone.
      const _Rgb figure = (0.86, 0.72, 0.62);
      final head = math.sqrt(
        math.pow(x - 0.5, 2) + math.pow((y - 0.38) * 0.9, 2),
      );
      final shoulders = math.sqrt(
        math.pow((x - 0.5) * 0.75, 2) + math.pow(y - 1.05, 2),
      );
      final body = math.max(
        1 - _smooth(0.17, 0.19, head),
        1 - _smooth(0.36, 0.38, shoulders),
      );
      final shade = _mix(figure, dark, (y * 0.5).clamp(0.0, 1.0));
      colour = _mix(colour, shade, body);
  }
  return colour;
}

/// A minimal PNG encoder: 8-bit RGB, filter 0, one zlib IDAT chunk.
Uint8List encodePngRgb(int width, int height, Uint8List rgb) {
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    raw.add(Uint8List.sublistView(rgb, y * width * 3, (y + 1) * width * 3));
  }
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type: RGB
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _chunk(out, 'IHDR', header.buffer.asUint8List());
  _chunk(
    out,
    'IDAT',
    Uint8List.fromList(ZLibEncoder(level: 9).convert(raw.takeBytes())),
  );
  _chunk(out, 'IEND', Uint8List(0));
  return out.takeBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  out.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
  out.add(typeBytes);
  out.add(data);
  final crc = _crc32([...typeBytes, ...data]);
  out.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
