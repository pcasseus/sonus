import 'dart:ui';

/// Whether the theme is greyscale (Monochrome), judged from its accent:
/// a red, green and blue within 0.02 of each other. Greyscale themes draw
/// no tints and keep colour for artwork only.
///
/// The one test shared by Charts, the chart movement indicator and Song
/// Stats (register R7). An explicit theme flag would be firmer than
/// reading the accent; until then every screen asks here.
bool sonusThemeIsGreyscale(Color accent) =>
    (accent.r - accent.g).abs() < 0.02 && (accent.g - accent.b).abs() < 0.02;
