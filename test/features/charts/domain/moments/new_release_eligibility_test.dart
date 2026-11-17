import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_eligibility.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

ChartMomentEvent debutEvent({
  String songId = 'song-dead',
  ChartMomentEventType type = ChartMomentEventType.debut,
  ChartMomentScope scope = ChartMomentScope.finalized,
  ChartType chartType = ChartType.songs,
  int? rank = 18,
  int? previousRank,
  int? previousPeakRank,
  DateTime? weekStartUtc,
  DateTime? occurredAt,
}) {
  final week = weekStartUtc ?? DateTime.utc(2026, 11, 16);
  return ChartMomentEvent(
    id: 'event-$songId-${scope.name}',
    deduplicationKey: 'dedupe-$songId-${scope.name}',
    chartType: chartType,
    scope: scope,
    eventType: type,
    entity: ChartEntitySnapshot(
      entityId: songId,
      title: 'Dead',
      artistName: 'Madison Beer',
    ),
    weekStartUtc: week,
    weekEndUtc: week.add(const Duration(days: 7)),
    occurredAt: occurredAt ?? week.add(const Duration(days: 7)),
    createdAt: week.add(const Duration(days: 7)),
    currentRank: rank,
    previousRank: previousRank,
    previousPeakRank: previousPeakRank,
  );
}

NewReleaseEditionFacts edition(
  String? date, {
  AlbumEditionType type = AlbumEditionType.standard,
}) =>
    NewReleaseEditionFacts(type: type, releaseDate: ReleaseDate.tryParse(date));

NewReleaseAlbumFacts album({
  List<NewReleaseEditionFacts>? editions,
  ReleaseFormat? format = ReleaseFormat.album,
  ReleaseKind? kind,
  bool? live,
  String title = 'Anatomy of a Popstar',
  bool songOnAlbum = true,
}) => NewReleaseAlbumFacts(
  albumId: 'album-1',
  title: title,
  format: format,
  kind: kind,
  live: live,
  songOnAlbum: songOnAlbum,
  editions: editions ?? [edition('2026-11-07')],
);

NewReleaseSongFacts single(String? date, {NewReleaseAlbumFacts? on}) =>
    NewReleaseSongFacts(
      songId: 'song-dead',
      isSingle: true,
      singleReleaseDate: ReleaseDate.tryParse(date),
      album: on,
    );

NewReleaseSongFacts albumTrack(NewReleaseAlbumFacts? on, {String? single}) =>
    NewReleaseSongFacts(
      songId: 'song-dead',
      isSingle: false,
      singleReleaseDate: ReleaseDate.tryParse(single),
      album: on,
    );

NewReleaseIneligibility? reasonFor(
  NewReleaseSongFacts song, [
  ChartMomentEvent? event,
]) => NewReleaseEligibility.evaluate(event ?? debutEvent(), song).reason;

void main() {
  group('release date cutoff (strictly after 2026-10-01)', () {
    bool isNew(String text) =>
        NewReleaseEligibility.isNew(ReleaseDate.tryParse(text)!);

    test('2026-10-01 does not qualify; 2026-10-02 is the first day', () {
      expect(isNew('2026-09-30'), isFalse);
      expect(isNew('2026-10-01'), isFalse);
      expect(isNew('2026-10-02'), isTrue);
      expect(isNew('2026-12-31'), isTrue);
    });

    test('partial dates qualify only when their whole interval is after', () {
      expect(isNew('2026-10'), isFalse);
      expect(isNew('2026-09'), isFalse);
      expect(isNew('2026-11'), isTrue);
      expect(isNew('2026'), isFalse);
      expect(isNew('2025'), isFalse);
      expect(isNew('2027'), isTrue);
    });

    test('a missing date never qualifies', () {
      expect(NewReleaseEligibility.isNew(null), isFalse);
    });

    test('a stored edition date without a recorded precision is missing', () {
      final legacy = NewReleaseEditionFacts.fromStored(
        type: AlbumEditionType.standard,
        releaseDate: DateTime.utc(2026, 11, 7),
      );
      expect(legacy.releaseDate, isNull);
      final dated = NewReleaseEditionFacts.fromStored(
        type: AlbumEditionType.standard,
        releaseDate: DateTime.utc(2026, 11),
        precision: ReleaseDatePrecision.month,
      );
      expect(dated.releaseDate, ReleaseDate.of(2026, 11));
    });
  });

  group('4.1 new single', () {
    test('a Single with its own new date debuting is eligible', () {
      final decision = NewReleaseEligibility.evaluate(
        debutEvent(),
        single('2026-10-02'),
      );
      expect(decision.isEligible, isTrue);
      expect(decision.debut!.kind, NewReleaseDebutKind.single);
      expect(decision.debut!.rank, 18);
      expect(decision.debut!.releaseDate, ReleaseDate.of(2026, 10, 2));
    });

    test('the cutoff day itself and partial cutoff dates are not eligible', () {
      for (final date in ['2026-10-01', '2026-10', '2026']) {
        expect(
          reasonFor(single(date)),
          NewReleaseIneligibility.singleDateNotNew,
          reason: date,
        );
      }
      expect(reasonFor(single('2026-11')), isNull);
    });

    test('never falls back to the album date', () {
      final newAlbum = album(editions: [edition('2026-11-07')]);
      expect(
        reasonFor(single(null, on: newAlbum)),
        NewReleaseIneligibility.singleDateMissing,
      );
      expect(
        reasonFor(single('2026-08-01', on: newAlbum)),
        NewReleaseIneligibility.singleDateNotNew,
      );
    });

    test('a Single date kept after the song stopped being a Single is '
        'ignored', () {
      // The presentation row survives un-marking; the song is then an album
      // track, judged by its album alone.
      final oldAlbum = album(editions: [edition('2019-05-17')]);
      expect(
        reasonFor(albumTrack(oldAlbum, single: '2026-11-01')),
        NewReleaseIneligibility.albumDateNotNew,
      );
    });
  });

  group('4.2 new album track', () {
    test('a track from a new standard album is eligible', () {
      final decision = NewReleaseEligibility.evaluate(
        debutEvent(rank: 24),
        albumTrack(
          album(
            editions: [
              edition('2026-11-07'),
              edition('2026-12', type: AlbumEditionType.deluxe),
            ],
          ),
        ),
      );
      expect(decision.isEligible, isTrue);
      final debut = decision.debut!;
      expect(debut.kind, NewReleaseDebutKind.albumTrack);
      expect(debut.albumTitle, 'Anatomy of a Popstar');
      expect(debut.albumFormat, ReleaseFormat.album);
      expect(debut.releaseDate, ReleaseDate.of(2026, 11, 7));
    });

    test('an EP qualifies; a Single release or unconfirmed format does '
        'not', () {
      expect(reasonFor(albumTrack(album(format: ReleaseFormat.ep))), isNull);
      expect(
        reasonFor(albumTrack(album(format: ReleaseFormat.single))),
        NewReleaseIneligibility.releaseIsSingleFormat,
      );
      expect(
        reasonFor(albumTrack(album(format: null))),
        NewReleaseIneligibility.releaseFormatUnconfirmed,
      );
    });

    test('an old album track newly imported is not a new release', () {
      // Import and date-added times are not inputs at all: only the
      // release's own dates count.
      expect(
        reasonFor(albumTrack(album(editions: [edition('2024-05-31')]))),
        NewReleaseIneligibility.albumDateNotNew,
      );
    });

    test('a new Deluxe of an old album is not a new album', () {
      expect(
        reasonFor(
          albumTrack(
            album(
              editions: [
                edition('2024-02-23'),
                edition('2026-11-14', type: AlbumEditionType.deluxe),
              ],
            ),
          ),
        ),
        NewReleaseIneligibility.albumDateNotNew,
      );
      // Only the Deluxe in the library: the original date is unknown.
      expect(
        reasonFor(
          albumTrack(
            album(
              editions: [edition('2026-11-14', type: AlbumEditionType.deluxe)],
            ),
          ),
        ),
        NewReleaseIneligibility.noStandardEdition,
      );
    });

    test('remasters and anniversary editions are reissues', () {
      for (final type in [
        AlbumEditionType.remaster,
        AlbumEditionType.anniversary,
      ]) {
        expect(
          reasonFor(
            albumTrack(
              album(
                editions: [
                  edition('2026-11-07'),
                  edition('2026-11-07', type: type),
                ],
              ),
            ),
          ),
          NewReleaseIneligibility.reissueEdition,
          reason: type.name,
        );
      }
    });

    test('compilations, soundtracks, cast recordings and live releases are '
        'excluded', () {
      for (final kind in ReleaseKind.values) {
        expect(
          reasonFor(albumTrack(album(kind: kind))),
          NewReleaseIneligibility.releaseKindExcluded,
          reason: kind.name,
        );
      }
      expect(
        reasonFor(albumTrack(album(live: true))),
        NewReleaseIneligibility.releaseKindExcluded,
      );
      expect(reasonFor(albumTrack(album(live: false))), isNull);
    });

    test('missing or ambiguous album data is not eligible', () {
      expect(reasonFor(albumTrack(null)), NewReleaseIneligibility.albumMissing);
      expect(
        reasonFor(albumTrack(album(songOnAlbum: false))),
        NewReleaseIneligibility.albumMissing,
      );
      expect(
        reasonFor(albumTrack(album(title: '  '))),
        NewReleaseIneligibility.albumTitleMissing,
      );
      expect(
        reasonFor(
          albumTrack(
            album(
              editions: [
                edition('2026-11-07'),
                edition(null, type: AlbumEditionType.deluxe),
              ],
            ),
          ),
        ),
        NewReleaseIneligibility.editionDateMissing,
      );
      expect(
        reasonFor(albumTrack(album(editions: const []))),
        NewReleaseIneligibility.noStandardEdition,
      );
    });

    test('album cutoff boundaries match the single cutoff', () {
      for (final (date, eligible) in [
        ('2026-10-01', false),
        ('2026-10-02', true),
        ('2026-10', false),
        ('2026-11', true),
        ('2026', false),
      ]) {
        expect(
          reasonFor(albumTrack(album(editions: [edition(date)]))) == null,
          eligible,
          reason: date,
        );
      }
    });
  });

  group('the chart event', () {
    test('a re-entry is never a new-release debut', () {
      expect(
        reasonFor(
          single('2026-11-01'),
          debutEvent(type: ChartMomentEventType.reentry, previousPeakRank: 40),
        ),
        NewReleaseIneligibility.reentry,
      );
    });

    test('routine movement is not a debut', () {
      for (final type in [
        ChartMomentEventType.rankRise,
        ChartMomentEventType.rankSame,
        ChartMomentEventType.newPeak,
        ChartMomentEventType.firstThresholdEntry,
      ]) {
        expect(
          reasonFor(
            single('2026-11-01'),
            debutEvent(type: type, previousRank: 30),
          ),
          NewReleaseIneligibility.notADebut,
          reason: type.name,
        );
      }
    });

    test('a debut carrying earlier chart history is not genuine', () {
      expect(
        reasonFor(single('2026-11-01'), debutEvent(previousPeakRank: 12)),
        NewReleaseIneligibility.priorChartHistory,
      );
      expect(
        reasonFor(single('2026-11-01'), debutEvent(previousRank: 12)),
        NewReleaseIneligibility.priorChartHistory,
      );
    });

    test('live Moments, release charts, missing ranks and other songs are '
        'excluded', () {
      final song = single('2026-11-01');
      expect(
        reasonFor(song, debutEvent(scope: ChartMomentScope.live)),
        NewReleaseIneligibility.liveScope,
      );
      expect(
        reasonFor(song, debutEvent(chartType: ChartType.albums)),
        NewReleaseIneligibility.notSongChart,
      );
      expect(
        reasonFor(song, debutEvent(rank: null)),
        NewReleaseIneligibility.noRank,
      );
      expect(
        reasonFor(song, debutEvent(rank: 201)),
        NewReleaseIneligibility.noRank,
      );
      expect(
        reasonFor(song, debutEvent(songId: 'other-song')),
        NewReleaseIneligibility.entityMismatch,
      );
    });

    test('weekly and career debuts, Hot 100 and Bubbling Under positions', () {
      final song = single('2026-11-01');
      final career = NewReleaseEligibility.evaluate(
        debutEvent(scope: ChartMomentScope.allTime, rank: 150),
        song,
      ).debut!;
      expect(career.weekly, isFalse);
      expect(career.bubblingUnder, isTrue);
      expect(career.rank, 150);

      final weekly = NewReleaseEligibility.evaluate(
        debutEvent(rank: 100),
        song,
      ).debut!;
      expect(weekly.weekly, isTrue);
      expect(weekly.bubblingUnder, isFalse);
    });
  });

  group('dedup', () {
    NewReleaseDebut debut(ChartMomentEvent event) =>
        NewReleaseEligibility.evaluate(event, single('2026-11-01')).debut!;

    // User decision 2026-11-16: one new-release story per song across the
    // Weekly and Career charts (it used to be one per chart).
    test('one story per song across both charts, the first debut kept', () {
      final first = debut(debutEvent());
      final repeat = debut(
        debutEvent(weekStartUtc: DateTime.utc(2026, 11, 23), rank: 9),
      );
      final career = debut(
        debutEvent(
          scope: ChartMomentScope.allTime,
          occurredAt: DateTime.utc(2026, 11, 24),
        ),
      );

      final kept = NewReleaseEligibility.deduplicate([repeat, career, first]);
      expect(kept, [first]);
      expect(first.storyKey, 'new-release-debut:songs:song-dead');
      expect(career.storyKey, first.storyKey);
    });

    test('a career debut before the weekly chart closes is first', () {
      // The weekly week closes on 2026-11-23; the career debut was earlier.
      final weekly = debut(debutEvent());
      final career = debut(
        debutEvent(
          scope: ChartMomentScope.allTime,
          occurredAt: DateTime.utc(2026, 11, 20),
        ),
      );
      expect(NewReleaseEligibility.deduplicate([weekly, career]), [career]);
    });

    test('at the same effective time the Weekly chart is first', () {
      final weekly = debut(debutEvent());
      final career = debut(
        debutEvent(
          scope: ChartMomentScope.allTime,
          occurredAt: DateTime.utc(2026, 11, 23),
        ),
      );
      expect(NewReleaseEligibility.deduplicate([career, weekly]), [weekly]);
    });

    group('firstDebuts (user decision 2026-11-16: the first appearance '
        'on either chart, or none)', () {
      final start = NewReleaseDebutStart(DateTime.utc(2026, 11, 16));
      Map<String, ChartMomentEvent> first(
        List<ChartMomentEvent> events, {
        bool approved = true,
      }) => NewReleaseEligibility.firstDebuts(
        events,
        start: start,
        approved: approved,
      );

      test('live debuts are ignored; the first appearance after the start '
          'is chosen', () {
        final events = [
          debutEvent(
            scope: ChartMomentScope.live,
            weekStartUtc: DateTime.utc(2026, 11, 16),
          ),
          debutEvent(weekStartUtc: DateTime.utc(2026, 11, 23)),
        ];
        expect(first(events).keys, ['song-dead']);
        expect(
          first(events)['song-dead']!.weekStartUtc,
          DateTime.utc(2026, 11, 23),
        );
        // Switched off, nothing qualifies.
        expect(first(events, approved: false), isEmpty);
      });

      test('a career debut before the start: no delayed weekly '
          'new-release story', () {
        final events = [
          debutEvent(
            scope: ChartMomentScope.allTime,
            occurredAt: DateTime.utc(2026, 11, 15),
          ),
          debutEvent(weekStartUtc: DateTime.utc(2026, 11, 23)),
        ];
        expect(first(events), isEmpty);
        // Without the earlier debut the weekly one would be told.
        expect(first(events.sublist(1)).keys, ['song-dead']);
      });

      test('a weekly debut before the start: no delayed career '
          'new-release story', () {
        final events = [
          debutEvent(weekStartUtc: DateTime.utc(2026, 11, 2)),
          debutEvent(
            scope: ChartMomentScope.allTime,
            occurredAt: DateTime.utc(2026, 11, 20),
          ),
        ];
        expect(first(events), isEmpty);
        expect(first(events.sublist(1)).keys, ['song-dead']);
      });

      test('a first appearance that is a re-entry (an earlier debut not '
          'stored) is never told', () {
        final events = [
          debutEvent(
            type: ChartMomentEventType.reentry,
            weekStartUtc: DateTime.utc(2026, 11, 16),
          ),
          debutEvent(
            scope: ChartMomentScope.allTime,
            occurredAt: DateTime.utc(2026, 11, 25),
          ),
        ];
        expect(first(events), isEmpty);
      });

      test('a first debut that is not a candidate (earlier peak) is not '
          'replaced by a later one', () {
        final events = [
          debutEvent(weekStartUtc: DateTime.utc(2026, 11, 16), rank: null),
          debutEvent(
            scope: ChartMomentScope.allTime,
            occurredAt: DateTime.utc(2026, 11, 25),
          ),
        ];
        expect(first(events), isEmpty);
      });

      test('the same effective time prefers the Weekly chart', () {
        final weekly = debutEvent(weekStartUtc: DateTime.utc(2026, 11, 16));
        final career = debutEvent(
          scope: ChartMomentScope.allTime,
          occurredAt: DateTime.utc(2026, 11, 23),
        );
        expect(first([career, weekly])['song-dead'], weekly);
        expect(first([weekly, career])['song-dead'], weekly);
      });
    });

    test('a debut already told is never told again', () {
      final first = debut(debutEvent());
      expect(
        NewReleaseEligibility.deduplicate(
          [first],
          alreadyTold: {first.storyKey},
        ),
        isEmpty,
      );
    });

    test('the same events always give the same stories', () {
      final events = [
        debut(debutEvent()),
        debut(debutEvent(scope: ChartMomentScope.allTime)),
      ];
      final once = NewReleaseEligibility.deduplicate(events);
      final again = NewReleaseEligibility.deduplicate(events.reversed);
      expect(again, once);
    });
  });

  group('activation (approved 2026-11-16, prospective)', () {
    final from = DateTime.utc(2026, 12, 1, 12);
    final start = NewReleaseDebutStart(from);

    test('generation is approved in this build, and off means off', () {
      expect(NewReleaseDebutActivation.generationApproved, isTrue);
      expect(
        start.applies(
          debutEvent(weekStartUtc: DateTime.utc(2027)),
          approved: false,
        ),
        isFalse,
      );
      expect(
        NewReleaseDebutStart.none.applies(debutEvent(), approved: true),
        isFalse,
      );
    });

    test('weekly debuts start with the first chart week after activation', () {
      // The week running at activation keeps its earlier telling.
      expect(
        start.applies(
          debutEvent(weekStartUtc: DateTime.utc(2026, 11, 30)),
          approved: true,
        ),
        isFalse,
      );
      expect(
        start.applies(
          debutEvent(weekStartUtc: DateTime.utc(2026, 12, 7)),
          approved: true,
        ),
        isTrue,
      );
    });

    test('career debuts start at the activation instant', () {
      ChartMomentEvent at(DateTime instant) => debutEvent(
        scope: ChartMomentScope.allTime,
        weekStartUtc: DateTime.utc(2026, 11, 30),
        occurredAt: instant,
      );
      expect(
        start.applies(
          at(from.subtract(const Duration(seconds: 1))),
          approved: true,
        ),
        isFalse,
      );
      expect(start.applies(at(from), approved: true), isTrue);
    });

    test('live debuts never start', () {
      expect(
        start.applies(
          debutEvent(
            scope: ChartMomentScope.live,
            weekStartUtc: DateTime.utc(2027),
          ),
          approved: true,
        ),
        isFalse,
      );
    });
  });
}
