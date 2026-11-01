import 'pulse_period_data.dart';

/// How a value compares with the selected comparison (spec §4–5).
enum PulseDeltaKind {
  /// More than before.
  up,

  /// Less than before.
  down,

  /// Exactly the same.
  same,

  /// Up from zero: shown as "New", never as a percentage (rule 4).
  newValue,

  /// The comparison period starts before recorded history (rule 3).
  notEnoughHistory,

  /// "No comparison" is selected.
  none,
}

/// One tile's comparison, exact and never invented.
class PulseDelta {
  const PulseDelta._(this.kind, this.difference, this.percent);

  const PulseDelta.none() : this._(PulseDeltaKind.none, 0, null);

  const PulseDelta.notEnoughHistory()
    : this._(PulseDeltaKind.notEnoughHistory, 0, null);

  /// Compares [current] with [previous]. Values are whole units (minutes,
  /// counts): a percentage is only given from a non-zero base.
  factory PulseDelta.compare(num current, num previous) {
    final difference = current - previous;
    if (difference == 0) return PulseDelta._(PulseDeltaKind.same, 0, 0);
    if (previous == 0) {
      return PulseDelta._(PulseDeltaKind.newValue, difference, null);
    }
    return PulseDelta._(
      difference > 0 ? PulseDeltaKind.up : PulseDeltaKind.down,
      difference,
      difference / previous * 100,
    );
  }

  final PulseDeltaKind kind;

  /// current − previous, in the tile's unit.
  final num difference;

  /// The exact percentage change; null when there is none to give.
  final double? percent;

  /// "▲ 12%", "▼ 4%", "▲ <1%", "No change", "New", "Not enough history",
  /// or "" with no comparison. Always a word or arrow, never colour alone.
  String get label => switch (kind) {
    PulseDeltaKind.up => '▲ ${_percent()}',
    PulseDeltaKind.down => '▼ ${_percent()}',
    PulseDeltaKind.same => 'No change',
    PulseDeltaKind.newValue => 'New',
    PulseDeltaKind.notEnoughHistory => 'Not enough history',
    PulseDeltaKind.none => '',
  };

  /// Words for screen readers: "Up 12%, 214 more", "Down 4%, 3 fewer".
  String spokenLabel(String unit) => switch (kind) {
    PulseDeltaKind.up => 'Up ${_percent()}, ${_abs()} more $unit',
    PulseDeltaKind.down => 'Down ${_percent()}, ${_abs()} fewer $unit',
    PulseDeltaKind.same => 'No change',
    PulseDeltaKind.newValue => 'New: none in the comparison period',
    PulseDeltaKind.notEnoughHistory => 'Not enough history for this comparison',
    PulseDeltaKind.none => '',
  };

  /// "+214" / "−3": the exact difference, signed.
  String get signedDifference =>
      difference > 0 ? '+${_abs()}' : (difference < 0 ? '−${_abs()}' : '0');

  String _abs() => _grouped(difference.abs().round());

  /// Whole percent, "<1%" for a real change that rounds to zero.
  String _percent() {
    final p = percent!.abs();
    if (p < 0.5) return '<1%';
    return '${_grouped(p.round())}%';
  }

  static String _grouped(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// The six tiles' deltas against one comparison.
class PulseOverviewDeltas {
  const PulseOverviewDeltas({
    required this.minutes,
    required this.streams,
    required this.allPlays,
    required this.activeDays,
    required this.artists,
    required this.tracks,
  });

  /// Deltas for [current] against [comparison]: none without one, "Not
  /// enough history" when it isn't eligible.
  factory PulseOverviewDeltas.of(
    PulseOverview current,
    PulseComparison? comparison,
  ) {
    if (comparison == null) return _all(const PulseDelta.none());
    final before = comparison.overview;
    if (!comparison.isAvailable || before == null) {
      return _all(const PulseDelta.notEnoughHistory());
    }
    return PulseOverviewDeltas(
      // Whole minutes on both sides, as the tiles show them.
      minutes: PulseDelta.compare(
        current.listened.inMinutes,
        before.listened.inMinutes,
      ),
      streams: PulseDelta.compare(current.streams, before.streams),
      allPlays: PulseDelta.compare(current.allPlays, before.allPlays),
      activeDays: PulseDelta.compare(current.activeDays, before.activeDays),
      artists: PulseDelta.compare(current.artists, before.artists),
      tracks: PulseDelta.compare(current.tracks, before.tracks),
    );
  }

  static PulseOverviewDeltas _all(PulseDelta delta) => PulseOverviewDeltas(
    minutes: delta,
    streams: delta,
    allPlays: delta,
    activeDays: delta,
    artists: delta,
    tracks: delta,
  );

  final PulseDelta minutes;
  final PulseDelta streams;
  final PulseDelta allPlays;
  final PulseDelta activeDays;
  final PulseDelta artists;
  final PulseDelta tracks;
}
