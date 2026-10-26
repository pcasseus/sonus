/// How much of a release date is known.
enum ReleaseDatePrecision {
  /// Only the year, such as `2026`.
  year,

  /// The year and month, such as `2026-04`.
  month,

  /// The exact day, such as `2026-04-17`.
  day,
}

/// A release date that says only as much as is known (SN-49): `2026`,
/// `2026-04` or `2026-04-17`. Nothing is filled in to make a partial date
/// look exact.
///
/// It is stored as an instant (the start of its year, month or day, at UTC
/// midnight) plus its [precision]. The instant orders releases; the
/// precision says what may be shown.
class ReleaseDate implements Comparable<ReleaseDate> {
  const ReleaseDate._(this.year, this.month, this.day);

  /// A date of [year], and [month] and [day] when known. Returns null for a
  /// date that does not exist, or a day without a month.
  static ReleaseDate? of(int year, [int? month, int? day]) {
    if (year < 1 || year > 9999) return null;
    if (day != null && month == null) return null;
    if (month != null && (month < 1 || month > 12)) return null;
    if (day != null) {
      final date = DateTime.utc(year, month!, day);
      if (date.month != month || date.day != day) return null;
    }
    return ReleaseDate._(year, month, day);
  }

  /// Reads `YYYY`, `YYYY-MM` or `YYYY-MM-DD`, as MusicBrainz and people
  /// write them. Returns null for anything else, including impossible
  /// dates such as `2026-02-30`.
  static ReleaseDate? tryParse(String? text) {
    final match = RegExp(
      r'^(\d{4})(?:-(\d{1,2})(?:-(\d{1,2}))?)?$',
    ).firstMatch(text?.trim() ?? '');
    if (match == null) return null;
    return of(
      int.parse(match.group(1)!),
      match.group(2) == null ? null : int.parse(match.group(2)!),
      match.group(3) == null ? null : int.parse(match.group(3)!),
    );
  }

  /// The date held in a stored [instant] at [precision]. A null precision
  /// is a date saved before precision was recorded; it is shown as the
  /// exact day it holds, as it always was.
  ///
  /// Older imports saved local midnight rather than UTC midnight, so an
  /// instant that is not at UTC midnight is read in local time; otherwise
  /// a year-only date could show as December 31 of the year before.
  static ReleaseDate fromStored(
    DateTime instant,
    ReleaseDatePrecision? precision,
  ) {
    final utc = instant.toUtc();
    final atUtcMidnight =
        utc.hour == 0 &&
        utc.minute == 0 &&
        utc.second == 0 &&
        utc.millisecond == 0;
    final date = atUtcMidnight ? utc : instant.toLocal();

    return switch (precision) {
      ReleaseDatePrecision.year => ReleaseDate._(date.year, null, null),
      ReleaseDatePrecision.month => ReleaseDate._(date.year, date.month, null),
      _ => ReleaseDate._(date.year, date.month, date.day),
    };
  }

  final int year;
  final int? month;
  final int? day;

  ReleaseDatePrecision get precision => day != null
      ? ReleaseDatePrecision.day
      : month != null
      ? ReleaseDatePrecision.month
      : ReleaseDatePrecision.year;

  /// The instant stored for this date: the start of its year, month or day
  /// at UTC midnight.
  DateTime get instant => DateTime.utc(year, month ?? 1, day ?? 1);

  /// `2026`, `2026-04` or `2026-04-17`.
  String get iso {
    final buffer = StringBuffer(year.toString().padLeft(4, '0'));
    if (month case final month?) {
      buffer.write('-${month.toString().padLeft(2, '0')}');
    }
    if (day case final day?) {
      buffer.write('-${day.toString().padLeft(2, '0')}');
    }
    return buffer.toString();
  }

  /// `2026`, `April 2026` or `April 17, 2026`.
  String get label => switch ((month, day)) {
    (final month?, final day?) => '${_months[month - 1]} $day, $year',
    (final month?, null) => '${_months[month - 1]} $year',
    _ => '$year',
  };

  /// Whether [other] says the same or more about the same date, so that
  /// replacing this with [other] loses nothing.
  bool isRefinedBy(ReleaseDate other) =>
      other.year == year &&
      (month == null || other.month == month) &&
      (day == null || other.day == day);

  /// Orders by the start of each date, then less precise first, so `2026`
  /// sorts just before `2026-01` and `2026-01-01`.
  @override
  int compareTo(ReleaseDate other) {
    final byInstant = instant.compareTo(other.instant);
    return byInstant != 0
        ? byInstant
        : precision.index.compareTo(other.precision.index);
  }

  @override
  bool operator ==(Object other) =>
      other is ReleaseDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
}
