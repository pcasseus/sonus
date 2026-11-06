import 'package:flutter/material.dart';

import '../../../../core/design/sonus_tokens.dart';
import '../../domain/models/chart_type.dart';
import '../editorial/moment_editorial_desk.dart';
import '../editorial/moment_family.dart';
import '../editorial/moment_publisher.dart';

/// How a story is presented in the Moments feed (App Update 1.1), from its
/// significance: the family it was told in and its recorded facts. Never
/// random and never by publisher. Presentation only: the story's words,
/// publisher and facts are unchanged, so earlier stories read as before.
enum MomentStoryFormat {
  /// Major events: a #1 (first, return, debut, self-replacement), an
  /// artist's first #1, a Top 10 debut, a new top artist, a major jump.
  feature,

  /// Number-led: stream and longevity milestones and #1 holds.
  spotlight,

  /// Everyday chart movement, entries, exits and smaller breakthroughs.
  bulletin;

  static MomentStoryFormat of(MomentStory story) => switch (story.family) {
    MomentFamily.songDebutNumberOne ||
    MomentFamily.releaseDebutNumberOne ||
    MomentFamily.songFirstNumberOne ||
    MomentFamily.releaseReachesNumberOne ||
    MomentFamily.songReturnsToNumberOne ||
    MomentFamily.releaseReturnsToNumberOne ||
    MomentFamily.songSelfReplacement ||
    MomentFamily.releaseSelfReplacement ||
    MomentFamily.artistFirstNumberOne ||
    MomentFamily.artistFirstNumberOneRelease ||
    MomentFamily.artistTopArtist ||
    MomentFamily.songDebutTop10 ||
    MomentFamily.songHot100MajorJump => feature,
    MomentFamily.songStreamMilestone ||
    MomentFamily.releaseStreamMilestone ||
    MomentFamily.artistStreamMilestone ||
    MomentFamily.songWeeksMilestone ||
    MomentFamily.releaseWeeksMilestone ||
    MomentFamily.songNumberOneHold ||
    MomentFamily.releaseNumberOneHold => spotlight,
    _ => bulletin,
  };
}

/// The kind label a card leads with.
enum MomentKind {
  feature('FEATURE STORY', Icons.auto_awesome_rounded),
  breakthrough('BREAKTHROUGH', Icons.auto_awesome_rounded),
  debut('CHART DEBUT', Icons.add_rounded),
  bulletin('CHART BULLETIN', Icons.format_list_bulleted_rounded),
  exit('CHART EXIT', Icons.close_rounded),
  hold('#1 HOLD', Icons.workspace_premium_rounded),
  milestone('MILESTONE', Icons.radio_button_checked_rounded);

  const MomentKind(this.label, this.icon);

  final String label;
  final IconData icon;

  static MomentKind of(MomentStory story) {
    switch (MomentStoryFormat.of(story)) {
      case MomentStoryFormat.feature:
        return feature;
      case MomentStoryFormat.spotlight:
        return story.family == MomentFamily.songNumberOneHold ||
                story.family == MomentFamily.releaseNumberOneHold
            ? hold
            : milestone;
      case MomentStoryFormat.bulletin:
        break;
    }
    return switch (story.family) {
      MomentFamily.songHot100Breakthrough ||
      MomentFamily.songFirstThreshold ||
      MomentFamily.releaseFirstThreshold ||
      MomentFamily.artistFirstHot100 ||
      MomentFamily.artistFirstTop10 ||
      MomentFamily.songHot100Return => breakthrough,
      MomentFamily.songChartMove || MomentFamily.releaseChartMove =>
        story.status.endsWith('ENTRY') ? breakthrough : bulletin,
      MomentFamily.songDebut ||
      MomentFamily.songBubblingUnderDebut ||
      MomentFamily.releaseDebut => debut,
      MomentFamily.songHot100Exit ||
      MomentFamily.songHot100Departure ||
      MomentFamily.songChartDeparture ||
      MomentFamily.releaseChartDeparture ||
      MomentFamily.songBubblingUnderFall => exit,
      _ => bulletin,
    };
  }
}

/// One badge under a story: a real recorded fact.
class MomentBadge {
  const MomentBadge(this.label, this.tone, {this.icon, this.semantics});

  final String label;
  final MomentBadgeTone tone;
  final IconData? icon;

  /// What a screen reader says, when the label alone is terse ("↑ 1").
  final String? semantics;

  /// The badges for [story]: its rank, its movement, and its status, each
  /// only when recorded. A badge never repeats another.
  static List<MomentBadge> of(MomentStory story) {
    final facts = story.facts;
    final first = story.item.events.first;
    final badges = <MomentBadge>[];
    final rank = story.rank;
    final family = story.family;
    final hold =
        family == MomentFamily.songNumberOneHold ||
        family == MomentFamily.releaseNumberOneHold;
    final exit =
        family == MomentFamily.songHot100Departure ||
        family == MomentFamily.songChartDeparture ||
        family == MomentFamily.releaseChartDeparture;
    final milestone =
        family == MomentFamily.songStreamMilestone ||
        family == MomentFamily.releaseStreamMilestone ||
        family == MomentFamily.artistStreamMilestone;

    if (milestone) {
      final value = first.milestoneValue ?? facts.milestone;
      if (value != null) {
        badges.add(
          MomentBadge(
            '${_grouped(value)} ${value == 1 ? 'STREAM' : 'STREAMS'}',
            MomentBadgeTone.neutral,
          ),
        );
      }
      badges.add(
        MomentBadge(switch (family) {
          MomentFamily.artistStreamMilestone => 'ARTIST',
          MomentFamily.releaseStreamMilestone =>
            facts.releaseLabel.toUpperCase(),
          _ => 'SONG',
        }, MomentBadgeTone.neutral),
      );
      return badges;
    }

    if (rank != null && !exit) {
      badges.add(MomentBadge('#$rank', MomentBadgeTone.neutral));
    }
    if (exit && first.currentRank != null) {
      badges.add(MomentBadge('#${first.currentRank}', MomentBadgeTone.neutral));
    }
    final climb = story.climb;
    if (climb != null && climb > 0) {
      badges.add(
        MomentBadge(
          '$climb',
          MomentBadgeTone.up,
          icon: Icons.arrow_upward_rounded,
          semantics: 'Up $climb ${climb == 1 ? 'place' : 'places'}',
        ),
      );
    }
    if (hold) {
      final days = first.milestoneValue ?? 1;
      badges.add(
        MomentBadge(
          '$days ${days == 1 ? 'DAY' : 'DAYS'} AT #1',
          MomentBadgeTone.gold,
          icon: Icons.workspace_premium_rounded,
        ),
      );
      return badges;
    }
    if (exit) {
      final days = first.milestoneValue;
      if (days != null) {
        final where = family == MomentFamily.songHot100Departure
            ? 'ON HOT 100'
            : 'ON CHART';
        badges.add(
          MomentBadge(
            '$days ${days == 1 ? 'DAY' : 'DAYS'} $where',
            MomentBadgeTone.neutral,
          ),
        );
      }
      return badges;
    }
    final status = story.status;
    if (status.isNotEmpty) {
      badges.add(
        MomentBadge(status, switch (status) {
          'RE-ENTRY' ||
          'BACK AT #1' ||
          'HOT 100 BREAKTHROUGH' ||
          '#1 DEBUT' => MomentBadgeTone.accent,
          final s when s.endsWith('ENTRY') => MomentBadgeTone.accent,
          _ => MomentBadgeTone.neutral,
        }),
      );
    }
    if (facts.chartType == ChartType.albums &&
        family != MomentFamily.artistTopArtist) {
      badges.add(
        MomentBadge(facts.releaseLabel.toUpperCase(), MomentBadgeTone.neutral),
      );
    }
    return badges;
  }

  static String _grouped(int value) {
    final digits = '$value';
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}

enum MomentBadgeTone { neutral, up, down, accent, gold }

/// The number a Milestone Spotlight leads with, and its unit.
class MomentSpotlightNumber {
  const MomentSpotlightNumber(this.value, this.unit);

  final String value;
  final String unit;

  static MomentSpotlightNumber? of(MomentStory story) {
    final first = story.item.events.first;
    switch (story.family) {
      case MomentFamily.songNumberOneHold || MomentFamily.releaseNumberOneHold:
        final days = first.milestoneValue ?? 1;
        return MomentSpotlightNumber(
          '$days',
          days == 1 ? 'DAY AT #1' : 'DAYS AT #1',
        );
      case MomentFamily.songWeeksMilestone ||
          MomentFamily.releaseWeeksMilestone:
        final weeks = story.facts.weeks ?? first.milestoneValue;
        return weeks == null
            ? null
            : MomentSpotlightNumber('$weeks', weeks == 1 ? 'WEEK' : 'WEEKS');
      default:
        final value = first.milestoneValue ?? story.facts.milestone;
        return value == null
            ? null
            : MomentSpotlightNumber(
                MomentBadge._grouped(value),
                value == 1 ? 'STREAM' : 'STREAMS',
              );
    }
  }
}

/// The Sonus editorial accents (App Update 1.1): a pink and a purple taken
/// toward the theme's own accents, so every theme keeps its character. Text
/// and icon colours are checked against the card surface (4.5:1 text, 3:1
/// borders and icons) and fall back to the theme's text colour. High
/// contrast uses the theme's text colour throughout, with solid outlines.
class MomentEditorialPalette {
  const MomentEditorialPalette({
    required this.pink,
    required this.purple,
    required this.pinkText,
    required this.purpleText,
    required this.up,
    required this.down,
    required this.gold,
    required this.outline,
    required this.surface,
    required this.highContrast,
    required this.glow,
    required this.gradients,
  });

  factory MomentEditorialPalette.of(
    SonusColors colors,
    SonusDecorationTokens d,
  ) {
    final surface = colors.raisedSurface;
    if (d.highContrast) {
      return MomentEditorialPalette(
        pink: colors.textPrimary,
        purple: colors.textPrimary,
        pinkText: colors.textPrimary,
        purpleText: colors.textPrimary,
        up: _readable(colors.chartUp, surface, 4.5, colors.textPrimary),
        down: _readable(colors.chartDown, surface, 4.5, colors.textPrimary),
        gold: colors.textPrimary,
        outline: colors.textPrimary,
        surface: surface,
        highContrast: true,
        glow: false,
        gradients: false,
      );
    }
    final pink = Color.lerp(
      const Color(0xFFFF4FB4),
      colors.accentSecondary,
      0.25,
    )!;
    final purple = Color.lerp(
      const Color(0xFF9D6BFF),
      colors.accentPrimary,
      0.3,
    )!;
    return MomentEditorialPalette(
      pink: _readable(pink, surface, 3, colors.textPrimary),
      purple: _readable(purple, surface, 3, colors.textPrimary),
      pinkText: _readable(
        Color.lerp(pink, Colors.white, 0.2)!,
        surface,
        4.5,
        colors.textPrimary,
      ),
      purpleText: _readable(
        Color.lerp(purple, Colors.white, 0.35)!,
        surface,
        4.5,
        colors.textPrimary,
      ),
      up: _readable(colors.chartUp, surface, 4.5, colors.textPrimary),
      down: _readable(colors.chartDown, surface, 4.5, colors.textPrimary),
      gold: _readable(
        const Color(0xFFFFC94D),
        surface,
        4.5,
        colors.textPrimary,
      ),
      outline: colors.border,
      surface: surface,
      highContrast: false,
      glow: d.allowGlow,
      gradients: d.allowGradients,
    );
  }

  final Color pink;
  final Color purple;
  final Color pinkText;
  final Color purpleText;
  final Color up;
  final Color down;
  final Color gold;
  final Color outline;
  final Color surface;
  final bool highContrast;
  final bool glow;
  final bool gradients;

  Color publisherColor(MomentPublisher publisher) =>
      publisher == MomentPublisher.pulsePop ? purpleText : pinkText;

  Color kindColor(MomentKind kind) => switch (kind) {
    MomentKind.feature || MomentKind.breakthrough => pinkText,
    MomentKind.hold => gold,
    MomentKind.exit => pinkText,
    _ => purpleText,
  };

  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  static Color _readable(
    Color color,
    Color surface,
    double ratio,
    Color fallback,
  ) {
    final opaque = color.withValues(alpha: 1);
    if (contrast(opaque, surface) >= ratio) return opaque;
    // Lighten toward white (dark themes) or darken (light) until readable.
    final dark = surface.computeLuminance() < 0.4;
    for (var step = 1; step <= 10; step++) {
      final candidate = Color.lerp(
        opaque,
        dark ? Colors.white : Colors.black,
        step / 10,
      )!;
      if (contrast(candidate, surface) >= ratio) return candidate;
    }
    return fallback;
  }
}

/// "now", "5m", "2h", "3d", or the date for older stories.
String momentAge(DateTime occurredAt, DateTime now) {
  final age = now.toUtc().difference(occurredAt.toUtc());
  if (age.inMinutes < 1) return 'now';
  if (age.inHours < 1) return '${age.inMinutes}m';
  if (age.inDays < 1) return '${age.inHours}h';
  if (age.inDays < 7) return '${age.inDays}d';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = occurredAt.toLocal();
  return '${months[local.month - 1]} ${local.day}';
}

/// The spoken age: "2 hours ago".
String momentAgeSpoken(DateTime occurredAt, DateTime now) {
  final age = now.toUtc().difference(occurredAt.toUtc());
  String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'} ago';
  if (age.inMinutes < 1) return 'just now';
  if (age.inHours < 1) return unit(age.inMinutes, 'minute');
  if (age.inDays < 1) return unit(age.inHours, 'hour');
  if (age.inDays < 7) return unit(age.inDays, 'day');
  return momentAge(occurredAt, now);
}
