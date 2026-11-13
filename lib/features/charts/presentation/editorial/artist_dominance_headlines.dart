import 'package:flutter/foundation.dart';

import '../../domain/moments/chart_moment_artist_dominance.dart';
import 'moment_facts.dart';
import 'moment_family.dart';
import 'moment_headlines.dart';
import 'moment_publisher.dart';
import 'refined_headline_catalog.dart';

/// One headline line of the App Update 1.2 artist-dominance families.
class _Line {
  const _Line(
    this.family,
    this.id,
    this.publisher,
    this.build, {
    this.minimum = 0,
    this.streakSafe = true,
    this.needsSecond = false,
  });

  final MomentFamily family;
  final String id;
  final MomentPublisher publisher;
  final String Function(MomentFacts f) build;

  /// The smallest sweep size (sweeps, joint control) or song count
  /// (presence) the line is used for: Pulse Pop's intensity minimums.
  final int minimum;

  /// Whether " for a second straight week" can end the line unambiguously.
  final bool streakSafe;

  /// The line names the song at #2 (or the second song in the zone).
  final bool needsSecond;
}

/// Headlines for artist sweeps, Top 10 and Hot 100 presence (approved
/// 2026-11-12, REF-19 final editorial approval) and joint chart control
/// (approved 2026-11-13).
///
/// - The card's kicker already reads "Weekly Sonus Hot 100", so lines say
///   "the Hot 100"; only a historical claim names the "Sonus Hot 100",
///   where its scope matters.
/// - Counts are the true counts; a sentence never starts with a digit.
/// - Pulse Pop's stronger lines need a minimum size, so a modest
///   achievement is never told as a takeover.
/// - A recorded historical claim ends the line; none is ever invented.
/// - Names and titles are tidied (control characters and runs of spaces
///   removed; double quotes inside a title made single), never rewritten.
abstract final class ArtistDominanceHeadlines {
  static final List<RefinedAddition> additions = [
    for (final line in _lines)
      RefinedAddition(
        line.family,
        HeadlineVariant(
          line.id,
          line.publisher,
          (f) => _withHistory(f, line.publisher, line.build(f)),
          requires: {
            MomentFact.count,
            MomentFact.threshold,
            MomentFact.rank,
            if (line.needsSecond) MomentFact.rival,
          },
        ),
        when: (f) => _fits(line, f),
        approved: true,
      ),
  ];

  /// Every line of [family], approved or not, for review and tests.
  static List<HeadlineVariant> linesOf(MomentFamily family) => [
    for (final addition in additions)
      if (addition.family == family) addition.variant,
  ];

  static bool _fits(_Line line, MomentFacts f) {
    if (line.family == MomentFamily.artistJointControl) {
      final partner = f.jointPartner;
      return partner != null &&
          partner.trim().isNotEmpty &&
          (f.threshold ?? 0) >= line.minimum;
    }
    final dominance = f.dominance;
    if (dominance == null || _familyOf(dominance.kind) != line.family) {
      return false;
    }
    final size = dominance.kind == ArtistDominanceKind.sweep
        ? f.threshold ?? 0
        : f.count ?? 0;
    if (size < line.minimum) return false;
    return line.streakSafe ||
        dominance.context.kind != DominanceContextKind.streak;
  }

  static MomentFamily _familyOf(ArtistDominanceKind kind) => switch (kind) {
    ArtistDominanceKind.sweep => MomentFamily.artistChartSweep,
    ArtistDominanceKind.top10 => MomentFamily.artistTop10Presence,
    ArtistDominanceKind.hot100 => MomentFamily.artistHot100Presence,
  };

  /// [line] with the recorded historical claim, if any, before its final
  /// full stop or exclamation mark.
  static String _withHistory(
    MomentFacts f,
    MomentPublisher publisher,
    String line,
  ) => withHistory(f, publisher, line);

  /// [line] with its recorded claim. A claim limited to the verified
  /// history window is told only when [windowApproved].
  @visibleForTesting
  static String withHistory(
    MomentFacts f,
    MomentPublisher publisher,
    String line, {
    bool windowApproved = MomentHeadlines.verifiedHistoryWindowApproved,
  }) {
    final context = f.dominance?.context;
    if (context == null || context.kind == DominanceContextKind.none) {
      return line;
    }
    final window = context.windowStartUtc;
    if (window != null) {
      if (!windowApproved) return line;
      final end = line.substring(line.length - 1);
      return '${line.substring(0, line.length - 1)}'
          '${_windowClause(f, context, window.toLocal())}$end';
    }
    final n = f.threshold ?? 0;
    final pulse = publisher == MomentPublisher.pulsePop;
    final clause = switch (context.kind) {
      DominanceContextKind.none => '',
      DominanceContextKind.chartFirst =>
        pulse
            ? ', a first for the Sonus Hot 100'
            : ', the first Top $n sweep in Sonus Hot 100 history',
      DominanceContextKind.chartRecord =>
        n == 10
            ? ', the most Top 10 songs any artist has held in Sonus Hot 100 '
                  'history'
            : ', the most songs any artist has had on the Hot 100 at once in '
                  'Sonus Hot 100 history',
      DominanceContextKind.chartRecordTie =>
        ', matching the Sonus Hot 100 record',
      DominanceContextKind.streak =>
        ' for a ${MomentFacts.ordinalWord(context.count ?? 2)} straight week',
      DominanceContextKind.artistFirst =>
        ', ${MomentFacts.possessive(_artist(f))} first Top $n sweep on the '
            'Sonus Hot 100',
      DominanceContextKind.personalBest =>
        ', a personal best for ${_artist(f)} on the Sonus Hot 100',
      DominanceContextKind.repeat =>
        ', ${MomentFacts.possessive(_artist(f))} '
            '${MomentFacts.ordinalWord(context.count ?? 2)} Top $n sweep on '
            'the Sonus Hot 100',
    };
    final end = line.substring(line.length - 1);
    return '${line.substring(0, line.length - 1)}$clause$end';
  }

  /// Wording (approved 2026-11-13) for a claim within the verified history
  /// window that began on [startLocal].
  static String _windowClause(
    MomentFacts f,
    DominanceContext context,
    DateTime startLocal,
  ) {
    final n = f.threshold ?? 0;
    final since =
        'since verified Sonus Hot 100 tracking began on '
        '${startLocal.day} ${_monthNames[startLocal.month - 1]} '
        '${startLocal.year}';
    return switch (context.kind) {
      DominanceContextKind.chartFirst => ', the first Top $n sweep $since',
      DominanceContextKind.chartRecord =>
        n == 10
            ? ', the most Top 10 songs any artist has held $since'
            : ', the most songs any artist has had on the Hot 100 at once '
                  '$since',
      DominanceContextKind.chartRecordTie => ', matching the most $since',
      DominanceContextKind.artistFirst =>
        ', ${MomentFacts.possessive(_artist(f))} first Top $n sweep $since',
      DominanceContextKind.personalBest =>
        ', the most for ${_artist(f)} $since',
      DominanceContextKind.repeat =>
        ', ${MomentFacts.possessive(_artist(f))} '
            '${MomentFacts.ordinalWord(context.count ?? 2)} Top $n sweep '
            '$since',
      DominanceContextKind.none || DominanceContextKind.streak => '',
    };
  }

  static const _monthNames = [
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

  /// Text from the library, tidied for a headline: control characters
  /// and runs of whitespace become one space.
  static String _clean(String text) =>
      text.replaceAll(RegExp(r'[\u0000-\u001F\u007F\s]+'), ' ').trim();

  static String _artist(MomentFacts f) => _clean(f.careerArtist);
  static String _partner(MomentFacts f) => _clean(f.jointPartner ?? '');

  /// A song title in quotes; a double quote inside it becomes single.
  static String _quoted(String title) =>
      '"${_clean(title).replaceAll('"', "'")}"';

  static String _lead(MomentFacts f) => _quoted(f.title);
  static String _second(MomentFacts f) => _quoted(f.rivalTitle ?? '');

  /// The sweep's or zone's size.
  static int _n(MomentFacts f) => f.threshold ?? 0;
  static int _c(MomentFacts f) => f.count ?? 0;

  /// "#1 and #2" for a Top 2 sweep, otherwise "#1 through #N".
  static String _span(MomentFacts f) =>
      _n(f) == 2 ? '#1 and #2' : '#1 through #${_n(f)}';

  static const _words = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
  ];

  /// One to ten as words, larger numbers as digits.
  static String _word(int n) => n >= 0 && n < _words.length ? _words[n] : '$n';

  /// [_word] to start a sentence.
  static String _capitalWord(int n) {
    final word = _word(n);
    return '${word[0].toUpperCase()}${word.substring(1)}';
  }

  static const _sweep = MomentFamily.artistChartSweep;
  static const _top10 = MomentFamily.artistTop10Presence;
  static const _hot100 = MomentFamily.artistHot100Presence;
  static const _joint = MomentFamily.artistJointControl;
  static const _d = MomentPublisher.sonusDaily;
  static const _p = MomentPublisher.pulsePop;

  static final List<_Line> _lines = [
    // Sweeps: one artist alone holds #1 through #N (N = 2 to 10).
    _Line(
      _sweep,
      'artist-sweep-d1',
      _d,
      (f) => '${_artist(f)} holds ${_span(f)} on the Hot 100.',
    ),
    _Line(
      _sweep,
      'artist-sweep-d2',
      _d,
      (f) =>
          '${_artist(f)} sweeps the Top ${_n(f)} of the Hot 100, led by ${_lead(f)} at #1.',
      streakSafe: false,
    ),
    _Line(
      _sweep,
      'artist-sweep-d3',
      _d,
      (f) =>
          '${_lead(f)} leads a Top ${_n(f)} sweep for ${_artist(f)} on the Hot 100.',
    ),
    _Line(
      _sweep,
      'artist-sweep-d4',
      _d,
      (f) => "The Hot 100's Top ${_n(f)} belongs entirely to ${_artist(f)}.",
    ),
    _Line(
      _sweep,
      'artist-sweep-d5',
      _d,
      (f) =>
          '${_artist(f)} occupies ${_span(f)} on the Hot 100, with ${_lead(f)} at #1 and ${_second(f)} at #2.',
      streakSafe: false,
      needsSecond: true,
    ),
    _Line(
      _sweep,
      'artist-sweep-d6',
      _d,
      (f) => '${_artist(f)} completes a Top ${_n(f)} sweep of the Hot 100.',
    ),
    _Line(
      _sweep,
      'artist-sweep-p1',
      _p,
      (f) => '${_artist(f)} takes ${_span(f)} on the Hot 100!',
    ),
    _Line(
      _sweep,
      'artist-sweep-p2',
      _p,
      (f) => 'A Top ${_n(f)} sweep for ${_artist(f)}, led by ${_lead(f)}!',
      streakSafe: false,
    ),
    _Line(
      _sweep,
      'artist-sweep-p3',
      _p,
      (f) =>
          '${_lead(f)} at #1, ${_second(f)} at #2: the top ${_word(_n(f))} spots all belong to ${_artist(f)}!',
      needsSecond: true,
    ),
    _Line(
      _sweep,
      'artist-sweep-p4',
      _p,
      (f) => '${_artist(f)} owns the Top ${_n(f)} of the Hot 100!',
    ),
    _Line(
      _sweep,
      'artist-sweep-p5',
      _p,
      (f) => 'Clean sweep! ${_artist(f)} fills the entire Top ${_n(f)}!',
      minimum: 5,
    ),
    _Line(
      _sweep,
      'artist-sweep-p6',
      _p,
      (f) => 'No one else in the Top ${_n(f)}: ${_artist(f)} holds every spot!',
      minimum: 5,
    ),

    // Top 10 presence: the true count of the artist's Top 10 songs.
    _Line(
      _top10,
      'artist-top10-count-d1',
      _d,
      (f) =>
          '${_artist(f)} has ${_c(f)} songs in the Top 10 of the Hot 100, led by ${_lead(f)} at #${f.rank}.',
    ),
    _Line(
      _top10,
      'artist-top10-count-d2',
      _d,
      (f) => "${_artist(f)} places ${_c(f)} songs in the Hot 100's Top 10.",
    ),
    _Line(
      _top10,
      'artist-top10-count-d3',
      _d,
      (f) =>
          "${_capitalWord(_c(f))} of the Hot 100's Top 10 songs are by ${_artist(f)}.",
    ),
    _Line(
      _top10,
      'artist-top10-count-d4',
      _d,
      (f) =>
          '${_artist(f)} holds ${_c(f)} of the 10 highest positions on the Hot 100.',
    ),
    _Line(
      _top10,
      'artist-top10-count-d5',
      _d,
      (f) =>
          "${_lead(f)} leads ${MomentFacts.possessive(_artist(f))} ${_c(f)} Top 10 songs on the Hot 100.",
    ),
    _Line(
      _top10,
      'artist-top10-count-d6',
      _d,
      (f) =>
          "${_artist(f)} now has ${_c(f)} songs inside the Hot 100's Top 10.",
    ),
    _Line(
      _top10,
      'artist-top10-count-p1',
      _p,
      (f) => '${_artist(f)} has ${_c(f)} songs in the Top 10!',
    ),
    _Line(
      _top10,
      'artist-top10-count-p2',
      _p,
      (f) => '${_capitalWord(_c(f))} Top 10 songs at once for ${_artist(f)}!',
    ),
    _Line(
      _top10,
      'artist-top10-count-p3',
      _p,
      (f) =>
          '${_lead(f)} leads the way as ${_artist(f)} lands ${_c(f)} songs in the Top 10!',
    ),
    _Line(
      _top10,
      'artist-top10-count-p4',
      _p,
      (f) => '${_artist(f)} holds ${_c(f)} of the 10 spots in the Top 10!',
    ),
    _Line(
      _top10,
      'artist-top10-count-p5',
      _p,
      (f) => '${_artist(f)} is all over the Top 10 with ${_c(f)} songs!',
      minimum: 5,
    ),
    _Line(
      _top10,
      'artist-top10-count-p6',
      _p,
      (f) => 'Top 10 takeover: ${_c(f)} songs by ${_artist(f)}!',
      minimum: 6,
    ),

    // Hot 100 presence: the true count of the artist's Hot 100 songs.
    _Line(
      _hot100,
      'artist-hot100-count-d1',
      _d,
      (f) =>
          '${_artist(f)} has ${_c(f)} songs on the Hot 100, led by ${_lead(f)} at #${f.rank}.',
    ),
    _Line(
      _hot100,
      'artist-hot100-count-d2',
      _d,
      (f) => '${_artist(f)} charts ${_c(f)} songs at once on the Hot 100.',
    ),
    _Line(
      _hot100,
      'artist-hot100-count-d3',
      _d,
      (f) => 'The Hot 100 includes ${_c(f)} songs by ${_artist(f)}.',
    ),
    _Line(
      _hot100,
      'artist-hot100-count-d4',
      _d,
      (f) => '${_lead(f)} leads ${_c(f)} Hot 100 entries for ${_artist(f)}.',
    ),
    _Line(
      _hot100,
      'artist-hot100-count-d5',
      _d,
      (f) =>
          '${_artist(f)} accounts for ${_c(f)} of the 100 songs on the Hot 100.',
    ),
    _Line(
      _hot100,
      'artist-hot100-count-d6',
      _d,
      (f) => '${_artist(f)} reaches ${_c(f)} simultaneous Hot 100 entries.',
    ),
    _Line(
      _hot100,
      'artist-hot100-count-p1',
      _p,
      (f) => '${_artist(f)} has ${_c(f)} songs on the Hot 100!',
    ),
    _Line(
      _hot100,
      'artist-hot100-count-p2',
      _p,
      (f) => 'Count them: ${_c(f)} songs by ${_artist(f)} on the Hot 100!',
    ),
    _Line(
      _hot100,
      'artist-hot100-count-p3',
      _p,
      (f) => '${_artist(f)} lands ${_c(f)} songs on the Hot 100 at once!',
    ),
    _Line(
      _hot100,
      'artist-hot100-count-p4',
      _p,
      (f) => '${_lead(f)} leads a ${_c(f)}-song Hot 100 run for ${_artist(f)}!',
      minimum: 10,
    ),
    _Line(
      _hot100,
      'artist-hot100-count-p5',
      _p,
      (f) => '${_artist(f)} is everywhere: ${_c(f)} songs on the Hot 100!',
      minimum: 10,
    ),
    _Line(
      _hot100,
      'artist-hot100-count-p6',
      _p,
      (f) => '${_artist(f)} floods the Hot 100 with ${_c(f)} songs!',
      minimum: 15,
    ),

    // Joint chart control (approved 2026-11-13). [MomentFacts.count] is
    // the first artist's songs in the Top N; the partner holds the rest.
    _Line(
      _joint,
      'artist-joint-d1',
      _d,
      (f) =>
          '${_artist(f)} and ${_partner(f)} hold #1 through #${_n(f)} on the Hot 100 between them.',
    ),
    _Line(
      _joint,
      'artist-joint-d2',
      _d,
      (f) =>
          "The Hot 100's Top ${_n(f)} belongs to two artists: ${_artist(f)} and ${_partner(f)}.",
    ),
    _Line(
      _joint,
      'artist-joint-d3',
      _d,
      (f) =>
          '${_artist(f)} (${_c(f)}) and ${_partner(f)} (${_n(f) - _c(f)}) account for every song in the Top ${_n(f)}.',
    ),
    _Line(
      _joint,
      'artist-joint-d4',
      _d,
      (f) =>
          'Only ${_artist(f)} and ${_partner(f)} appear from #1 to #${_n(f)} on the Hot 100.',
    ),
    _Line(
      _joint,
      'artist-joint-d5',
      _d,
      (f) =>
          '${_lead(f)} leads at #1 as ${_artist(f)} and ${_partner(f)} share the Top ${_n(f)}.',
    ),
    _Line(
      _joint,
      'artist-joint-d6',
      _d,
      (f) =>
          '${_artist(f)} and ${_partner(f)} split the Top ${_n(f)} of the Hot 100.',
    ),
    _Line(
      _joint,
      'artist-joint-p1',
      _p,
      (f) =>
          'Two artists, ${_word(_n(f))} spots: ${_artist(f)} and ${_partner(f)} own the Top ${_n(f)}!',
    ),
    _Line(
      _joint,
      'artist-joint-p2',
      _p,
      (f) => '${_artist(f)} and ${_partner(f)} share the whole Top ${_n(f)}!',
    ),
    _Line(
      _joint,
      'artist-joint-p3',
      _p,
      (f) =>
          'The Top ${_n(f)} is a two-artist race: ${_artist(f)} and ${_partner(f)}!',
    ),
    _Line(
      _joint,
      'artist-joint-p4',
      _p,
      (f) =>
          'Nobody else in the Top ${_n(f)}: just ${_artist(f)} and ${_partner(f)}!',
    ),
    _Line(
      _joint,
      'artist-joint-p5',
      _p,
      (f) => '${_artist(f)} and ${_partner(f)} lock out the Top ${_n(f)}!',
      minimum: 6,
    ),
    _Line(
      _joint,
      'artist-joint-p6',
      _p,
      (f) => 'A Top ${_n(f)} split between ${_artist(f)} and ${_partner(f)}!',
    ),
  ];
}
