import '../../../library/domain/entities/library_organization.dart';
import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/services/chart_ranking_engine.dart';

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

  /// A library artist with exactly this name, if there is one.
  String? artistIdNamed(String name);

  /// The cover of the song's release (or its own artwork).
  String? songCover(String songId);

  String? releaseCover(String albumId);

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

  /// The artist named for career facts: the owner when it differs.
  String get careerArtist => ownerName ?? artist;

  int? get places {
    final before = previousRank;
    final now = rank;
    return before == null || now == null || before <= now ? null : before - now;
  }

  bool get bubblingUnder =>
      chartType == ChartType.songs &&
      rank != null &&
      rank! > ChartRankingEngine.officialChartLimit;

  Set<MomentFact> get available => {
    if (previousRank != null) MomentFact.previousRank,
    if (previousPeak != null) MomentFact.previousPeak,
    if (streams != null && streams! > 0) MomentFact.streams,
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
  };

  /// The chart, by name, for the rank in this story: the Sonus Hot 100 or
  /// Sonus Bubbling Under for songs, Sonus Albums & EPs for releases.
  String get chart => switch (chartType) {
    ChartType.songs when weekly => "this week's Sonus Hot 100",
    ChartType.songs when bubblingUnder => 'Sonus Bubbling Under',
    ChartType.songs => 'the Sonus Hot 100',
    ChartType.albums when weekly => "this week's Sonus Albums & EPs chart",
    ChartType.albums => 'the Sonus Albums & EPs chart',
  };

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
  factory MomentFacts.of(ChartMomentFeedItem item, MomentLookups lookups) {
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
      newTopArtist: topArtist?.entity.title,
      passedTopArtist: topArtist?.relatedEntity?.title,
    );
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
