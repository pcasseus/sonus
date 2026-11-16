import '../../../library/domain/entities/library_organization.dart';
import '../../domain/moments/new_release_eligibility.dart';
import '../widgets/chart_extended_divider.dart';
import 'moment_facts.dart';
import 'moment_family.dart';

/// Proposed headlines for new-release debuts (App Update 1.3). DRAFT:
/// [approved] is false and nothing calls this from the editorial desk, so
/// no story is told with these words until they are approved.
///
/// Deterministic: one line per kind, built only from verified facts. A
/// headline never states an album ordinal ("fourth studio album"), a
/// "studio" classification, a certification or a gendered pronoun: Sonus
/// cannot prove them.
abstract final class NewReleaseDebutHeadlines {
  /// Fail-closed: the wording below is a proposal awaiting approval.
  static const bool approved = false;

  /// The debut stories a new-release headline would re-word in place
  /// (same story id, same family), so it is never a second story.
  static const Set<MomentFamily> replacesFamilies = {
    MomentFamily.songDebutNumberOne,
    MomentFamily.songDebutTop10,
    MomentFamily.songDebut,
    MomentFamily.songBubblingUnderDebut,
  };

  /// The chart a debut is on, by name, at its real position: "the Weekly
  /// Sonus Hot 100", "the Weekly Sonus Bubbling Under", "the Career Sonus
  /// Hot 100" or "the Career Sonus Bubbling Under".
  static String chartName(NewReleaseDebut debut) {
    final scope = debut.weekly ? 'Weekly' : 'Career';
    final zone = debut.bubblingUnder
        ? ChartZoneNames.bubblingUnder
        : ChartZoneNames.hot100;
    return 'the $scope $zone';
  }

  /// The headline for [debut]. [featured] are the song's featured artists
  /// in credit order, exactly as stored.
  static String headline(
    NewReleaseDebut debut, {
    List<String> featured = const [],
  }) {
    final title = debut.event.entity.title.trim();
    final artist = debut.event.entity.artistName.trim();
    final names = [
      for (final name in featured)
        if (name.trim().isNotEmpty) name.trim(),
    ];
    final featuring = names.isEmpty
        ? ''
        : ' featuring ${MomentFacts.nameList(names)}';
    final chart = chartName(debut);
    final rank = debut.rank;

    return switch (debut.kind) {
      NewReleaseDebutKind.single =>
        '$artist debuts new single "$title"$featuring on $chart at #$rank.',
      NewReleaseDebutKind.albumTrack =>
        '"$title" by $artist$featuring debuts at #$rank on $chart from the '
            'new ${_releaseWord(debut.albumFormat)} ${debut.albumTitle}.',
    };
  }

  static String _releaseWord(ReleaseFormat? format) =>
      format == ReleaseFormat.ep ? 'EP' : 'album';
}
