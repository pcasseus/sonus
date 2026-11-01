// SN-50 device QA: Moments name every featured artist from the structured
// credits (guests apart), and show a song's own or edition artwork as Now
// Playing does. Both for stories from the device-polish start; earlier
// stories keep exactly what they published.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';

import 'moment_editorial_test.dart' show FakeLookups, event, items, song;

final _start = DateTime.utc(2026, 11, 2);
final _after = DateTime.utc(2026, 11, 3, 12);
final _before = DateTime.utc(2026, 10, 27, 12);
final _polished = ChartMomentRules(devicePolishFromUtc: _start);

FakeLookups _lookups({
  Map<String, List<String>> featured = const {},
  Map<String, List<String>> guests = const {},
}) => FakeLookups(
  artists: const {'artist-a': 'Zara Larsson'},
  featured: featured,
  guests: guests,
  // The album's primary cover, and the song's own (edition) artwork.
  covers: const {'amb': '/art/midnight-sun.jpg'},
  currentCovers: const {'amb': '/art/girls-trip.jpg'},
);

List<MomentStory> _compose(
  List<ChartMomentEvent> events, {
  FakeLookups? lookups,
  ChartMomentRules? rules,
}) => MomentEditorialDesk(
  lookups: lookups ?? _lookups(),
  rules: rules ?? _polished,
).compose(items(events));

ChartMomentEvent _debut({DateTime? at, String id = 'amb', int rank = 42}) =>
    event(
      ChartMomentEventType.debut,
      entity: song(id),
      source: 'debut-$id',
      at: at ?? _after,
      rank: rank,
    );

ChartMomentEvent _climb(String id, int from, int to, int minutes) => event(
  ChartMomentEventType.rankRise,
  entity: song(id),
  source: '$id-$minutes',
  at: _after.add(Duration(minutes: minutes)),
  rank: to,
  previousRank: from,
);

void main() {
  group('featured artists', () {
    test('every featured artist is named, in credit order', () {
      final story = _compose(
        [_debut()],
        lookups: _lookups(
          featured: {
            'amb': ['Madison Beer', 'BAMBII'],
          },
        ),
      ).single;
      expect(
        story.headline,
        contains(
          '"Song amb" by Name artist-a featuring Madison Beer and BAMBII',
        ),
      );
    });

    test('a long credit list stays readable', () {
      expect(MomentFacts.nameList(['A']), 'A');
      expect(MomentFacts.nameList(['A', 'B']), 'A and B');
      expect(MomentFacts.nameList(['A', 'B', 'C']), 'A, B and C');
      expect(
        MomentFacts.nameList(['A', 'B', 'C', 'D', 'E']),
        'A, B and 3 others',
      );
      final story = _compose(
        [_debut()],
        lookups: _lookups(
          featured: {
            'amb': ['One', 'Two', 'Three', 'Four'],
          },
        ),
      ).single;
      expect(story.headline, contains('featuring One, Two and 2 others'));
    });

    test('guests are never featured; they are credited in the body', () {
      final story = _compose(
        [_debut()],
        lookups: _lookups(
          guests: {
            'amb': ['Guest Voice'],
          },
        ),
      ).single;
      expect(story.headline, isNot(contains('featuring')));
      expect(story.headline, isNot(contains('Guest Voice')));
      expect(story.body, contains('With a guest appearance by Guest Voice.'));

      final both = _compose(
        [_debut()],
        lookups: _lookups(
          featured: {
            'amb': ['Madison Beer'],
          },
          guests: {
            'amb': ['G1', 'G2'],
          },
        ),
      ).single;
      expect(both.headline, contains('featuring Madison Beer'));
      expect(both.headline, isNot(contains('G1')));
      expect(both.body, contains('With guest appearances by G1 and G2.'));
    });

    test('no credits: the lead artist alone', () {
      final story = _compose([_debut()]).single;
      expect(story.headline, contains('"Song amb" by Name artist-a'));
      expect(story.headline, isNot(contains('featuring')));
      expect(story.body ?? '', isNot(contains('guest')));
    });

    test('climbs and developing stories carry the credits', () {
      final lookups = _lookups(
        featured: {
          'amb': ['Madison Beer', 'BAMBII'],
        },
      );
      // Every headline style credits them: in the headline, or first in
      // the body when the headline names the song on its own.
      for (var i = 0; i < 8; i++) {
        final story = _compose(
          [_climb('c$i', 40, 38, 0)],
          lookups: _lookups(
            featured: {
              'c$i': ['Madison Beer', 'BAMBII'],
            },
          ),
        ).single;
        final text = '${story.headline} ${story.body ?? ''}';
        expect(
          text,
          contains('Madison Beer and BAMBII'),
          reason: story.headline,
        );
      }

      final developing = _compose([
        _climb('amb', 40, 38, 0),
        _climb('amb', 38, 30, 10),
      ], lookups: lookups).single;
      expect(developing.isDeveloping, isTrue);
      expect(
        developing.headline,
        contains('featuring Madison Beer and BAMBII'),
      );
      expect(
        developing.updates.first.text,
        contains('featuring Madison Beer and BAMBII'),
      );
      expect(developing.updates.last.text, startsWith('UPDATE: Song amb'));
    });

    test('earlier stories keep their published wording', () {
      final lookups = _lookups(
        featured: {
          'amb': ['Madison Beer', 'BAMBII'],
        },
        guests: {
          'amb': ['Guest Voice'],
        },
      );
      final legacy = _compose(
        [_debut(at: _before)],
        lookups: lookups,
        rules: ChartMomentRules.legacy,
      ).single;
      final polishedRules = _compose([
        _debut(at: _before),
      ], lookups: lookups).single;
      expect(polishedRules.headline, legacy.headline);
      expect(polishedRules.body, legacy.body);
      expect(legacy.headline, isNot(contains('BAMBII')));
    });
  });

  group('artwork', () {
    test('new stories show the song or edition artwork, as Now Playing', () {
      final story = _compose([_debut()]).single;
      expect(story.visual.left.path, '/art/girls-trip.jpg');
    });

    test('earlier stories keep the cover they were published with', () {
      final story = _compose([_debut(at: _before)]).single;
      expect(story.visual.left.path, '/art/midnight-sun.jpg');
    });

    test('developing stories use the same artwork', () {
      final story = _compose([
        _climb('amb', 40, 38, 0),
        _climb('amb', 38, 30, 10),
      ]).single;
      expect(story.visual.left.path, '/art/girls-trip.jpg');
    });
  });
}
