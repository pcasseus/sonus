import '../../../library/domain/entities/library_organization.dart';
import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/services/chart_ranking_engine.dart';
import 'chart_jump_facts.dart';

/// What the editorial desk may look up about the library. Everything else
/// comes from the Moment's own recorded facts.
abstract interface class MomentLookups {
  String? artistName(String artistId);

  /// The release's format: as stated, null while it needs review (it
  /// might be a Single), otherwise an Album.
  ReleaseFormat? formatOf(String albumId);

  /// The format of the release the song is on, as [formatOf] gives it.
  ReleaseFormat? songReleaseFormat(String songId);

  /// The song's featured credits, exactly as stored.
  List<String> featuredOf(String songId);

  /// The song's guest credits (role guest), in credit order. Guests are
  /// never featured artists.
  List<String> guestsOf(String songId);

  /// A library artist with exactly this name, if there is one.
  String? artistIdNamed(String name);

  /// The cover of the song's release (or its own artwork), as stories
  /// before the SN-50 rules show it.
  String? songCover(String songId);

  String? releaseCover(String albumId);

  /// The song's picture for SN-50 stories (A-Q12, C-23; App Update 1.1):
  /// the cover of the edition the song first appeared on (the earliest
  /// released edition of its own album that lists it, so a song on both
  /// Standard and Deluxe shows the Standard cover and a Deluxe-only song
  /// the Deluxe cover), else its own artwork as song rows show it, else
  /// the album's cover.
  String? currentSongCover(String songId);

  /// The release's cover for SN-50 stories: the current album chart's,
  /// from its edition with the most songs (A-Q28: an edition without a
  /// cover keeps the placeholder).
  String? currentReleaseCover(String albumId);

  /// The artist's portrait, or their banner without one.
  String? artistPortrait(String artistId);
}

/// A fact a headline may need. A headline that declares a fact is only
/// chosen when the Moment really has it.
enum MomentFact {
  /// A rank before this Moment (for "jumps from #4 to #1").
  previousRank,

  /// The previous best rank.
  previousPeak,

  /// Qualified streams at this Moment.
  streams,

  /// The entity displaced or passed (verified by the chart replay).
  rival,

  /// The artist's ordinal for a career fact (their 3rd #1, …).
  ordinal,

  /// The song's album title.
  album,

  /// Weeks for a longevity milestone.
  weeks,

  /// Places climbed.
  places,

  /// A different owning artist or project than the performer credit (a
  /// soundtrack contributor's song counts for the soundtrack).
  owner,

  /// One featured artist on the song.
  featured,

  /// A current rank (not every milestone story has one).
  rank,

  /// A chart zone (Top 10, …) the story is about.
  threshold,

  /// A longevity run that is unbroken.
  consecutive,

  /// How many songs an artist has in a zone at once.
  count,

  /// Two or more zones entered for the first time in one move.
  thresholdList,

  /// A verified run of weekly climbs (SN-50 chart jumps).
  run,

  /// Places lost since the preceding finalized week (SN-50 BUG-04).
  placesDown,
}

/// Every verified fact of one story, ready for headlines.
class MomentFacts {
  const MomentFacts({
    required this.chartType,
    required this.weekly,
    required this.title,
    required this.artist,
    this.ownerName,
    this.album,
    this.format,
    this.songRelease,
    this.rank,
    this.previousRank,
    this.previousPeak,
    this.streams,
    this.milestone,
    this.ordinal,
    this.threshold,
    this.weeks,
    this.rivalTitle,
    this.rivalArtist,
    this.featured,
    this.newTopArtist,
    this.passedTopArtist,
    this.consecutive = false,
    this.count,
    this.refined = false,
    this.catalogVersion,
    this.polished = false,
    this.featuredArtists = const [],
    this.guests = const [],
    this.thresholds = const [],
    this.jump,
  });

  final ChartType chartType;

  /// From a finalized weekly chart rather than the permanent standings.
  final bool weekly;

  /// The song, release or artist the story is about.
  final String title;

  /// The credited artist (a song's performer, a release's owner).
  final String artist;

  /// The artist or project the story's career facts count for, when it is
  /// not [artist].
  final String? ownerName;

  final String? album;

  /// For release stories: Single, EP or Album; null while unconfirmed.
  final ReleaseFormat? format;

  /// For song stories: the format of the song's release; null while it is
  /// unconfirmed.
  final ReleaseFormat? songRelease;

  /// What a link to the story's release calls it: "Single", "EP", "Album",
  /// or "Release" while its format is unconfirmed.
  String get releaseLabel =>
      (chartType == ChartType.albums ? format : songRelease)?.label ??
      'Release';

  final int? rank;
  final int? previousRank;
  final int? previousPeak;
  final int? streams;
  final int? milestone;
  final int? ordinal;
  final int? threshold;
  final int? weeks;
  final String? rivalTitle;
  final String? rivalArtist;
  final String? featured;

  /// When the same play also made an artist the most-streamed artist,
  /// passing another: both names.
  final String? newTopArtist;
  final String? passedTopArtist;

  /// For longevity: the weeks are an unbroken run.
  final bool consecutive;

  /// For simultaneous entries: how many songs at once.
  final int? count;

  /// Told under the SN-50 rules (see ChartMomentRules).
  final bool refined;

  /// The refined catalog version the story is told with (SN-50 R-V); null
  /// under the earlier rules. Wording that changes in a later version
  /// branches on it, so earlier stories keep their words.
  final int? catalogVersion;

  /// Told under the SN-50 device polish (ChartMomentRules
  /// .tellsEveryChartEvent): weekly stories name the weekly chart, as
  /// refined ones do. Earlier stories keep their wording.
  final bool polished;

  /// Every featured artist on the song, in credit order: device-polish
  /// stories name them all ([subject]); earlier stories named one only.
  final List<String> featuredArtists;

  /// Guest credits, told apart from featured artists (device polish).
  final List<String> guests;

  /// "A", "A and B", "A, B and C", or for longer credits "A, B and 3
  /// others", so a headline stays readable.
  static String nameList(List<String> names) {
    if (names.length <= 1) return names.join();
    if (names.length <= 3) {
      return '${names.sublist(0, names.length - 1).join(', ')} and '
          '${names.last}';
    }
    return '${names[0]}, ${names[1]} and ${names.length - 2} others';
  }

  /// A chart jump's verified movement and stream facts (SN-50).
  final ChartJumpFacts? jump;

  /// The rank before a run of weekly climbs began.
  int? get runFromRank => jump?.fromRank;

  /// How many weeks in a row the song has climbed.
  int? get runWeeks => jump?.weeks;

  /// Places gained over the whole run.
  int? get runPlaces => jump?.placesGained;

  /// Zones first entered in one move, largest first.
  final List<int> thresholds;

  /// The artist named for career facts: the owner when it differs.
  String get careerArtist => ownerName ?? artist;

  int? get places {
    final before = previousRank;
    final now = rank;
    return before == null || now == null || before <= now ? null : before - now;
  }

  /// Places lost since the preceding finalized week; weekly stories
  /// only, where the previous rank is that week's finalized rank.
  int? get placesDown {
    final before = previousRank;
    final now = rank;
    return !weekly || before == null || now == null || now <= before
        ? null
        : now - before;
  }

  bool get bubblingUnder =>
      chartType == ChartType.songs &&
      rank != null &&
      rank! > ChartRankingEngine.officialChartLimit;

  /// SN-49: the fewest streams a story quotes. A personal chart can be
  /// led by a song played twice; "debuts at #1 with 2 streams" reads as a
  /// joke, so smaller counts are left to the chart itself.
  static const int notableStreams = 10;

  /// Whether [streams] is worth stating; see [notableStreams].
  bool get hasNotableStreams => (streams ?? 0) >= notableStreams;

  Set<MomentFact> get available => {
    if (previousRank != null) MomentFact.previousRank,
    if (previousPeak != null) MomentFact.previousPeak,
    if (hasNotableStreams) MomentFact.streams,
    if (rivalTitle != null) MomentFact.rival,
    if (ordinal != null) MomentFact.ordinal,
    if (album != null &&
        songRelease != ReleaseFormat.single &&
        album!.trim().isNotEmpty &&
        album!.trim().toLowerCase() != title.trim().toLowerCase())
      MomentFact.album,
    if (weeks != null) MomentFact.weeks,
    if (places != null) MomentFact.places,
    if (ownerName != null) MomentFact.owner,
    if (featured != null) MomentFact.featured,
    if (rank != null) MomentFact.rank,
    if (threshold != null) MomentFact.threshold,
    if (consecutive) MomentFact.consecutive,
    if (count != null) MomentFact.count,
    if (thresholds.length >= 2) MomentFact.thresholdList,
    if (jump case final run? when run.weeks > 1) MomentFact.run,
    if (placesDown != null) MomentFact.placesDown,
  };

  /// The chart, by name, for the rank in this story: the Sonus Hot 100 or
  /// Sonus Bubbling Under for songs, Sonus Albums & EPs for releases.
  String get chart => switch (chartType) {
    // SN-50 P-003/P-004 (refined stories only): a finished week is the
    // weekly chart, never "this week's", and a weekly #101–200 position is
    // never named as the Hot 100. Earlier stories keep their wording.
    ChartType.songs when weekly && (refined || polished) && bubblingUnder =>
      'the weekly Sonus Bubbling Under',
    ChartType.songs when weekly && (refined || polished) =>
      'the weekly Sonus Hot 100',
    ChartType.songs when weekly => "this week's Sonus Hot 100",
    ChartType.songs when bubblingUnder => 'Sonus Bubbling Under',
    ChartType.songs => 'the Sonus Hot 100',
    ChartType.albums when weekly && (refined || polished) =>
      'the weekly Sonus Albums & EPs chart',
    ChartType.albums when weekly => "this week's Sonus Albums & EPs chart",
    ChartType.albums => 'the Sonus Albums & EPs chart',
  };

  /// [chart] for SN-50 headlines: a finished week is the weekly chart,
  /// never "this week's" (F-Q24).
  String get scopedChart => switch (chartType) {
    ChartType.songs when weekly && bubblingUnder =>
      'the weekly Sonus Bubbling Under',
    ChartType.songs when weekly => 'the weekly Sonus Hot 100',
    ChartType.albums when weekly => 'the weekly Sonus Albums & EPs chart',
    _ => chart,
  };

  /// [thresholds] as a headline names them: "the Top 75, Top 50 and Top
  /// 40".
  String get thresholdList {
    final names = [for (final zone in thresholds) 'Top $zone'];
    if (names.length < 2) return 'the ${names.join()}';
    final head = names.sublist(0, names.length - 1).join(', ');
    return 'the $head and ${names.last}';
  }

  /// The chart's name to start a sentence or a label with.
  String get chartName => switch (chartType) {
    ChartType.songs when bubblingUnder => 'Sonus Bubbling Under',
    ChartType.songs => 'Sonus Hot 100',
    ChartType.albums => 'Sonus Albums & EPs',
  };

  /// "Single", "EP" or "album", for release stories; "release" while the
  /// format is unconfirmed.
  String get releaseWord => switch (format) {
    ReleaseFormat.single => 'single',
    ReleaseFormat.ep => 'EP',
    ReleaseFormat.album => 'album',
    null => 'release',
  };

  /// The story's subject as a headline names it: "Song" by Artist (feat.
  /// Guest), or Title by Artist for a release, or the artist's name.
  String get subject => switch (chartType) {
    ChartType.songs when polished && featuredArtists.isNotEmpty =>
      '"$title" by $artist featuring ${nameList(featuredArtists)}',
    ChartType.songs when featured != null =>
      '"$title" by $artist featuring $featured',
    ChartType.songs => '"$title" by $artist',
    ChartType.albums => '$title by $artist',
  };

  /// The song or release on its own: "Song" or Title.
  String get work => chartType == ChartType.songs ? '"$title"' : title;

  String get rivalWork =>
      chartType == ChartType.songs ? '"$rivalTitle"' : '$rivalTitle';

  String get rivalSubject => rivalArtist == null || rivalArtist!.isEmpty
      ? rivalWork
      : '$rivalWork by $rivalArtist';

  /// "1 stream", "25 streams".
  String get streamsText => streamCount(streams ?? 0);

  String get milestoneText => streamCount(milestone ?? 0);

  /// "100 times".
  String get milestoneTimes => '${_grouped(milestone ?? 0)} times';

  /// Where a longevity run is: "at #1", "in the Top 10" or "on the weekly
  /// chart".
  String get weeksPlace => switch (threshold) {
    null => 'on the weekly chart',
    1 => 'at #1',
    final zone => 'in the Top $zone',
  };

  /// The artist's ordinal as a word: "third".
  String get ordinalText => ordinalWord(ordinal ?? 1);

  /// [ordinalText] with its article: "a second", "an eighth", "an 11th".
  String get aOrdinalText => withArticle(ordinalText);

  /// [word] after "a" or "an", as it is said: "an eighth", "an 18th",
  /// "a 12th".
  static String withArticle(String word) {
    final lower = word.trim().toLowerCase();
    final digits = RegExp(r'^\d+').stringMatch(lower);
    final an = digits == null
        ? lower.isNotEmpty && 'aeio'.contains(lower[0])
        : digits.startsWith('8') || digits == '11' || digits == '18';
    return '${an ? 'an' : 'a'} $word';
  }

  /// "Victoria Justice's", for the credited artist.
  static String possessive(String name) => "$name's";

  static String streamCount(int count) =>
      '${_grouped(count)} ${count == 1 ? 'stream' : 'streams'}';

  static String _grouped(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// "first", "second", … "21st".
  static String ordinalWord(int value) {
    const words = [
      'first',
      'second',
      'third',
      'fourth',
      'fifth',
      'sixth',
      'seventh',
      'eighth',
      'ninth',
      'tenth',
    ];
    if (value >= 1 && value <= words.length) return words[value - 1];
    final mod100 = value % 100;
    final suffix = mod100 >= 11 && mod100 <= 13
        ? 'th'
        : switch (value % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return '$value$suffix';
  }

  /// "1 week", "5 weeks".
  static String weeksText(int weeks) => weeks == 1 ? '1 week' : '$weeks weeks';

  /// Builds the facts of [item]: every value from its recorded events,
  /// names and formats from [lookups].
  factory MomentFacts.of(
    ChartMomentFeedItem item,
    MomentLookups lookups, {
    bool refined = false,
    int? catalogVersion,
    bool polished = false,
    ChartJumpFacts? jump,
  }) {
    final dominant = item.events.firstWhere(
      (event) => event.eventType == item.dominantEventType,
    );
    ChartMomentEvent? find(bool Function(ChartMomentEvent) test) {
      for (final event in item.events) {
        if (test(event)) return event;
      }
      return null;
    }

    final career = find((e) => _careerTypes.contains(e.eventType));
    final rivalEvent = find((e) => e.relatedEntity != null);
    final entity = item.entity;
    final isArtistStory = _artistTypes.contains(item.dominantEventType);
    final songs = item.chartType == ChartType.songs && !isArtistStory;

    // A song's entity artist is the artist it counts for; its credit is
    // the artist name it was recorded with.
    final ownerId = entity.artistId;
    final ownerName = songs && ownerId != null
        ? lookups.artistName(ownerId)
        : null;
    final featured = songs ? lookups.featuredOf(entity.entityId) : const [];

    final milestone = find(
      (e) =>
          e.eventType == ChartMomentEventType.lifetimeStreamMilestone ||
          e.eventType == ChartMomentEventType.artistStreamMilestone,
    )?.milestoneValue;
    final weeksEvent = find((e) => _weeksTypes.contains(e.eventType));
    final topArtist = isArtistStory
        ? null
        : find(
            (e) => e.eventType == ChartMomentEventType.artistBecomesTopArtist,
          );

    return MomentFacts(
      chartType: isArtistStory ? ChartType.songs : item.chartType,
      weekly: item.scope == ChartMomentScope.finalized,
      title: entity.title,
      artist: entity.artistName,
      ownerName:
          ownerName == null ||
              ownerName.toLowerCase() == entity.artistName.toLowerCase()
          ? null
          : ownerName,
      album: songs ? entity.albumTitle : null,
      format: item.chartType == ChartType.albums && !isArtistStory
          ? lookups.formatOf(entity.entityId)
          : null,
      songRelease: songs ? lookups.songReleaseFormat(entity.entityId) : null,
      rank: dominant.currentRank,
      previousRank: dominant.previousRank,
      previousPeak: dominant.previousPeakRank,
      // A weekly chart's count is that week's streams, not a total.
      streams: item.scope == ChartMomentScope.finalized
          ? null
          : dominant.qualifiedStreamCount,
      milestone: milestone,
      ordinal: career?.milestoneValue,
      threshold: career?.threshold ?? dominant.threshold,
      weeks: weeksEvent?.milestoneValue,
      consecutive:
          weeksEvent != null &&
          _consecutiveTypes.contains(weeksEvent.eventType),
      count: find(
        (e) =>
            e.eventType ==
                ChartMomentEventType.artistSimultaneousThresholdSongs ||
            e.eventType ==
                ChartMomentEventType.artistSimultaneousThresholdAlbums,
      )?.milestoneValue,
      rivalTitle: rivalEvent?.relatedEntity?.title,
      // An artist rival is named on its own, never "Name by Name".
      rivalArtist: isArtistStory ? null : rivalEvent?.relatedEntity?.artistName,
      featured: featured.length == 1 ? featured.single : null,
      featuredArtists: songs && polished
          ? List.unmodifiable([
              for (final name in featured)
                if (name.trim().isNotEmpty) name.trim(),
            ])
          : const [],
      guests: songs && polished
          ? List.unmodifiable([
              for (final name in lookups.guestsOf(entity.entityId))
                if (name.trim().isNotEmpty) name.trim(),
            ])
          : const [],
      newTopArtist: topArtist?.entity.title,
      passedTopArtist: topArtist?.relatedEntity?.title,
      refined: refined,
      catalogVersion: catalogVersion,
      polished: polished,
      jump: jump,
      thresholds: refined ? _firstThresholds(item) : const [],
    );
  }

  static List<int> _firstThresholds(ChartMomentFeedItem item) {
    final zones = {
      for (final event in item.events)
        if (event.eventType == ChartMomentEventType.firstThresholdEntry &&
            event.threshold != null)
          event.threshold!,
    }.toList()..sort((a, b) => b.compareTo(a));
    return List.unmodifiable(zones);
  }

  static const Set<ChartMomentEventType> _careerTypes = {
    ChartMomentEventType.artistFirstNumberOneSong,
    ChartMomentEventType.artistNthNumberOneSong,
    ChartMomentEventType.artistFirstNumberOneAlbum,
    ChartMomentEventType.artistNthNumberOneAlbum,
    ChartMomentEventType.artistFirstThresholdSong,
    ChartMomentEventType.artistNthThresholdSong,
    ChartMomentEventType.artistFirstThresholdAlbum,
    ChartMomentEventType.artistNthThresholdAlbum,
  };

  static const Set<ChartMomentEventType> _artistTypes = {
    ChartMomentEventType.artistBecomesTopArtist,
    ChartMomentEventType.artistStreamMilestone,
  };

  static const Set<ChartMomentEventType> _consecutiveTypes = {
    ChartMomentEventType.consecutiveWeeksMilestone,
    ChartMomentEventType.consecutiveThresholdWeeksMilestone,
  };

  static const Set<ChartMomentEventType> _weeksTypes = {
    ChartMomentEventType.consecutiveWeeksMilestone,
    ChartMomentEventType.totalWeeksMilestone,
    ChartMomentEventType.consecutiveThresholdWeeksMilestone,
    ChartMomentEventType.totalThresholdWeeksMilestone,
  };
}
