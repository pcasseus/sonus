// SN-50 F-Q25/F-Q26/A-Q29: the Moments feed is read a page at a time in
// whole days, filtered, marked when new, and opens surviving editions.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/moments_last_seen_store.dart';
import 'package:sonus_next/features/charts/domain/entities/all_time_chart.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/models/chart_week.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/presentation/controllers/charts_controller.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_category.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/charts/presentation/models/charts_presentation_mode.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_release_edition.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/song_edition_membership.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

import '../../support/all_time_chart_fakes.dart';
import '../../support/moment_page_fakes.dart';

void main() {
  group('paging', () {
    test('a first page tells whole days exactly as the full feed does, and '
        'reading on reaches the same feed', () async {
      final events = _mixedHistory();
      final full = await _controller(events: events, pageSize: 10000);
      final paged = await _controller(events: events, pageSize: 2);

      expect(paged.controller.hasMoreMoments, isTrue);
      expect(
        paged.moments.pageReads,
        lessThan(events.length ~/ 2),
        reason: 'a load reads a bounded number of pages',
      );

      final firstPage = _summary(paged.controller.momentStories);
      expect(firstPage, isNotEmpty);
      expect(
        firstPage,
        _summary(full.controller.momentStories).take(firstPage.length),
        reason: 'the loaded days tell the stories a full read tells',
      );

      while (paged.controller.hasMoreMoments) {
        await paged.controller.loadMoreMoments();
      }

      expect(
        _summary(paged.controller.momentStories),
        _summary(full.controller.momentStories),
      );
    });

    test('the daily cap counts the whole day, even across a page break', () {
      // Five minor debuts on one day: three are told, the first three.
      final day = DateTime(2026, 10, 20);
      final events = [
        for (var i = 0; i < 5; i++)
          _debut('cap-$i', at: day.add(Duration(hours: 9 + i)), rank: 150),
        _debut('older', at: DateTime(2026, 10, 18, 9), rank: 150),
        _debut('oldest', at: DateTime(2026, 10, 17, 9), rank: 150),
      ];

      return _controller(events: events, pageSize: 2).then((paged) {
        final titles = [
          for (final story in paged.controller.momentStories) story.facts.title,
        ];
        expect(titles, [
          'Song cap-2',
          'Song cap-1',
          'Song cap-0',
          'Song older',
          'Song oldest',
        ]);
      });
    });

    test('a failed page keeps the feed and can be tried again', () async {
      final paged = await _controller(events: _mixedHistory(), pageSize: 2);
      final before = paged.controller.momentStories.length;

      paged.moments.error = StateError('disk busy');
      await paged.controller.loadMoreMoments();

      expect(paged.controller.momentPageError, isA<StateError>());
      expect(paged.controller.momentStories, hasLength(before));

      paged.moments.error = null;
      await paged.controller.loadMoreMoments();

      expect(paged.controller.momentPageError, isNull);
      expect(
        paged.controller.momentStories.length,
        greaterThanOrEqualTo(before),
      );
    });
  });

  group('filters', () {
    test(
      'category and publisher narrow the feed; clearing shows it all',
      () async {
        final loaded = await _controller(events: _mixedHistory());
        final controller = loaded.controller;
        final all = controller.momentStories;

        controller.selectMomentCategory(MomentCategory.entries);
        expect(controller.visibleMomentStories, isNotEmpty);
        expect(
          controller.visibleMomentStories.map(
            (story) => MomentCategory.of(story.family),
          ),
          everyElement(MomentCategory.entries),
        );

        controller.selectMomentPublisher(MomentPublisher.sonusDaily);
        expect(
          controller.visibleMomentStories.map((story) => story.publisher),
          everyElement(MomentPublisher.sonusDaily),
        );

        controller
          ..selectMomentCategory(null)
          ..selectMomentPublisher(null);
        expect(controller.visibleMomentStories, all);
        expect(controller.isFilteringMoments, isFalse);
      },
    );
  });

  group('new-content dot', () {
    Future<void> openMoments(ChartsController controller) async {
      controller.selectPresentationMode(ChartsPresentationMode.moments);
      await pumpEventQueue();
      controller.selectPresentationMode(ChartsPresentationMode.charts);
    }

    test(
      'shows for stories newer than the last visit, until Moments opens',
      () async {
        final store = MemoryMomentsLastSeenStore.at(DateTime.utc(2026, 10, 1));
        final loaded = await _controller(events: _mixedHistory(), store: store);
        final controller = loaded.controller;

        expect(controller.hasNewMoments, isTrue);

        controller.selectPresentationMode(ChartsPresentationMode.moments);
        await pumpEventQueue();

        expect(controller.hasNewMoments, isFalse);
        final newest = controller.momentStories.first;
        expect(store.seen?.occurredAtUtc, newest.occurredAt.toUtc());
        expect(store.seen?.storyId, newest.id);

        controller.selectPresentationMode(ChartsPresentationMode.charts);
        expect(controller.hasNewMoments, isFalse);
      },
    );

    test('nothing newer than the last visit: no dot', () async {
      final store = MemoryMomentsLastSeenStore.at(DateTime.utc(2027));
      final loaded = await _controller(events: _mixedHistory(), store: store);

      expect(loaded.controller.hasNewMoments, isFalse);
      expect(store.writes, 0);
    });

    test('without a store there is never a dot', () async {
      final loaded = await _controller(events: _mixedHistory());

      expect(loaded.controller.hasNewMoments, isFalse);
    });

    test('R6: the first visit records a mark without a dot, even with '
        'older stories', () async {
      final store = MemoryMomentsLastSeenStore();
      final loaded = await _controller(events: _mixedHistory(), store: store);
      final controller = loaded.controller;

      expect(controller.momentStories, isNotEmpty);
      expect(controller.hasNewMoments, isFalse);
      expect(store.writes, 0);

      await openMoments(controller);

      expect(store.seen?.storyId, controller.momentStories.first.id);
      expect(controller.hasNewMoments, isFalse);
    });

    test('R6: a later story shows the dot; opening Moments clears it and '
        'reopening writes nothing more', () async {
      final store = MemoryMomentsLastSeenStore();
      final loaded = await _controller(events: _mixedHistory(), store: store);
      final controller = loaded.controller;
      await openMoments(controller);

      loaded.moments.events.add(
        _debut('later', at: DateTime(2026, 11, 5, 9), rank: 14),
      );
      await controller.refresh();
      expect(controller.hasNewMoments, isTrue);

      await openMoments(controller);
      expect(controller.hasNewMoments, isFalse);
      expect(store.seen?.occurredAtUtc, DateTime(2026, 11, 5, 9).toUtc());
      final writes = store.writes;

      await openMoments(controller);
      await controller.refresh();
      expect(store.writes, writes);
      expect(controller.hasNewMoments, isFalse);
    });

    test('R6: stories at one instant are ordered by id, so the mark is '
        'the same whichever order they are read in', () async {
      final at = DateTime(2026, 11, 4, 9);
      Future<MomentsSeenMark?> markOf(List<ChartMomentEvent> events) async {
        final store = MemoryMomentsLastSeenStore();
        final loaded = await _controller(events: events, store: store);
        await openMoments(loaded.controller);
        return store.seen;
      }

      final forward = await markOf([
        _debut('a', at: at, rank: 14),
        _debut('b', at: at, rank: 16),
      ]);
      final backward = await markOf([
        _debut('b', at: at, rank: 16),
        _debut('a', at: at, rank: 14),
      ]);

      expect(forward?.occurredAtUtc, at.toUtc());
      expect(backward?.storyId, forward?.storyId);
      expect(forward!.isOlderThan(at, '${forward.storyId}~'), isTrue);
      expect(forward.isOlderThan(at, forward.storyId), isFalse);
      expect(forward.isOlderThan(at, ''), isFalse);
    });

    test('R6: a story synced in with an earlier time than the mark shows '
        'no dot', () async {
      final store = MemoryMomentsLastSeenStore();
      final loaded = await _controller(events: _mixedHistory(), store: store);
      final controller = loaded.controller;
      await openMoments(controller);
      final mark = store.seen;

      loaded.moments.events.add(
        _debut('backdated', at: DateTime(2026, 11, 2, 23), rank: 14),
      );
      await controller.refresh();

      expect(
        controller.momentStories.map((story) => story.facts.title),
        contains('Song backdated'),
      );
      expect(controller.hasNewMoments, isFalse);
      expect(store.seen, same(mark));
    });

    test('R6: a mark lost to a preferences restore shows no dot and is '
        'recorded again on the next visit', () async {
      final store = MemoryMomentsLastSeenStore();
      final first = await _controller(events: _mixedHistory(), store: store);
      await openMoments(first.controller);

      store.seen = null;
      final restored = await _controller(
        events: [
          ..._mixedHistory(),
          _debut('after-restore', at: DateTime(2026, 11, 5, 9), rank: 14),
        ],
        store: store,
      );

      expect(restored.controller.hasNewMoments, isFalse);
      await openMoments(restored.controller);
      expect(store.seen?.occurredAtUtc, DateTime(2026, 11, 5, 9).toUtc());
    });

    test('R6: a feed first seen empty shows the dot for its first '
        'story', () async {
      final store = MemoryMomentsLastSeenStore();
      final loaded = await _controller(events: [], store: store);
      final controller = loaded.controller;
      await openMoments(controller);

      expect(store.seen?.occurredAtUtc, isNull);
      expect(controller.hasNewMoments, isFalse);

      loaded.moments.events.add(
        _debut('first', at: DateTime(2026, 11, 5, 9), rank: 14),
      );
      await controller.refresh();
      expect(controller.hasNewMoments, isTrue);
    });
  });

  group('opening a song Moment', () {
    final when = DateTime(2026, 11, 3, 12);

    Future<MomentReleaseTarget?> open({
      required List<LibraryAlbumEdition> editions,
      String? playEdition,
      List<LibraryTrack>? tracks,
    }) async {
      final loaded = await _controller(
        events: [_debut('home', at: when, rank: 20, source: 'play-1')],
        tracks: tracks ?? [_track('home')],
        editions: editions,
        playEditions: {'play-1': ?playEdition},
      );
      final item = loaded.controller.momentStories.single.item;
      return loaded.controller.releaseTargetForMoment(item);
    }

    test('opens the edition the play was of while it survives', () async {
      final target = await open(
        editions: [_edition('primary', primary: true), _edition('deluxe')],
        playEdition: 'deluxe',
      );

      expect(target?.editionId, 'deluxe');
      expect(target?.editionRemoved, isFalse);
    });

    test('a removed edition opens the primary edition and says so', () async {
      final target = await open(
        editions: [_edition('primary', primary: true)],
        playEdition: 'deleted-deluxe',
      );

      expect(target?.editionId, 'primary');
      expect(target?.editionRemoved, isTrue);
    });

    test('without a recorded play it opens the song\'s own edition', () async {
      final target = await open(editions: [_edition('primary', primary: true)]);

      expect(target?.editionId, 'edition-album-1');
      expect(target?.editionRemoved, isFalse);
    });

    test('a purged song has no release link and no invented record', () async {
      final target = await open(editions: const [], tracks: const []);

      expect(target, isNull);
    });
  });

  group('covers and credits', () {
    test('SN-50 song stories show the song\'s own picture, earlier ones '
        'too (approved device QA correction)', () async {
      final loaded = await _controller(
        events: [
          _debut('new', at: DateTime(2026, 11, 3, 12), rank: 20),
          _debut('old', at: DateTime(2026, 10, 20, 12), rank: 20),
        ],
        tracks: [
          _track('new', artworkPath: '/art/deluxe-new.jpg'),
          _track('old', artworkPath: '/art/deluxe-old.jpg'),
        ],
      );
      final byTitle = {
        for (final story in loaded.controller.momentStories)
          story.facts.title: story,
      };

      expect(byTitle['Song new']!.visual.left.path, '/art/deluxe-new.jpg');
      expect(byTitle['Song old']!.visual.left.path, '/art/deluxe-old.jpg');
    });

    test('SN-50 song stories name every performer; earlier stories and '
        'solo songs show no credit line', () async {
      final loaded = await _controller(
        events: [
          _debut('duet', at: DateTime(2026, 11, 3, 12), rank: 20),
          _debut('solo', at: DateTime(2026, 11, 3, 11), rank: 30),
          _debut('older', at: DateTime(2026, 10, 20, 12), rank: 20),
        ],
        tracks: [
          _track('duet', featured: const ['Bo Vale', 'Cy Rune']),
          _track('solo'),
          _track('older', featured: const ['Bo Vale']),
        ],
      );
      final credits = {
        for (final story in loaded.controller.momentStories)
          story.facts.title: loaded.controller.creditForMoment(story),
      };

      expect(credits['Song duet'], 'Ada Lune Ft. Bo Vale, Cy Rune');
      expect(credits['Song solo'], isNull);
      expect(credits['Song older'], isNull);
    });

    test('SN-50 reconciliation: a refined release Moment shows the Deluxe '
        'cover; a pre-activation release Moment now shows it '
        'too', () async {
      Future<String?> coverOf(DateTime at) async {
        final loaded = await _controller(
          events: [_releaseDebut('one', at: at)],
          tracks: [_track('one')],
          editions: [_edition('primary', primary: true), _edition('deluxe')],
          releaseEditions: _longerDeluxe,
        );
        final story = loaded.controller.momentStories.singleWhere(
          (story) => story.item.chartType == ChartType.albums,
        );
        expect(story.facts.refined, at.isAfter(DateTime(2026, 11, 1, 12)));
        return story.visual.left.path;
      }

      expect(await coverOf(DateTime(2026, 11, 3, 12)), '/art/deluxe.jpg');
      expect(await coverOf(DateTime(2026, 10, 20, 12)), '/art/deluxe.jpg');
    });
  });

  group('App Update 1.1: song stories show the edition the song first '
      'appeared on', () {
    final at = DateTime(2026, 11, 3, 12);
    Future<List<SongEditionMembership>> memberships() async => const [
      SongEditionMembership(songId: 'song-both', editionId: 'primary'),
      SongEditionMembership(songId: 'song-both', editionId: 'deluxe'),
      SongEditionMembership(songId: 'song-bonus', editionId: 'deluxe'),
    ];

    test('a song on both editions shows the Standard cover, a Deluxe-only '
        'song the Deluxe cover, the release the Deluxe', () async {
      final loaded = await _controller(
        events: [
          _releaseDebut('one', at: at),
          _debut('both', at: at, rank: 20),
          _debut('bonus', at: at.add(const Duration(minutes: 1)), rank: 21),
        ],
        tracks: [
          _track(
            'both',
            artworkPath: '/art/song-both.jpg',
            albumEditionId: 'primary',
          ),
          _track(
            'bonus',
            artworkPath: '/art/song-bonus.jpg',
            albumEditionId: 'deluxe',
          ),
        ],
        editions: [_edition('primary', primary: true), _edition('deluxe')],
        releaseEditions: _locket,
        memberships: memberships,
      );
      final covers = {
        for (final story in loaded.controller.momentStories)
          story.item.entity.entityId: story.visual.left.path,
      };

      expect(covers['song-both'], '/art/standard.jpg');
      expect(covers['song-bonus'], '/art/deluxe.jpg');
      expect(covers['album-1'], '/art/deluxe.jpg');
      expect(
        loaded.controller.momentSongEditionTitle('song-both'),
        'Album One',
      );
      expect(
        loaded.controller.momentSongEditionTitle('song-bonus'),
        'Album One (Deluxe)',
      );
      expect(loaded.controller.momentSongEditionTitle('missing'), isNull);
    });

    test("a failed membership read keeps the song's own artwork", () async {
      final loaded = await _controller(
        events: [_debut('both', at: at, rank: 20)],
        tracks: [
          _track(
            'both',
            artworkPath: '/art/song-both.jpg',
            albumEditionId: 'primary',
          ),
        ],
        releaseEditions: _locket,
        memberships: () async => throw StateError('read failed'),
      );

      expect(
        loaded.controller.momentStories.single.visual.left.path,
        '/art/song-both.jpg',
      );
      expect(loaded.controller.momentSongEditionTitle('song-both'), isNull);
    });
  });

  group('the release is presented by its edition with the most songs', () {
    final at = DateTime(2026, 11, 3, 12);

    test('a shorter Deluxe leaves the standard cover on release stories, '
        "while a Deluxe-only song keeps its own edition's picture", () async {
      final loaded = await _controller(
        events: [
          _releaseDebut('one', at: at),
          _debut('bonus', at: at, rank: 20),
        ],
        // The library resolves a Deluxe-only song's picture from the
        // edition it lives on (A-Q12/A-Q13).
        tracks: [_track('bonus', artworkPath: '/art/deluxe.jpg')],
        editions: [_edition('primary', primary: true), _edition('deluxe')],
        releaseEditions: _shorterDeluxe,
      );
      final stories = loaded.controller.momentStories;
      final release = stories.singleWhere(
        (story) => story.item.chartType == ChartType.albums,
      );
      final song = stories.singleWhere(
        (story) => story.item.chartType == ChartType.songs,
      );

      expect(release.visual.left.path, '/art/primary.jpg');
      expect(song.visual.left.path, '/art/deluxe.jpg');
    });

    test('a longer Deluxe gives release stories its cover and opens it; '
        "the story's words stay as recorded", () async {
      final loaded = await _controller(
        events: [_releaseDebut('one', at: at)],
        tracks: [_track('one')],
        editions: [_edition('primary', primary: true), _edition('deluxe')],
        releaseEditions: _longerDeluxe,
      );
      final story = loaded.controller.momentStories.single;
      final target = await loaded.controller.releaseTargetForMoment(story.item);

      expect(story.visual.left.path, '/art/deluxe.jpg');
      expect(story.facts.title, 'Album One');
      expect(target?.editionId, 'deluxe');
    });

    test('the release button names the edition a refined story opens; '
        'earlier stories keep the recorded name', () async {
      final loaded = await _controller(
        events: [
          _releaseDebut('new', at: at),
          _releaseDebut('old', at: DateTime(2026, 10, 20, 12)),
          _debut('song', at: at, rank: 20),
        ],
        tracks: [_track('song')],
        editions: [_edition('primary', primary: true), _edition('deluxe')],
        releaseEditions: _longerDeluxe,
      );
      final titles = {
        for (final story in loaded.controller.momentStories)
          story.item.id: loaded.controller.releaseTitleForMoment(story.item),
      };

      expect(titles.values.whereType<String>(), ['Album One (Deluxe)']);
      expect(titles.length, 3);
    });

    test('a shorter Deluxe opens the primary edition', () async {
      final loaded = await _controller(
        events: [_releaseDebut('one', at: at)],
        tracks: [_track('one')],
        editions: [_edition('primary', primary: true), _edition('deluxe')],
        releaseEditions: _shorterDeluxe,
      );
      final target = await loaded.controller.releaseTargetForMoment(
        loaded.controller.momentStories.single.item,
      );

      expect(target?.editionId, 'primary');
    });
  });
}

/// Shaped like locket by Madison Beer: Standard (12 tracks, 2026-01-16)
/// and Deluxe (15 tracks, 2026-05-08).
final _locket = [
  LibraryReleaseEdition(
    edition: LibraryAlbumEdition(
      editionId: 'primary',
      albumId: 'album-1',
      title: 'Album One',
      type: AlbumEditionType.standard,
      isPrimary: true,
      dateAdded: DateTime.utc(2026, 9, 1),
      releaseDate: DateTime.utc(2026, 1, 16),
      releaseDatePrecision: ReleaseDatePrecision.day,
      artworkPath: '/art/standard.jpg',
    ),
    trackCount: 12,
  ),
  LibraryReleaseEdition(
    edition: LibraryAlbumEdition(
      editionId: 'deluxe',
      albumId: 'album-1',
      title: 'Album One (Deluxe)',
      type: AlbumEditionType.deluxe,
      isPrimary: false,
      dateAdded: DateTime.utc(2026, 9, 1),
      releaseDate: DateTime.utc(2026, 5, 8),
      releaseDatePrecision: ReleaseDatePrecision.day,
      artworkPath: '/art/deluxe.jpg',
    ),
    trackCount: 15,
  ),
];

LibraryReleaseEdition _countedEdition(
  String id, {
  required int tracks,
  bool primary = false,
  String? artworkPath,
}) => LibraryReleaseEdition(
  edition: LibraryAlbumEdition(
    editionId: id,
    albumId: 'album-1',
    title: primary ? 'Album One' : 'Album One (Deluxe)',
    type: primary ? AlbumEditionType.standard : AlbumEditionType.deluxe,
    isPrimary: primary,
    dateAdded: DateTime.utc(2026, 9, 1),
    artworkPath: artworkPath,
  ),
  trackCount: tracks,
);

final _longerDeluxe = [
  _countedEdition('primary', tracks: 12, primary: true),
  _countedEdition('deluxe', tracks: 16, artworkPath: '/art/deluxe.jpg'),
];

final _shorterDeluxe = [
  _countedEdition('primary', tracks: 12, primary: true),
  _countedEdition('deluxe', tracks: 4, artworkPath: '/art/deluxe.jpg'),
];

/// What a reader sees of each story.
List<String> _summary(List<MomentStory> stories) => [
  for (final story in stories)
    '${story.id}|${story.publisher.name}|${story.headline}|${story.body}',
];

/// Days of real-time debuts before and after the SN-50 rules, several per
/// day so the daily cap and headline variety both apply.
List<ChartMomentEvent> _mixedHistory() => [
  for (final day in [
    DateTime(2026, 10, 29),
    DateTime(2026, 10, 30),
    DateTime(2026, 10, 31),
    DateTime(2026, 11, 1),
    DateTime(2026, 11, 2),
    DateTime(2026, 11, 4),
  ])
    for (var i = 0; i < 5; i++)
      _debut(
        '${day.month}-${day.day}-$i',
        at: day.add(Duration(hours: 8 + i)),
        rank: i.isEven ? 150 : 12 + i,
      ),
];

ChartMomentEvent _debut(
  String id, {
  required DateTime at,
  required int rank,
  String? source,
}) {
  final week = DateTime.utc(2026, 10, 25);
  final song = ChartEntitySnapshot(
    entityId: 'song-$id',
    title: 'Song $id',
    artistId: 'artist-1',
    artistName: 'Ada Lune',
    albumTitle: 'Album One',
  );

  return ChartMomentEvent(
    id: 'debut-$id',
    deduplicationKey: 'debut-$id',
    sourceId: source ?? 'play-$id',
    chartType: ChartType.songs,
    scope: ChartMomentScope.allTime,
    eventType: ChartMomentEventType.debut,
    entity: song,
    weekStartUtc: week,
    weekEndUtc: week.add(const Duration(days: 7)),
    occurredAt: at.toUtc(),
    createdAt: at.toUtc(),
    currentRank: rank,
    currentPeakRank: rank,
    qualifiedStreamCount: 1,
  );
}

ChartMomentEvent _releaseDebut(String id, {required DateTime at}) {
  final week = DateTime.utc(2026, 10, 25);
  return ChartMomentEvent(
    id: 'release-debut-$id',
    deduplicationKey: 'release-debut-$id',
    sourceId: 'play-release-$id',
    chartType: ChartType.albums,
    scope: ChartMomentScope.allTime,
    eventType: ChartMomentEventType.debut,
    entity: const ChartEntitySnapshot(
      entityId: 'album-1',
      title: 'Album One',
      artistId: 'artist-1',
      artistName: 'Ada Lune',
    ),
    weekStartUtc: week,
    weekEndUtc: week.add(const Duration(days: 7)),
    occurredAt: at.toUtc(),
    createdAt: at.toUtc(),
    currentRank: 20,
    currentPeakRank: 20,
    qualifiedStreamCount: 1,
  );
}

LibraryTrack _track(
  String id, {
  String? artworkPath,
  String albumEditionId = 'edition-album-1',
  List<String> featured = const [],
}) => LibraryTrack(
  songId: 'song-$id',
  title: 'Song $id',
  artistId: 'artist-1',
  artistName: 'Ada Lune',
  albumId: 'album-1',
  albumTitle: 'Album One',
  albumEditionId: albumEditionId,
  albumEditionTitle: 'Album One',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: featured,
  dateAdded: DateTime.utc(2026, 9, 1),
  isAvailable: true,
  filePath: 'C:/Music/$id.mp3',
  artworkPath: artworkPath,
);

LibraryAlbumEdition _edition(String id, {bool primary = false}) =>
    LibraryAlbumEdition(
      editionId: id,
      albumId: 'album-1',
      title: primary ? 'Album One' : 'Album One (Deluxe)',
      type: primary ? AlbumEditionType.standard : AlbumEditionType.deluxe,
      isPrimary: primary,
      dateAdded: DateTime.utc(2026, 9, 1),
    );

Future<({ChartsController controller, _PagedMoments moments})> _controller({
  required List<ChartMomentEvent> events,
  int pageSize = 200,
  MomentsLastSeenStore? store,
  List<LibraryTrack>? tracks,
  List<LibraryAlbumEdition> editions = const [],
  Map<String, String> playEditions = const {},
  List<LibraryReleaseEdition>? releaseEditions,
  SongEditionMembershipsLoader? memberships,
}) async {
  final moments = _PagedMoments(events);
  final controller = ChartsController(
    allTimeCharts: _EmptyAllTimeCharts(),
    finalization: _NoFinalization(),
    charts: _NoHistory(),
    library: _EditionLibrary(
      tracks: tracks ?? const [],
      albums: [
        LibraryAlbum(
          albumId: 'album-1',
          title: 'Album One',
          artistId: 'artist-1',
          artistName: 'Ada Lune',
          trackCount: 1,
          dateAdded: DateTime.utc(2026, 9, 1),
          artworkPath: '/art/primary.jpg',
          primaryEditionId: 'primary',
        ),
      ],
      editions: editions,
    ),
    moments: moments,
    now: () => DateTime(2026, 11, 5, 12),
    momentsLastSeen: store,
    playEdition: (playId) async => playEditions[playId],
    releaseEditions: releaseEditions == null
        ? null
        : () async => releaseEditions,
    songEditionMemberships: memberships,
    momentPageSize: pageSize,
    momentRules: () async =>
        ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 11, 1)),
  );
  addTearDown(controller.dispose);

  await controller.load();
  await pumpEventQueue();

  return (controller: controller, moments: moments);
}

class _PagedMoments implements ChartMomentRepository {
  _PagedMoments(this.events);

  final List<ChartMomentEvent> events;
  Object? error;
  int pageReads = 0;

  @override
  Future<List<ChartMomentEvent>> getPage({
    ChartMomentPageCursor? before,
    required int limit,
  }) async {
    pageReads++;
    final error = this.error;
    if (error != null) throw error;
    return momentPageOf(events, before: before, limit: limit);
  }

  @override
  Future<List<ChartMomentEvent>> getRecent({int? limit}) async =>
      momentPageOf(events, limit: limit ?? events.length);

  @override
  Future<ChartMomentEvent?> getById(String id) async => null;

  @override
  Future<void> saveAll(Iterable<ChartMomentEvent> events) async {}

  @override
  Future<bool> publishFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  }) async => false;
}

class _EditionLibrary extends FakeChartLibrary
    implements AlbumEditionQueryRepository {
  _EditionLibrary({
    required super.tracks,
    required super.albums,
    required this.editions,
  });

  final List<LibraryAlbumEdition> editions;

  @override
  Future<List<LibraryAlbumEdition>> getAlbumEditions(String albumId) async => [
    for (final edition in editions)
      if (edition.albumId == albumId) edition,
  ];

  @override
  Future<List<LibraryTrack>> getTracksByAlbumEditionId(String editionId) =>
      throw UnimplementedError();
}

class _EmptyAllTimeCharts implements AllTimeChartService {
  @override
  Future<AllTimeChart> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    ChartViewSize viewSize = ChartViewSize.top100,
  }) async => AllTimeChart(
    chartType: chartType,
    comparisonStartUtc: DateTime.utc(2026, 10, 25),
    entries: const [],
  );
}

class _NoFinalization implements ChartFinalizationService {
  @override
  Future<List<ChartSnapshot>> finalizeCompletedWeeks({
    required DateTime referenceLocal,
  }) async => const [];

  @override
  Future<List<ChartSnapshot>> finalizePreviousCompletedWeek({
    required DateTime referenceLocal,
  }) => throw UnimplementedError();

  @override
  Future<List<ChartSnapshot>> reconcileCompletedWeek(ChartWeek week) =>
      throw UnimplementedError();
}

class _NoHistory implements ChartRepository {
  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async => const [];

  @override
  Future<ChartSnapshot?> getById(String id) async => null;

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) async => null;

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) async {}
}
