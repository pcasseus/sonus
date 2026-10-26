import 'moment_publisher.dart';
import 'moment_facts.dart';
import 'moment_family.dart';

/// One way to write a family's headline, in one publisher's voice.
///
/// [requires] lists every conditional fact the headline states. It is only
/// chosen when the story really has all of them, so a headline never
/// claims a previous rank, a dethroned #1 or a career count that did not
/// happen.
class HeadlineVariant {
  const HeadlineVariant(
    this.id,
    this.publisher,
    this.build, {
    this.requires = const {},
  });

  final String id;
  final MomentPublisher publisher;
  final String Function(MomentFacts f) build;
  final Set<MomentFact> requires;

  bool fits(MomentFacts facts) => facts.available.containsAll(requires);
}

const _d = MomentPublisher.sonusDaily;
const _p = MomentPublisher.pulsePop;

const _rank = {MomentFact.rank};
const _streams = {MomentFact.rank, MomentFact.streams};
const _rival = {MomentFact.rival};
const _previous = {MomentFact.rank, MomentFact.previousRank};
const _peak = {MomentFact.rank, MomentFact.previousPeak};
const _album = {MomentFact.rank, MomentFact.album};
const _places = {MomentFact.rank, MomentFact.places};
const _placesFrom = {
  MomentFact.rank,
  MomentFact.places,
  MomentFact.previousRank,
};
const _zone = {MomentFact.rank, MomentFact.threshold};
const _owner = {MomentFact.rank, MomentFact.owner};
const _ordinal = {MomentFact.rank, MomentFact.ordinal};
const _ordinalFrom = {
  MomentFact.rank,
  MomentFact.ordinal,
  MomentFact.previousRank,
};
const _ordinalStreams = {
  MomentFact.rank,
  MomentFact.ordinal,
  MomentFact.streams,
};
const _ordinalRival = {MomentFact.ordinal, MomentFact.rival};
const _weeks = {MomentFact.weeks};
const _run = {MomentFact.weeks, MomentFact.consecutive};
const _count = {MomentFact.count, MomentFact.threshold};

String _p1(MomentFacts f) => MomentFacts.possessive(f.artist);
String _pc(MomentFacts f) => MomentFacts.possessive(f.careerArtist);

/// The editorial library (SN-45): twelve headlines for every story family,
/// six in the Sonus Daily voice (polished, factual) and six in the PulsePop
/// voice (energetic, conversational). Both voices state the same facts.
abstract final class MomentHeadlines {
  static List<HeadlineVariant> of(MomentFamily family) => _library[family]!;

  static Iterable<MomentFamily> get families => _library.keys;

  static final Map<MomentFamily, List<HeadlineVariant>> _library = {
    // Songs ---------------------------------------------------------------

    MomentFamily.songDebutNumberOne: [
      HeadlineVariant(
        'song-debut-1-d1',
        _d,
        (f) => '${f.subject} debuts at #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'song-debut-1-d2',
        _d,
        (f) => '${f.subject} enters ${f.chart} at #1.',
      ),
      HeadlineVariant(
        'song-debut-1-d3',
        _d,
        (f) => '${f.subject} debuts at #1 on ${f.chart} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-debut-1-d4',
        _d,
        (f) =>
            '${f.subject} debuts at #1, taking the top position from '
            '${f.rivalSubject}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'song-debut-1-d5',
        _d,
        (f) => '${f.work} from ${f.album} debuts at #1 on ${f.chart}.',
        requires: _album,
      ),
      HeadlineVariant(
        'song-debut-1-d6',
        _d,
        (f) => '${f.artist} opens at #1 on ${f.chart} with ${f.work}.',
      ),
      HeadlineVariant(
        'song-debut-1-p1',
        _p,
        (f) =>
            'Straight in at #1! ${f.subject} debuts at the very top of '
            '${f.chart}.',
      ),
      HeadlineVariant(
        'song-debut-1-p2',
        _p,
        (f) => 'No warm-up needed: ${f.subject} lands at #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'song-debut-1-p3',
        _p,
        (f) => '${f.artist} goes straight to #1 with ${f.work}.',
      ),
      HeadlineVariant(
        'song-debut-1-p4',
        _p,
        (f) =>
            '${f.work} by ${f.artist} debuts at #1 with ${f.streamsText} to '
            'its name.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-debut-1-p5',
        _p,
        (f) =>
            '${f.work} debuts at #1 and knocks ${f.rivalSubject} out of the '
            'top spot.',
        requires: _rival,
      ),
      HeadlineVariant(
        'song-debut-1-p6',
        _p,
        (f) => 'A #1 debut: ${f.subject} arrives at the top of ${f.chart}.',
      ),
    ],

    MomentFamily.songDebutTop10: [
      HeadlineVariant(
        'song-debut-10-d1',
        _d,
        (f) => '${f.subject} debuts at #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-10-d2',
        _d,
        (f) => '${f.subject} enters ${f.chart} at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-10-d3',
        _d,
        (f) =>
            '${f.subject} debuts at #${f.rank} on ${f.chart} with '
            '${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-debut-10-d4',
        _d,
        (f) =>
            '${f.subject} opens inside the Top 10 at #${f.rank} on '
            '${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-10-d5',
        _d,
        (f) => '${f.work} from ${f.album} debuts at #${f.rank} on ${f.chart}.',
        requires: _album,
      ),
      HeadlineVariant(
        'song-debut-10-d6',
        _d,
        (f) =>
            '${f.artist} debuts in the Top 10 as ${f.work} enters at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-10-p1',
        _p,
        (f) => 'Top 10 debut! ${f.subject} lands at #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-10-p2',
        _p,
        (f) => '${f.work} wastes no time: ${f.artist} debuts at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-10-p3',
        _p,
        (f) => 'Straight into the Top 10: ${f.subject} enters at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-10-p4',
        _p,
        (f) => '${f.subject} debuts at #${f.rank} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-debut-10-p5',
        _p,
        (f) =>
            '${f.artist} arrives at #${f.rank} on ${f.chart} with ${f.work}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-10-p6',
        _p,
        (f) =>
            'New in the Top 10: ${f.work} by ${f.artist} debuts at '
            '#${f.rank}.',
        requires: _rank,
      ),
    ],

    MomentFamily.songDebut: [
      HeadlineVariant(
        'song-debut-d1',
        _d,
        (f) => '${f.subject} debuts at #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-d2',
        _d,
        (f) => '${f.subject} enters ${f.chart} at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-d3',
        _d,
        (f) =>
            '${f.subject} debuts at #${f.rank} on ${f.chart} with '
            '${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-debut-d4',
        _d,
        (f) => '${f.work} from ${f.album} debuts at #${f.rank} on ${f.chart}.',
        requires: _album,
      ),
      HeadlineVariant(
        'song-debut-d5',
        _d,
        (f) =>
            '${f.artist} adds a new entry as ${f.work} debuts at #${f.rank} '
            'on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-d6',
        _d,
        (f) => 'New on ${f.chart}: ${f.subject} enters at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-p1',
        _p,
        (f) => 'Fresh entry! ${f.subject} debuts at #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-p2',
        _p,
        (f) => '${f.work} by ${f.artist} joins ${f.chart} at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-p3',
        _p,
        (f) => '${f.artist} lands a new entry: ${f.work} debuts at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-p4',
        _p,
        (f) =>
            'Just in: ${f.subject} debuts at #${f.rank} with '
            '${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-debut-p5',
        _p,
        (f) => 'Say hello to ${f.work}: ${_p1(f)} song debuts at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-debut-p6',
        _p,
        (f) => '${f.subject} makes its debut at #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
    ],

    MomentFamily.songBubblingUnderDebut: [
      HeadlineVariant(
        'song-bu-debut-d1',
        _d,
        (f) => '${f.subject} debuts at #${f.rank} on Sonus Bubbling Under.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-bu-debut-d2',
        _d,
        (f) => '${f.subject} enters Sonus Bubbling Under at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-bu-debut-d3',
        _d,
        (f) =>
            '${f.subject} debuts at #${f.rank} on Sonus Bubbling Under with '
            '${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-bu-debut-d4',
        _d,
        (f) =>
            '${f.work} from ${f.album} debuts at #${f.rank} on Sonus '
            'Bubbling Under.',
        requires: _album,
      ),
      HeadlineVariant(
        'song-bu-debut-d5',
        _d,
        (f) => '${f.subject} starts out at #${f.rank} on Sonus Bubbling Under.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-bu-debut-d6',
        _d,
        (f) =>
            'New on Sonus Bubbling Under: ${f.subject} enters at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-bu-debut-p1',
        _p,
        (f) =>
            'Watch this one: ${f.subject} debuts at #${f.rank} on Sonus '
            'Bubbling Under.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-bu-debut-p2',
        _p,
        (f) =>
            '${f.work} by ${f.artist} joins Sonus Bubbling Under at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-bu-debut-p3',
        _p,
        (f) =>
            '${f.artist} lands on Sonus Bubbling Under as ${f.work} debuts at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-bu-debut-p4',
        _p,
        (f) =>
            'Just in: ${f.subject} debuts at #${f.rank} on Sonus Bubbling '
            'Under with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-bu-debut-p5',
        _p,
        (f) =>
            '${f.work} by ${f.artist} starts at #${f.rank} on Sonus Bubbling '
            'Under.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-bu-debut-p6',
        _p,
        (f) =>
            'First steps: ${f.subject} debuts at #${f.rank} on Sonus '
            'Bubbling Under.',
        requires: _rank,
      ),
    ],

    MomentFamily.songHot100Breakthrough: [
      HeadlineVariant(
        'song-break-d1',
        _d,
        (f) => '${f.subject} enters the Sonus Hot 100 at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-break-d2',
        _d,
        (f) =>
            '${f.subject} climbs from #${f.previousRank} on Sonus Bubbling '
            'Under to #${f.rank} on the Sonus Hot 100.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-break-d3',
        _d,
        (f) => '${f.subject} breaks into the Sonus Hot 100 at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-break-d4',
        _d,
        (f) =>
            '${f.subject} reaches the Sonus Hot 100 at #${f.rank} with '
            '${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-break-d5',
        _d,
        (f) =>
            '${f.work} by ${f.artist} moves up from Sonus Bubbling Under to '
            '#${f.rank} on the Sonus Hot 100.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-break-d6',
        _d,
        (f) =>
            'From Sonus Bubbling Under to the Sonus Hot 100: ${f.subject} '
            'rises to #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-break-p1',
        _p,
        (f) =>
            'Breakthrough! ${f.subject} enters the Sonus Hot 100 at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-break-p2',
        _p,
        (f) =>
            '${f.work} graduates from Sonus Bubbling Under, landing at '
            '#${f.rank} on the Sonus Hot 100.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-break-p3',
        _p,
        (f) =>
            '${f.work} jumps from #${f.previousRank} to #${f.rank}, into the '
            'Sonus Hot 100.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-break-p4',
        _p,
        (f) =>
            '${f.artist} cracks the Sonus Hot 100 as ${f.work} rises to '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-break-p5',
        _p,
        (f) =>
            '${f.streamsText} in, ${f.subject} is in the Sonus Hot 100 at '
            '#${f.rank}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-break-p6',
        _p,
        (f) =>
            'Welcome to the Sonus Hot 100: ${f.subject} enters at '
            '#${f.rank}.',
        requires: _rank,
      ),
    ],

    MomentFamily.songFirstNumberOne: [
      HeadlineVariant(
        'song-1-d1',
        _d,
        (f) => '${f.subject} reaches #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'song-1-d2',
        _d,
        (f) => '${f.subject} reaches #1 on ${f.chart} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-1-d3',
        _d,
        (f) =>
            '${f.subject} rises from #${f.previousRank} to #1 on ${f.chart}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-1-d4',
        _d,
        (f) => '${f.subject} replaces ${f.rivalSubject} at #1 on ${f.chart}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'song-1-d5',
        _d,
        (f) => '${f.subject} becomes the new #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'song-1-d6',
        _d,
        (f) =>
            '${f.subject} reaches #1 for the first time, beating its previous '
            'peak of #${f.previousPeak}.',
        requires: _peak,
      ),
      HeadlineVariant(
        'song-1-p1',
        _p,
        (f) => '${f.work} is #1! ${f.artist} tops ${f.chart}.',
      ),
      HeadlineVariant(
        'song-1-p2',
        _p,
        (f) => '${f.work} dethrones ${f.rivalSubject} to reach #1.',
        requires: _rival,
      ),
      HeadlineVariant(
        'song-1-p3',
        _p,
        (f) => '${f.work} jumps from #${f.previousRank} to #1 on ${f.chart}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-1-p4',
        _p,
        (f) => '${f.subject} reaches #1 with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-1-p5',
        _p,
        (f) => 'New #1 alert: ${f.subject} takes the top spot on ${f.chart}.',
      ),
      HeadlineVariant(
        'song-1-p6',
        _p,
        (f) => '${f.artist} has the #1 song on ${f.chart} with ${f.work}.',
      ),
    ],

    MomentFamily.songReturnsToNumberOne: [
      HeadlineVariant(
        'song-1-again-d1',
        _d,
        (f) => '${f.subject} returns to #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'song-1-again-d2',
        _d,
        (f) =>
            '${f.subject} returns to #1 on ${f.chart} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-1-again-d3',
        _d,
        (f) => '${f.subject} takes #1 back from ${f.rivalSubject}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'song-1-again-d4',
        _d,
        (f) =>
            '${f.subject} climbs from #${f.previousRank} back to #1 on '
            '${f.chart}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-1-again-d5',
        _d,
        (f) => '${f.subject} is #1 again on ${f.chart}.',
      ),
      HeadlineVariant(
        'song-1-again-d6',
        _d,
        (f) => '${f.work} regains #1 on ${f.chart} for ${f.artist}.',
      ),
      HeadlineVariant(
        'song-1-again-p1',
        _p,
        (f) => 'Back at #1! ${f.subject} reclaims the top spot.',
      ),
      HeadlineVariant(
        'song-1-again-p2',
        _p,
        (f) => '${f.work} retakes #1 from ${f.rivalSubject}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'song-1-again-p3',
        _p,
        (f) => '${f.artist} is back on top: ${f.work} returns to #1.',
      ),
      HeadlineVariant(
        'song-1-again-p4',
        _p,
        (f) => '${f.work} returns to #1 with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-1-again-p5',
        _p,
        (f) => 'Once more at #1: ${f.subject} heads ${f.chart} again.',
      ),
      HeadlineVariant(
        'song-1-again-p6',
        _p,
        (f) => '${f.work} bounces from #${f.previousRank} back to #1.',
        requires: _previous,
      ),
    ],

    MomentFamily.songNewPeak: [
      HeadlineVariant(
        'song-peak-d1',
        _d,
        (f) => '${f.subject} reaches a new peak of #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-peak-d2',
        _d,
        (f) =>
            '${f.subject} climbs to a new peak of #${f.rank}, up from its '
            'previous best of #${f.previousPeak}.',
        requires: _peak,
      ),
      HeadlineVariant(
        'song-peak-d3',
        _d,
        (f) =>
            '${f.subject} rises to #${f.rank}, its highest position yet on '
            '${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-peak-d4',
        _d,
        (f) =>
            '${f.subject} enters the Top ${f.threshold} at #${f.rank} on '
            '${f.chart}.',
        requires: _zone,
      ),
      HeadlineVariant(
        'song-peak-d5',
        _d,
        (f) =>
            '${f.subject} hits a new peak of #${f.rank} with '
            '${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-peak-d6',
        _d,
        (f) =>
            '${f.subject} moves from #${f.previousRank} to a new peak of '
            '#${f.rank}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-peak-p1',
        _p,
        (f) => 'New peak! ${f.subject} climbs to #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-peak-p2',
        _p,
        (f) =>
            'Top ${f.threshold} unlocked: ${f.work} by ${f.artist} reaches '
            '#${f.rank}.',
        requires: _zone,
      ),
      HeadlineVariant(
        'song-peak-p3',
        _p,
        (f) => '${f.work} climbs to a new high of #${f.rank} for ${f.artist}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-peak-p4',
        _p,
        (f) =>
            '${f.work} beats its old best of #${f.previousPeak} and peaks at '
            '#${f.rank}.',
        requires: _peak,
      ),
      HeadlineVariant(
        'song-peak-p5',
        _p,
        (f) =>
            '${f.subject} reaches #${f.rank} with ${f.streamsText}, a new '
            'peak.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-peak-p6',
        _p,
        (f) => '${f.artist} sees ${f.work} rise to a new peak of #${f.rank}.',
        requires: _rank,
      ),
    ],

    MomentFamily.songPeakMatch: [
      HeadlineVariant(
        'song-repeak-d1',
        _d,
        (f) => '${f.subject} returns to its peak of #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-repeak-d2',
        _d,
        (f) =>
            '${f.subject} matches its best position, #${f.rank}, on '
            '${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-repeak-d3',
        _d,
        (f) =>
            '${f.subject} climbs from #${f.previousRank} back to its '
            '#${f.rank} peak.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-repeak-d4',
        _d,
        (f) =>
            '${f.subject} is back at #${f.rank}, its highest position so far.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-repeak-d5',
        _d,
        (f) =>
            '${f.work} by ${f.artist} equals its #${f.rank} peak on '
            '${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-repeak-d6',
        _d,
        (f) =>
            '${f.work} returns to #${f.rank} for ${f.artist}, matching its '
            'peak.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-repeak-p1',
        _p,
        (f) => 'Back at the peak! ${f.subject} returns to #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-repeak-p2',
        _p,
        (f) => '${f.work} hits #${f.rank} again, tying its best.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-repeak-p3',
        _p,
        (f) =>
            '${f.work} jumps from #${f.previousRank} back to its #${f.rank} '
            'high.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-repeak-p4',
        _p,
        (f) => 'Peak repeat: ${f.subject} is #${f.rank} once more.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-repeak-p5',
        _p,
        (f) =>
            '${f.artist} gets ${f.work} back to its #${f.rank} high on '
            '${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-repeak-p6',
        _p,
        (f) => 'Same peak, new week: ${f.work} returns to #${f.rank}.',
        requires: _rank,
      ),
    ],

    MomentFamily.songBigClimb: [
      HeadlineVariant(
        'song-climb-d1',
        _d,
        (f) =>
            '${f.subject} climbs ${f.places} places to #${f.rank} on '
            '${f.chart}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-climb-d2',
        _d,
        (f) =>
            '${f.subject} rises from #${f.previousRank} to #${f.rank} on '
            '${f.chart}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-climb-d3',
        _d,
        (f) => '${f.subject} jumps ${f.places} spots to #${f.rank}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-climb-d4',
        _d,
        (f) => '${f.subject} climbs to #${f.rank} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-climb-d5',
        _d,
        (f) =>
            '${f.work} by ${f.artist} gains ${f.places} places, rising to '
            '#${f.rank}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-climb-d6',
        _d,
        (f) =>
            '${f.subject} moves up ${f.places} places, from '
            '#${f.previousRank} to #${f.rank}.',
        requires: _placesFrom,
      ),
      HeadlineVariant(
        'song-climb-p1',
        _p,
        (f) => 'Big move! ${f.subject} jumps ${f.places} spots to #${f.rank}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-climb-p2',
        _p,
        (f) => '${f.work} rockets from #${f.previousRank} to #${f.rank}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-climb-p3',
        _p,
        (f) =>
            '${f.artist} on the rise: ${f.work} climbs ${f.places} places to '
            '#${f.rank}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-climb-p4',
        _p,
        (f) =>
            'Up ${f.places}! ${f.subject} lands at #${f.rank} on ${f.chart}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-climb-p5',
        _p,
        (f) => '${f.work} surges to #${f.rank} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-climb-p6',
        _p,
        (f) =>
            'From #${f.previousRank} to #${f.rank}: ${f.subject} makes a big '
            'climb.',
        requires: _previous,
      ),
    ],

    MomentFamily.songBiggestGainer: [
      HeadlineVariant(
        'song-gainer-d1',
        _d,
        (f) =>
            '${f.subject} is the biggest gainer on ${f.chart}, up ${f.places} '
            'places to #${f.rank}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-gainer-d2',
        _d,
        (f) =>
            "${f.subject} makes the week's biggest climb, from "
            '#${f.previousRank} to #${f.rank}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-gainer-d3',
        _d,
        (f) =>
            "The week's biggest gainer: ${f.subject} rises ${f.places} places "
            'to #${f.rank}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-gainer-d4',
        _d,
        (f) =>
            '${f.subject} posts the largest climb on ${f.chart}, gaining '
            '${f.places} places.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-gainer-d5',
        _d,
        (f) =>
            '${f.work} by ${f.artist} climbs from #${f.previousRank} to '
            '#${f.rank}, the biggest move of the week.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-gainer-d6',
        _d,
        (f) =>
            'No song climbs further this week than ${f.subject}, up '
            '${f.places} places to #${f.rank}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-gainer-p1',
        _p,
        (f) =>
            'Biggest gainer! ${f.subject} jumps ${f.places} spots to '
            '#${f.rank}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-gainer-p2',
        _p,
        (f) =>
            '${f.work} flies from #${f.previousRank} to #${f.rank}, the '
            "week's biggest jump.",
        requires: _previous,
      ),
      HeadlineVariant(
        'song-gainer-p3',
        _p,
        (f) =>
            "${f.artist} owns the week's biggest climb: ${f.work} is up "
            '${f.places} to #${f.rank}.',
        requires: _places,
      ),
      HeadlineVariant(
        'song-gainer-p4',
        _p,
        (f) => "Up ${f.places} places! ${f.subject} is the week's top gainer.",
        requires: _places,
      ),
      HeadlineVariant(
        'song-gainer-p5',
        _p,
        (f) =>
            "Week's best move: ${f.work} goes from #${f.previousRank} to "
            '#${f.rank}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'song-gainer-p6',
        _p,
        (f) =>
            '${f.work} leads every climber this week, rising ${f.places} '
            'places to #${f.rank}.',
        requires: _places,
      ),
    ],

    MomentFamily.songReentry: [
      HeadlineVariant(
        'song-reentry-d1',
        _d,
        (f) => '${f.subject} re-enters ${f.chart} at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-reentry-d2',
        _d,
        (f) => '${f.subject} returns to ${f.chart} at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-reentry-d3',
        _d,
        (f) =>
            '${f.subject} re-enters ${f.chart} at #${f.rank} with '
            '${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-reentry-d4',
        _d,
        (f) =>
            '${f.subject} returns at #${f.rank}; it previously peaked at '
            '#${f.previousPeak}.',
        requires: _peak,
      ),
      HeadlineVariant(
        'song-reentry-d5',
        _d,
        (f) => '${f.work} by ${f.artist} is back on ${f.chart} at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-reentry-d6',
        _d,
        (f) =>
            '${f.artist} returns to ${f.chart} as ${f.work} re-enters at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-reentry-p1',
        _p,
        (f) => "It's back! ${f.subject} re-enters at #${f.rank}.",
        requires: _rank,
      ),
      HeadlineVariant(
        'song-reentry-p2',
        _p,
        (f) => '${f.work} makes a comeback at #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-reentry-p3',
        _p,
        (f) => 'Return trip: ${f.subject} is back at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-reentry-p4',
        _p,
        (f) => '${f.work} returns at #${f.rank} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'song-reentry-p5',
        _p,
        (f) =>
            'Once a #${f.previousPeak} peak, ${f.work} is back at #${f.rank}.',
        requires: _peak,
      ),
      HeadlineVariant(
        'song-reentry-p6',
        _p,
        (f) =>
            '${f.artist} is back: ${f.work} re-enters ${f.chart} at '
            '#${f.rank}.',
        requires: _rank,
      ),
    ],

    MomentFamily.songStreamMilestone: [
      HeadlineVariant(
        'song-streams-d1',
        _d,
        (f) => '${f.subject} reaches ${f.milestoneText} on Sonus.',
      ),
      HeadlineVariant(
        'song-streams-d2',
        _d,
        (f) => '${f.subject} hits ${f.milestoneText}.',
      ),
      HeadlineVariant(
        'song-streams-d3',
        _d,
        (f) =>
            '${f.subject} reaches ${f.milestoneText} and stands at '
            '#${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-streams-d4',
        _d,
        (f) =>
            '${f.work} by ${f.artist} has now been played '
            '${f.milestoneTimes} on Sonus.',
      ),
      HeadlineVariant(
        'song-streams-d5',
        _d,
        (f) =>
            'A milestone for ${f.artist}: ${f.work} reaches '
            '${f.milestoneText}.',
      ),
      HeadlineVariant(
        'song-streams-d6',
        _d,
        (f) => '${f.subject} crosses ${f.milestoneText}.',
      ),
      HeadlineVariant(
        'song-streams-p1',
        _p,
        (f) => '${f.milestoneText}! ${f.subject} hits a streaming milestone.',
      ),
      HeadlineVariant(
        'song-streams-p2',
        _p,
        (f) => '${f.work} just reached ${f.milestoneText} on Sonus.',
      ),
      HeadlineVariant(
        'song-streams-p3',
        _p,
        (f) => '${f.artist} celebrates ${f.milestoneText} for ${f.work}.',
      ),
      HeadlineVariant(
        'song-streams-p4',
        _p,
        (f) =>
            '${f.work} reaches ${f.milestoneText} while sitting at '
            '#${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'song-streams-p5',
        _p,
        (f) => 'Milestone unlocked: ${f.subject} reaches ${f.milestoneText}.',
      ),
      HeadlineVariant(
        'song-streams-p6',
        _p,
        (f) =>
            'Play count check: ${f.work} by ${f.artist} is now at '
            '${f.milestoneText}.',
      ),
    ],

    MomentFamily.songWeeksMilestone: _weeksVariants('song'),

    // Artists -------------------------------------------------------------
    MomentFamily.artistFirstHot100: [
      HeadlineVariant(
        'artist-hot100-d1',
        _d,
        (f) =>
            '${f.careerArtist} earns a first Sonus Hot 100 entry as '
            '${f.work} reaches #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-hot100-d2',
        _d,
        (f) =>
            '${f.work} gives ${f.careerArtist} a first entry on the Sonus Hot '
            '100, at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-hot100-d3',
        _d,
        (f) =>
            '${f.careerArtist} reaches the Sonus Hot 100 for the first time '
            'with ${f.work} at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-hot100-d4',
        _d,
        (f) =>
            '${f.work} puts ${f.careerArtist} on the Sonus Hot 100 at '
            '#${f.rank} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'artist-hot100-d5',
        _d,
        (f) =>
            '${f.work} by ${f.artist} gives ${f.ownerName} its first Sonus '
            'Hot 100 entry, at #${f.rank}.',
        requires: _owner,
      ),
      HeadlineVariant(
        'artist-hot100-d6',
        _d,
        (f) =>
            'First Sonus Hot 100 entry for ${f.careerArtist}: ${f.work} lands '
            'at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-hot100-p1',
        _p,
        (f) =>
            'Welcome, ${f.careerArtist}! ${f.work} is a first Sonus Hot 100 '
            'entry at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-hot100-p2',
        _p,
        (f) =>
            '${f.careerArtist} is on the board: ${f.work} enters the Sonus '
            'Hot 100 at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-hot100-p3',
        _p,
        (f) =>
            'A first for ${f.careerArtist}: ${f.work} reaches #${f.rank} on '
            'the Sonus Hot 100.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-hot100-p4',
        _p,
        (f) =>
            '${f.careerArtist} cracks the Sonus Hot 100 for the first time '
            'as ${f.work} reaches ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'artist-hot100-p5',
        _p,
        (f) => "${f.work} opens ${_pc(f)} Sonus Hot 100 account at #${f.rank}.",
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-hot100-p6',
        _p,
        (f) =>
            '${f.artist} puts ${f.ownerName} on the Sonus Hot 100 for the '
            'first time with ${f.work}.',
        requires: _owner,
      ),
    ],

    MomentFamily.artistFirstTop10: [
      HeadlineVariant(
        'artist-top10-d1',
        _d,
        (f) =>
            '${f.careerArtist} earns a first Top 10 hit as ${f.work} reaches '
            '#${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-top10-d2',
        _d,
        (f) =>
            '${f.work} gives ${f.careerArtist} a first Top 10 hit on '
            '${f.chart}, at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-top10-d3',
        _d,
        (f) =>
            '${f.work} climbs from #${f.previousRank} to #${f.rank}, a first '
            'Top 10 hit for ${f.careerArtist}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'artist-top10-d4',
        _d,
        (f) =>
            '${f.careerArtist} reaches the Top 10 for the first time: '
            '${f.work} is #${f.rank} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'artist-top10-d5',
        _d,
        (f) =>
            '${f.work} by ${f.artist} brings ${f.ownerName} into the Top 10 '
            'for the first time, at #${f.rank}.',
        requires: _owner,
      ),
      HeadlineVariant(
        'artist-top10-d6',
        _d,
        (f) =>
            'First Top 10 hit for ${f.careerArtist}: ${f.work} reaches '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-top10-p1',
        _p,
        (f) =>
            '${f.careerArtist} scores a first Top 10 hit! ${f.work} reaches '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-top10-p2',
        _p,
        (f) =>
            '${f.careerArtist} joins the Top 10 club with ${f.work} at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-top10-p3',
        _p,
        (f) =>
            '${f.work} jumps from #${f.previousRank} to #${f.rank} and hands '
            '${f.careerArtist} a first Top 10 hit.',
        requires: _previous,
      ),
      HeadlineVariant(
        'artist-top10-p4',
        _p,
        (f) =>
            'A first Top 10 for ${f.careerArtist}: ${f.work} lands at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'artist-top10-p5',
        _p,
        (f) =>
            '${f.work} takes ${f.careerArtist} into the Top 10 for the first '
            'time with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'artist-top10-p6',
        _p,
        (f) =>
            '${f.careerArtist} breaks into the Top 10 as ${f.work} reaches '
            '#${f.rank}.',
        requires: _rank,
      ),
    ],

    MomentFamily.artistNthTop10: [
      HeadlineVariant(
        'artist-top10-n-d1',
        _d,
        (f) =>
            '${f.careerArtist} earns ${f.aOrdinalText} Top 10 hit as '
            '${f.work} reaches #${f.rank}.',
        requires: _ordinal,
      ),
      HeadlineVariant(
        'artist-top10-n-d2',
        _d,
        (f) =>
            '${f.work} becomes ${_pc(f)} ${f.ordinalText} Top 10 hit on '
            '${f.chart}.',
        requires: _ordinal,
      ),
      HeadlineVariant(
        'artist-top10-n-d3',
        _d,
        (f) =>
            '${f.work} climbs from #${f.previousRank} to #${f.rank}, '
            '${_pc(f)} ${f.ordinalText} Top 10 hit.',
        requires: _ordinalFrom,
      ),
      HeadlineVariant(
        'artist-top10-n-d4',
        _d,
        (f) =>
            '${f.careerArtist} adds ${f.aOrdinalText} Top 10 hit: ${f.work} '
            'is #${f.rank} on ${f.chart}.',
        requires: _ordinal,
      ),
      HeadlineVariant(
        'artist-top10-n-d5',
        _d,
        (f) =>
            '${f.work} reaches #${f.rank} with ${f.streamsText}, '
            '${f.aOrdinalText} Top 10 hit for ${f.careerArtist}.',
        requires: _ordinalStreams,
      ),
      HeadlineVariant(
        'artist-top10-n-d6',
        _d,
        (f) =>
            '${f.careerArtist} now has ${f.ordinal} Top 10 hits on '
            '${f.chart} after ${f.work} reaches #${f.rank}.',
        requires: _ordinal,
      ),
      HeadlineVariant(
        'artist-top10-n-p1',
        _p,
        (f) =>
            'Top 10 hit number ${f.ordinal} for ${f.careerArtist}! ${f.work} '
            'reaches #${f.rank}.',
        requires: _ordinal,
      ),
      HeadlineVariant(
        'artist-top10-n-p2',
        _p,
        (f) =>
            '${f.careerArtist} keeps the hits coming: ${f.work} is '
            '${f.aOrdinalText} Top 10 hit.',
        requires: _ordinal,
      ),
      HeadlineVariant(
        'artist-top10-n-p3',
        _p,
        (f) =>
            '${f.work} leaps from #${f.previousRank} to #${f.rank}, Top 10 '
            'hit No. ${f.ordinal} for ${f.careerArtist}.',
        requires: _ordinalFrom,
      ),
      HeadlineVariant(
        'artist-top10-n-p4',
        _p,
        (f) =>
            '${f.ordinal} and counting: ${f.careerArtist} lands another Top '
            '10 hit with ${f.work}.',
        requires: _ordinal,
      ),
      HeadlineVariant(
        'artist-top10-n-p5',
        _p,
        (f) =>
            '${f.work} reaches #${f.rank} with ${f.streamsText} and becomes '
            '${_pc(f)} ${f.ordinalText} Top 10 hit.',
        requires: _ordinalStreams,
      ),
      HeadlineVariant(
        'artist-top10-n-p6',
        _p,
        (f) =>
            '${f.careerArtist} collects ${f.aOrdinalText} Top 10 hit as '
            '${f.work} reaches #${f.rank}.',
        requires: _ordinal,
      ),
    ],

    MomentFamily.artistFirstNumberOne: [
      HeadlineVariant(
        'artist-1-d1',
        _d,
        (f) =>
            '${f.careerArtist} earns a first #1 hit as ${f.work} reaches #1 '
            'on ${f.chart}.',
      ),
      HeadlineVariant(
        'artist-1-d2',
        _d,
        (f) => '${f.work} gives ${f.careerArtist} a first #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'artist-1-d3',
        _d,
        (f) =>
            '${f.work} replaces ${f.rivalSubject} at #1, giving '
            '${f.careerArtist} a first #1 hit.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-1-d4',
        _d,
        (f) =>
            '${f.work} rises from #${f.previousRank} to #1, a first #1 hit '
            'for ${f.careerArtist}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'artist-1-d5',
        _d,
        (f) =>
            '${f.careerArtist} scores a first #1 on ${f.chart} as ${f.work} '
            'reaches #1 with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'artist-1-d6',
        _d,
        (f) =>
            '${f.work} by ${f.artist} gives ${f.ownerName} its first #1 on '
            '${f.chart}.',
        requires: _owner,
      ),
      HeadlineVariant(
        'artist-1-p1',
        _p,
        (f) => '${f.careerArtist} scores a first #1 hit! ${f.work} reaches #1.',
      ),
      HeadlineVariant(
        'artist-1-p2',
        _p,
        (f) =>
            '${f.work} dethrones ${f.rivalSubject} and hands '
            '${f.careerArtist} a first #1.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-1-p3',
        _p,
        (f) =>
            'First #1 for ${f.careerArtist}: ${f.work} is the new #1 on '
            '${f.chart}.',
      ),
      HeadlineVariant(
        'artist-1-p4',
        _p,
        (f) =>
            '${f.work} jumps from #${f.previousRank} to #1, and '
            '${f.careerArtist} has a first #1 hit.',
        requires: _previous,
      ),
      HeadlineVariant(
        'artist-1-p5',
        _p,
        (f) =>
            '${f.work} reaches #1 with ${f.streamsText}: a first #1 for '
            '${f.careerArtist}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'artist-1-p6',
        _p,
        (f) =>
            'A first #1 for ${f.careerArtist}! ${f.work} leads ${f.chart} at '
            '#1.',
      ),
    ],

    MomentFamily.artistNthNumberOne: [
      HeadlineVariant(
        'artist-1-n-d1',
        _d,
        (f) =>
            '${f.careerArtist} earns ${f.aOrdinalText} #1 hit as ${f.work} '
            'reaches #1 on ${f.chart}.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-1-n-d2',
        _d,
        (f) => '${f.work} becomes ${_pc(f)} ${f.ordinalText} #1 on ${f.chart}.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-1-n-d3',
        _d,
        (f) =>
            '${f.work} replaces ${f.rivalSubject} at #1, ${_pc(f)} '
            '${f.ordinalText} #1 hit.',
        requires: _ordinalRival,
      ),
      HeadlineVariant(
        'artist-1-n-d4',
        _d,
        (f) =>
            '${f.work} rises from #${f.previousRank} to #1, '
            '${f.aOrdinalText} #1 hit for ${f.careerArtist}.',
        requires: _ordinalFrom,
      ),
      HeadlineVariant(
        'artist-1-n-d5',
        _d,
        (f) =>
            '${f.careerArtist} now has ${f.ordinal} #1 hits on ${f.chart} '
            'after ${f.work} reaches #1.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-1-n-d6',
        _d,
        (f) =>
            '${f.work} reaches #1 with ${f.streamsText}, ${_pc(f)} '
            '${f.ordinalText} #1 hit.',
        requires: _ordinalStreams,
      ),
      HeadlineVariant(
        'artist-1-n-p1',
        _p,
        (f) =>
            '${f.careerArtist} does it again: ${f.work} is '
            '${f.aOrdinalText} #1 hit.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-1-n-p2',
        _p,
        (f) =>
            '${f.work} dethrones ${f.rivalSubject} for ${_pc(f)} '
            '${f.ordinalText} #1.',
        requires: _ordinalRival,
      ),
      HeadlineVariant(
        'artist-1-n-p3',
        _p,
        (f) =>
            '#1 hit number ${f.ordinal} for ${f.careerArtist}: ${f.work} '
            'reaches #1.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-1-n-p4',
        _p,
        (f) =>
            '${f.work} leaps from #${f.previousRank} to #1, ${_pc(f)} '
            '${f.ordinalText} #1.',
        requires: _ordinalFrom,
      ),
      HeadlineVariant(
        'artist-1-n-p5',
        _p,
        (f) =>
            '${f.ordinal} #1 hits and counting for ${f.careerArtist} as '
            '${f.work} reaches #1.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-1-n-p6',
        _p,
        (f) =>
            '${f.work} reaches #1 with ${f.streamsText}, giving '
            '${f.careerArtist} ${f.ordinal} #1 hits.',
        requires: _ordinalStreams,
      ),
    ],

    MomentFamily.artistTopArtist: [
      HeadlineVariant(
        'artist-top-d1',
        _d,
        (f) =>
            '${f.title} passes ${f.rivalTitle} to become your #1 artist on '
            'Sonus.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-top-d2',
        _d,
        (f) => '${f.title} is now your #1 artist, overtaking ${f.rivalTitle}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-top-d3',
        _d,
        (f) =>
            '${f.title} becomes your #1 artist with ${f.streamsText}, passing '
            '${f.rivalTitle}.',
        requires: const {MomentFact.rival, MomentFact.streams},
      ),
      HeadlineVariant(
        'artist-top-d4',
        _d,
        (f) =>
            '${f.title} takes over from ${f.rivalTitle} at #1 among your '
            'artists.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-top-d5',
        _d,
        (f) =>
            '${f.rivalTitle} is no longer your #1 artist: ${f.title} moves '
            'ahead.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-top-d6',
        _d,
        (f) =>
            'With ${f.streamsText}, ${f.title} overtakes ${f.rivalTitle} for '
            '#1 among your artists.',
        requires: const {MomentFact.rival, MomentFact.streams},
      ),
      HeadlineVariant(
        'artist-top-p1',
        _p,
        (f) => 'New #1 artist! ${f.title} passes ${f.rivalTitle}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-top-p2',
        _p,
        (f) =>
            '${f.title} overtakes ${f.rivalTitle} and is your #1 artist now.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-top-p3',
        _p,
        (f) =>
            '${f.title} vs. ${f.rivalTitle}: ${f.title} pulls ahead as your #1 artist.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-top-p4',
        _p,
        (f) =>
            '${f.title} hits ${f.streamsText} and moves past ${f.rivalTitle} '
            'to become your #1 artist.',
        requires: const {MomentFact.rival, MomentFact.streams},
      ),
      HeadlineVariant(
        'artist-top-p5',
        _p,
        (f) =>
            'Changing of the guard: ${f.title} replaces ${f.rivalTitle} as '
            'your #1 artist.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-top-p6',
        _p,
        (f) =>
            '${f.rivalTitle} slips to #2 as ${f.title} becomes your #1 '
            'artist.',
        requires: _rival,
      ),
    ],

    MomentFamily.artistStreamMilestone: [
      HeadlineVariant(
        'artist-streams-d1',
        _d,
        (f) => '${f.title} reaches ${f.milestoneText} on Sonus.',
      ),
      HeadlineVariant(
        'artist-streams-d2',
        _d,
        (f) => 'Your plays of ${f.title} reach ${f.milestoneText}.',
      ),
      HeadlineVariant(
        'artist-streams-d3',
        _d,
        (f) => '${f.title} passes ${f.milestoneText} across your library.',
      ),
      HeadlineVariant(
        'artist-streams-d4',
        _d,
        (f) => '${f.title} hits ${f.milestoneText} on Sonus.',
      ),
      HeadlineVariant(
        'artist-streams-d5',
        _d,
        (f) => '${f.milestoneText} for ${f.title}: a new listening milestone.',
      ),
      HeadlineVariant(
        'artist-streams-d6',
        _d,
        (f) =>
            "${MomentFacts.possessive(f.title)} songs have now been played "
            '${f.milestoneTimes} on Sonus.',
      ),
      HeadlineVariant(
        'artist-streams-p1',
        _p,
        (f) => '${f.title} just hit ${f.milestoneText}!',
      ),
      HeadlineVariant(
        'artist-streams-p2',
        _p,
        (f) => 'Milestone: ${f.title} crosses ${f.milestoneText}.',
      ),
      HeadlineVariant(
        'artist-streams-p3',
        _p,
        (f) => '${f.milestoneText} and counting for ${f.title}.',
      ),
      HeadlineVariant(
        'artist-streams-p4',
        _p,
        (f) => 'Big listening moment: ${f.title} reaches ${f.milestoneText}.',
      ),
      HeadlineVariant(
        'artist-streams-p5',
        _p,
        (f) => '${f.title} is now at ${f.milestoneText} in your library.',
      ),
      HeadlineVariant(
        'artist-streams-p6',
        _p,
        (f) => 'Play count check: ${f.title} reaches ${f.milestoneText}.',
      ),
    ],

    MomentFamily.artistSimultaneous: [
      HeadlineVariant(
        'artist-sim-d1',
        _d,
        (f) =>
            '${f.artist} has ${f.count} songs in the Top ${f.threshold} of '
            '${f.chart} at once.',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-d2',
        _d,
        (f) =>
            '${f.artist} places ${f.count} songs inside the Top '
            '${f.threshold} on ${f.chart}.',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-d3',
        _d,
        (f) =>
            '${f.count} songs by ${f.artist} sit in the Top ${f.threshold} of '
            '${f.chart}.',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-d4',
        _d,
        (f) =>
            '${f.artist} holds ${f.count} Top ${f.threshold} positions on '
            '${f.chart}.',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-d5',
        _d,
        (f) =>
            'In the Top ${f.threshold} of ${f.chart}: ${f.count} songs by '
            '${f.artist}.',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-d6',
        _d,
        (f) =>
            '${f.artist} charts ${f.count} songs in the Top ${f.threshold} at '
            'the same time.',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-p1',
        _p,
        (f) =>
            '${f.artist} stacks the Top ${f.threshold}: ${f.count} songs at '
            'once!',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-p2',
        _p,
        (f) =>
            '${f.count} songs, one artist: ${f.artist} holds ${f.count} Top '
            '${f.threshold} spots.',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-p3',
        _p,
        (f) =>
            '${switch (f.count) {
              2 => 'Double take',
              3 => 'Triple threat',
              _ => 'Stacked',
            }}! ${f.artist} has ${f.count} songs in the Top ${f.threshold}.',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-p4',
        _p,
        (f) =>
            '${f.artist} lands ${f.count} songs in the Top ${f.threshold} '
            'this week.',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-p5',
        _p,
        (f) => 'Top ${f.threshold} roll call: ${f.count} songs by ${f.artist}.',
        requires: _count,
      ),
      HeadlineVariant(
        'artist-sim-p6',
        _p,
        (f) =>
            '${f.artist} fills ${f.count} of the Top ${f.threshold} spots on '
            '${f.chart}.',
        requires: _count,
      ),
    ],

    // Releases ------------------------------------------------------------
    MomentFamily.releaseDebutNumberOne: [
      HeadlineVariant(
        'release-debut-1-d1',
        _d,
        (f) => '${f.subject} debuts at #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'release-debut-1-d2',
        _d,
        (f) =>
            '${_p1(f)} ${f.releaseWord} ${f.title} debuts at #1 on '
            '${f.chart}.',
      ),
      HeadlineVariant(
        'release-debut-1-d3',
        _d,
        (f) => '${f.subject} debuts at #1 on ${f.chart} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-debut-1-d4',
        _d,
        (f) =>
            '${f.subject} debuts at #1, replacing ${f.rivalSubject} at the '
            'top.',
        requires: _rival,
      ),
      HeadlineVariant(
        'release-debut-1-d5',
        _d,
        (f) => '${f.title} by ${f.artist} enters ${f.chart} at #1.',
      ),
      HeadlineVariant(
        'release-debut-1-d6',
        _d,
        (f) =>
            'A #1 debut for ${f.artist}: the ${f.releaseWord} ${f.title} '
            'opens at #1.',
      ),
      HeadlineVariant(
        'release-debut-1-p1',
        _p,
        (f) => 'Straight to #1! ${f.subject} debuts at the top of ${f.chart}.',
      ),
      HeadlineVariant(
        'release-debut-1-p2',
        _p,
        (f) => '${f.artist} opens at #1 with the ${f.releaseWord} ${f.title}.',
      ),
      HeadlineVariant(
        'release-debut-1-p3',
        _p,
        (f) => '${f.title} by ${f.artist} debuts at #1 with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-debut-1-p4',
        _p,
        (f) => '${f.title} debuts at #1 and knocks ${f.rivalSubject} from #1.',
        requires: _rival,
      ),
      HeadlineVariant(
        'release-debut-1-p5',
        _p,
        (f) => 'New ${f.releaseWord}, new #1: ${f.subject} debuts at #1.',
      ),
      HeadlineVariant(
        'release-debut-1-p6',
        _p,
        (f) =>
            '${f.artist} lands a #1 debut as ${f.title} enters ${f.chart} at '
            '#1.',
      ),
    ],

    MomentFamily.releaseDebut: [
      HeadlineVariant(
        'release-debut-d1',
        _d,
        (f) => '${f.subject} debuts at #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-debut-d2',
        _d,
        (f) =>
            '${_p1(f)} ${f.releaseWord} ${f.title} enters ${f.chart} at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-debut-d3',
        _d,
        (f) => '${f.subject} debuts at #${f.rank} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-debut-d4',
        _d,
        (f) => '${f.title} by ${f.artist} opens at #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-debut-d5',
        _d,
        (f) =>
            'New on ${f.chart}: the ${f.releaseWord} ${f.title} by '
            '${f.artist} enters at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-debut-d6',
        _d,
        (f) =>
            '${f.artist} adds the ${f.releaseWord} ${f.title} to ${f.chart} '
            'at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-debut-p1',
        _p,
        (f) => 'Fresh ${f.releaseWord}! ${f.subject} debuts at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-debut-p2',
        _p,
        (f) => '${f.title} arrives at #${f.rank} for ${f.artist}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-debut-p3',
        _p,
        (f) => '${f.subject} enters at #${f.rank} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-debut-p4',
        _p,
        (f) =>
            'Just in: the ${f.releaseWord} ${f.title} by ${f.artist} debuts '
            'at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-debut-p5',
        _p,
        (f) =>
            '${f.artist} drops into ${f.chart} at #${f.rank} with '
            '${f.title}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-debut-p6',
        _p,
        (f) => 'New entry: ${f.subject} lands at #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
    ],

    MomentFamily.releaseReachesNumberOne: [
      HeadlineVariant(
        'release-1-d1',
        _d,
        (f) => '${f.subject} reaches #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'release-1-d2',
        _d,
        (f) => '${f.subject} replaces ${f.rivalSubject} at #1 on ${f.chart}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'release-1-d3',
        _d,
        (f) =>
            '${f.subject} rises from #${f.previousRank} to #1 on ${f.chart}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'release-1-d4',
        _d,
        (f) => '${f.subject} reaches #1 on ${f.chart} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-1-d5',
        _d,
        (f) =>
            '${_p1(f)} ${f.releaseWord} ${f.title} becomes the new #1 on '
            '${f.chart}.',
      ),
      HeadlineVariant(
        'release-1-d6',
        _d,
        (f) =>
            '${f.subject} reaches #1, improving on its previous peak of '
            '#${f.previousPeak}.',
        requires: _peak,
      ),
      HeadlineVariant(
        'release-1-p1',
        _p,
        (f) => '${f.title} is #1! ${f.artist} tops ${f.chart}.',
      ),
      HeadlineVariant(
        'release-1-p2',
        _p,
        (f) => '${f.title} dethrones ${f.rivalSubject} to reach #1.',
        requires: _rival,
      ),
      HeadlineVariant(
        'release-1-p3',
        _p,
        (f) =>
            '${f.title} climbs from #${f.previousRank} to #1 for '
            '${f.artist}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'release-1-p4',
        _p,
        (f) => 'With ${f.streamsText}, ${f.subject} reaches #1.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-1-p5',
        _p,
        (f) => 'New #1 ${f.releaseWord}: ${f.subject} moves up to #1.',
      ),
      HeadlineVariant(
        'release-1-p6',
        _p,
        (f) =>
            '${f.artist} has the #1 ${f.releaseWord} on ${f.chart} with '
            '${f.title}.',
      ),
    ],

    MomentFamily.releaseReturnsToNumberOne: [
      HeadlineVariant(
        'release-1-again-d1',
        _d,
        (f) => '${f.subject} returns to #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'release-1-again-d2',
        _d,
        (f) => '${f.subject} takes #1 back from ${f.rivalSubject}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'release-1-again-d3',
        _d,
        (f) => '${f.subject} climbs from #${f.previousRank} back to #1.',
        requires: _previous,
      ),
      HeadlineVariant(
        'release-1-again-d4',
        _d,
        (f) => '${f.subject} returns to #1 with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-1-again-d5',
        _d,
        (f) =>
            '${_p1(f)} ${f.releaseWord} ${f.title} is #1 again on '
            '${f.chart}.',
      ),
      HeadlineVariant(
        'release-1-again-d6',
        _d,
        (f) => '${f.title} regains #1 on ${f.chart} for ${f.artist}.',
      ),
      HeadlineVariant(
        'release-1-again-p1',
        _p,
        (f) => 'Back at #1! ${f.subject} reclaims the top spot.',
      ),
      HeadlineVariant(
        'release-1-again-p2',
        _p,
        (f) => '${f.title} retakes #1 from ${f.rivalSubject}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'release-1-again-p3',
        _p,
        (f) => '${f.artist} is back on top as ${f.title} returns to #1.',
      ),
      HeadlineVariant(
        'release-1-again-p4',
        _p,
        (f) => '${f.title} returns to #1 with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-1-again-p5',
        _p,
        (f) => 'Once more at #1: ${f.subject} heads ${f.chart} again.',
      ),
      HeadlineVariant(
        'release-1-again-p6',
        _p,
        (f) => '${f.title} bounces from #${f.previousRank} back to #1.',
        requires: _previous,
      ),
    ],

    MomentFamily.releaseNewPeak: [
      HeadlineVariant(
        'release-peak-d1',
        _d,
        (f) => '${f.subject} reaches a new peak of #${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-peak-d2',
        _d,
        (f) =>
            '${f.subject} climbs to a new peak of #${f.rank}, up from '
            '#${f.previousPeak}.',
        requires: _peak,
      ),
      HeadlineVariant(
        'release-peak-d3',
        _d,
        (f) =>
            '${_p1(f)} ${f.releaseWord} ${f.title} rises to #${f.rank}, its '
            'highest position yet.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-peak-d4',
        _d,
        (f) =>
            '${f.subject} enters the Top ${f.threshold} at #${f.rank} on '
            '${f.chart}.',
        requires: _zone,
      ),
      HeadlineVariant(
        'release-peak-d5',
        _d,
        (f) =>
            '${f.subject} hits a new peak of #${f.rank} with '
            '${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-peak-d6',
        _d,
        (f) =>
            '${f.subject} moves from #${f.previousRank} to a new peak of '
            '#${f.rank}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'release-peak-p1',
        _p,
        (f) => 'New peak! ${f.subject} climbs to #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-peak-p2',
        _p,
        (f) =>
            'Top ${f.threshold} for the ${f.releaseWord}: ${f.title} by '
            '${f.artist} reaches #${f.rank}.',
        requires: _zone,
      ),
      HeadlineVariant(
        'release-peak-p3',
        _p,
        (f) => '${f.title} reaches a new high of #${f.rank} for ${f.artist}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-peak-p4',
        _p,
        (f) =>
            '${f.title} beats its old best of #${f.previousPeak} and peaks at '
            '#${f.rank}.',
        requires: _peak,
      ),
      HeadlineVariant(
        'release-peak-p5',
        _p,
        (f) =>
            '${f.subject} reaches #${f.rank} with ${f.streamsText}, a new '
            'peak.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-peak-p6',
        _p,
        (f) =>
            '${f.artist} sees the ${f.releaseWord} ${f.title} rise to a new '
            'peak of #${f.rank}.',
        requires: _rank,
      ),
    ],

    MomentFamily.releaseReentry: [
      HeadlineVariant(
        'release-reentry-d1',
        _d,
        (f) => '${f.subject} re-enters ${f.chart} at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-reentry-d2',
        _d,
        (f) => '${f.subject} returns to ${f.chart} at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-reentry-d3',
        _d,
        (f) => '${f.subject} re-enters at #${f.rank} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-reentry-d4',
        _d,
        (f) =>
            '${f.subject} returns at #${f.rank}; it previously peaked at '
            '#${f.previousPeak}.',
        requires: _peak,
      ),
      HeadlineVariant(
        'release-reentry-d5',
        _d,
        (f) =>
            '${_p1(f)} ${f.releaseWord} ${f.title} is back on ${f.chart} at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-reentry-d6',
        _d,
        (f) =>
            '${f.artist} returns to ${f.chart} as the ${f.releaseWord} '
            '${f.title} re-enters at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-reentry-p1',
        _p,
        (f) => "It's back! ${f.subject} re-enters at #${f.rank}.",
        requires: _rank,
      ),
      HeadlineVariant(
        'release-reentry-p2',
        _p,
        (f) => '${f.title} makes a comeback at #${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-reentry-p3',
        _p,
        (f) =>
            'Return trip: the ${f.releaseWord} ${f.title} is back at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-reentry-p4',
        _p,
        (f) => '${f.title} returns at #${f.rank} with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'release-reentry-p5',
        _p,
        (f) =>
            'Once a #${f.previousPeak} peak, ${f.title} is back at '
            '#${f.rank}.',
        requires: _peak,
      ),
      HeadlineVariant(
        'release-reentry-p6',
        _p,
        (f) =>
            '${f.artist} is back: ${f.title} re-enters ${f.chart} at '
            '#${f.rank}.',
        requires: _rank,
      ),
    ],

    MomentFamily.releaseStreamMilestone: [
      HeadlineVariant(
        'release-streams-d1',
        _d,
        (f) => '${f.subject} reaches ${f.milestoneText} on Sonus.',
      ),
      HeadlineVariant(
        'release-streams-d2',
        _d,
        (f) => '${_p1(f)} ${f.releaseWord} ${f.title} hits ${f.milestoneText}.',
      ),
      HeadlineVariant(
        'release-streams-d3',
        _d,
        (f) =>
            '${f.subject} reaches ${f.milestoneText} and stands at '
            '#${f.rank} on ${f.chart}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-streams-d4',
        _d,
        (f) =>
            'The ${f.releaseWord} ${f.title} by ${f.artist} has now been '
            'played ${f.milestoneTimes} on Sonus.',
      ),
      HeadlineVariant(
        'release-streams-d5',
        _d,
        (f) =>
            'A milestone for ${f.artist}: ${f.title} reaches '
            '${f.milestoneText}.',
      ),
      HeadlineVariant(
        'release-streams-d6',
        _d,
        (f) => '${f.subject} crosses ${f.milestoneText}.',
      ),
      HeadlineVariant(
        'release-streams-p1',
        _p,
        (f) => '${f.milestoneText}! ${f.subject} hits a streaming milestone.',
      ),
      HeadlineVariant(
        'release-streams-p2',
        _p,
        (f) => '${f.title} just reached ${f.milestoneText} on Sonus.',
      ),
      HeadlineVariant(
        'release-streams-p3',
        _p,
        (f) =>
            '${f.artist} celebrates ${f.milestoneText} for the '
            '${f.releaseWord} ${f.title}.',
      ),
      HeadlineVariant(
        'release-streams-p4',
        _p,
        (f) =>
            '${f.title} reaches ${f.milestoneText} while sitting at '
            '#${f.rank}.',
        requires: _rank,
      ),
      HeadlineVariant(
        'release-streams-p5',
        _p,
        (f) => 'Milestone unlocked: ${f.subject} reaches ${f.milestoneText}.',
      ),
      HeadlineVariant(
        'release-streams-p6',
        _p,
        (f) =>
            'Play count check: the ${f.releaseWord} ${f.title} is now at '
            '${f.milestoneText}.',
      ),
    ],

    MomentFamily.releaseWeeksMilestone: _weeksVariants('release'),

    MomentFamily.artistFirstNumberOneRelease: [
      HeadlineVariant(
        'artist-release-1-d1',
        _d,
        (f) =>
            '${f.careerArtist} earns a first #1 ${f.releaseWord} as '
            '${f.title} reaches #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'artist-release-1-d2',
        _d,
        (f) => '${f.title} gives ${f.careerArtist} a first #1 on ${f.chart}.',
      ),
      HeadlineVariant(
        'artist-release-1-d3',
        _d,
        (f) =>
            '${f.title} replaces ${f.rivalSubject} at #1, giving '
            '${f.careerArtist} a first #1 ${f.releaseWord}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-release-1-d4',
        _d,
        (f) =>
            '${f.title} rises from #${f.previousRank} to #1, a first #1 '
            '${f.releaseWord} for ${f.careerArtist}.',
        requires: _previous,
      ),
      HeadlineVariant(
        'artist-release-1-d5',
        _d,
        (f) =>
            '${f.careerArtist} scores a first #1 ${f.releaseWord} as '
            '${f.title} reaches #1 with ${f.streamsText}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'artist-release-1-d6',
        _d,
        (f) =>
            'First #1 ${f.releaseWord} for ${f.careerArtist}: ${f.title} '
            'leads ${f.chart} at #1.',
      ),
      HeadlineVariant(
        'artist-release-1-p1',
        _p,
        (f) =>
            '${f.careerArtist} has a first #1 ${f.releaseWord}! ${f.title} '
            'reaches #1.',
      ),
      HeadlineVariant(
        'artist-release-1-p2',
        _p,
        (f) =>
            '${f.title} dethrones ${f.rivalSubject} and hands '
            '${f.careerArtist} a first #1 ${f.releaseWord}.',
        requires: _rival,
      ),
      HeadlineVariant(
        'artist-release-1-p3',
        _p,
        (f) =>
            'A first #1 ${f.releaseWord} for ${f.careerArtist}: ${f.title} '
            'is the new #1.',
      ),
      HeadlineVariant(
        'artist-release-1-p4',
        _p,
        (f) =>
            '${f.title} jumps from #${f.previousRank} to #1 for '
            "${_pc(f)} first #1 ${f.releaseWord}.",
        requires: _previous,
      ),
      HeadlineVariant(
        'artist-release-1-p5',
        _p,
        (f) =>
            '${f.title} reaches #1 with ${f.streamsText}: a first #1 '
            '${f.releaseWord} for ${f.careerArtist}.',
        requires: _streams,
      ),
      HeadlineVariant(
        'artist-release-1-p6',
        _p,
        (f) =>
            '${f.careerArtist} reaches #1 on ${f.chart} for the first time '
            'with ${f.title}.',
      ),
    ],

    MomentFamily.artistNthNumberOneRelease: [
      HeadlineVariant(
        'artist-release-1-n-d1',
        _d,
        (f) =>
            '${f.careerArtist} earns ${f.aOrdinalText} #1 release as '
            '${f.title} reaches #1.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-release-1-n-d2',
        _d,
        (f) =>
            '${f.title} becomes ${_pc(f)} ${f.ordinalText} #1 on '
            '${f.chart}.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-release-1-n-d3',
        _d,
        (f) =>
            '${f.title} replaces ${f.rivalSubject} at #1, ${_pc(f)} '
            '${f.ordinalText} #1 release.',
        requires: _ordinalRival,
      ),
      HeadlineVariant(
        'artist-release-1-n-d4',
        _d,
        (f) =>
            '${f.title} rises from #${f.previousRank} to #1, '
            '${f.aOrdinalText} #1 for ${f.careerArtist}.',
        requires: _ordinalFrom,
      ),
      HeadlineVariant(
        'artist-release-1-n-d5',
        _d,
        (f) =>
            '${f.careerArtist} now has ${f.ordinal} #1 releases on '
            '${f.chart} after ${f.title} reaches #1.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-release-1-n-d6',
        _d,
        (f) =>
            '${f.title} reaches #1 with ${f.streamsText}, ${_pc(f)} '
            '${f.ordinalText} #1 release.',
        requires: _ordinalStreams,
      ),
      HeadlineVariant(
        'artist-release-1-n-p1',
        _p,
        (f) =>
            '${f.careerArtist} does it again: ${f.title} is '
            '${f.aOrdinalText} #1 release.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-release-1-n-p2',
        _p,
        (f) =>
            '${f.title} dethrones ${f.rivalSubject} for ${_pc(f)} '
            '${f.ordinalText} #1.',
        requires: _ordinalRival,
      ),
      HeadlineVariant(
        'artist-release-1-n-p3',
        _p,
        (f) =>
            '#1 release number ${f.ordinal} for ${f.careerArtist}: '
            '${f.title} reaches #1.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-release-1-n-p4',
        _p,
        (f) =>
            '${f.title} leaps from #${f.previousRank} to #1, ${_pc(f)} '
            '${f.ordinalText} #1.',
        requires: _ordinalFrom,
      ),
      HeadlineVariant(
        'artist-release-1-n-p5',
        _p,
        (f) =>
            '${f.ordinal} #1 releases and counting for ${f.careerArtist} as '
            '${f.title} reaches #1.',
        requires: const {MomentFact.ordinal},
      ),
      HeadlineVariant(
        'artist-release-1-n-p6',
        _p,
        (f) =>
            '${f.title} reaches #1 with ${f.streamsText}, giving '
            '${f.careerArtist} ${f.ordinal} #1 releases.',
        requires: _ordinalStreams,
      ),
    ],
  };

  /// Longevity headlines for songs and releases, from weekly records only.
  static List<HeadlineVariant> _weeksVariants(String kind) => [
    HeadlineVariant(
      '$kind-weeks-d1',
      _d,
      (f) =>
          '${f.subject} spends ${MomentFacts.withArticle(MomentFacts.ordinalWord(f.weeks!))} '
          'consecutive week ${f.weeksPlace}.',
      requires: _run,
    ),
    HeadlineVariant(
      '$kind-weeks-d2',
      _d,
      (f) =>
          '${f.subject} reaches ${MomentFacts.weeksText(f.weeks!)} '
          '${f.weeksPlace}.',
      requires: _weeks,
    ),
    HeadlineVariant(
      '$kind-weeks-d3',
      _d,
      (f) =>
          '${f.subject} logs its ${MomentFacts.ordinalWord(f.weeks!)} week '
          '${f.weeksPlace}.',
      requires: _weeks,
    ),
    HeadlineVariant(
      '$kind-weeks-d4',
      _d,
      (f) =>
          '${f.subject} has now spent ${MomentFacts.weeksText(f.weeks!)} '
          '${f.weeksPlace}.',
      requires: _weeks,
    ),
    HeadlineVariant(
      '$kind-weeks-d5',
      _d,
      (f) =>
          '${MomentFacts.weeksText(f.weeks!)} in a row ${f.weeksPlace}: '
          '${f.subject} extends its run.',
      requires: _run,
    ),
    HeadlineVariant(
      '$kind-weeks-d6',
      _d,
      (f) => '${f.subject} completes week ${f.weeks} ${f.weeksPlace}.',
      requires: _weeks,
    ),
    HeadlineVariant(
      '$kind-weeks-p1',
      _p,
      (f) => 'Week ${f.weeks}! ${f.subject} is still ${f.weeksPlace}.',
      requires: _run,
    ),
    HeadlineVariant(
      '$kind-weeks-p2',
      _p,
      (f) =>
          '${f.work} keeps going: ${MomentFacts.weeksText(f.weeks!)} in a row '
          '${f.weeksPlace}.',
      requires: _run,
    ),
    HeadlineVariant(
      '$kind-weeks-p3',
      _p,
      (f) =>
          '${f.artist} logs ${MomentFacts.weeksText(f.weeks!)} '
          '${f.weeksPlace} with ${f.work}.',
      requires: _weeks,
    ),
    HeadlineVariant(
      '$kind-weeks-p4',
      _p,
      (f) =>
          'Staying power: ${f.subject} reaches '
          '${MomentFacts.weeksText(f.weeks!)} ${f.weeksPlace}.',
      requires: _weeks,
    ),
    HeadlineVariant(
      '$kind-weeks-p5',
      _p,
      (f) =>
          '${MomentFacts.weeksText(f.weeks!)} ${f.weeksPlace} for ${f.work} '
          'by ${f.artist}.',
      requires: _weeks,
    ),
    HeadlineVariant(
      '$kind-weeks-p6',
      _p,
      (f) =>
          'Longevity check: ${f.work} hits ${MomentFacts.weeksText(f.weeks!)} '
          '${f.weeksPlace}.',
      requires: _weeks,
    ),
  ];
}
