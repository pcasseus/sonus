/// Text scale above which Sonus rows and headers switch to their
/// large-text layout (more lines, details moved, icons dropped).
///
/// Compared with `>`: at exactly 1.3 (Android's "Large" font step) the
/// normal layout is kept. The exceptions are Pulse's rankings header and
/// overview tiles, which change at 1.3 too (`>=`); unifying them is an
/// open decision (cleanup register R21). The Artist Roster and Film Reel
/// keep their own thresholds.
const double sonusLargeTextScale = 1.3;
