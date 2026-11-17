// App Update 1.3 new-release debuts through the real ChartsController:
// the controller reads release facts and every stored song debut since the
// write-once start, so a song's one new-release story is the same however
// much of the feed is paged in; with approval off nothing is read and no
// story changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/chart_schema.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_repository.dart';
import 'package:sonus_next/features/charts/data/services/sqlite_new_release_evidence_reader.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_deletion_journal_reader.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_new_release_publication_repository.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_eligibility.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/features/charts/application/models/new_release_library_facts.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/new_release_publication_store.dart';
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
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_release_edition.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/domain/entities/song_single_presentation.dart';

import '../../support/all_time_chart_fakes.dart';
import '../../support/moment_page_fakes.dart';
import '../../support/new_release_publication_fakes.dart';

final _start = DateTime.utc(2026, 11, 15);
final _week1 = _start;
final _week2 = _start.add(const Duration(days: 7));

const _dead = ChartEntitySnapshot(
  entityId: 'song-dead',
  title: 'Dead',
  artistId: 'artist-1',
  artistName: 'Madison Beer',
);

void main() {
  // The career debut comes first (Tuesday of week 1); the weekly debut of
  // week 1 is published after the week closes. Three days of other news in
  // between keep the career debut off the first page.
  final careerDebut = _event(
    _dead,
    scope: ChartMomentScope.allTime,
    weekStart: _week1,
    at: _week1.add(const Duration(days: 2, hours: 10)),
    rank: 45,
  );
  final weeklyDebut = _event(
    _dead,
    scope: ChartMomentScope.finalized,
    weekStart: _week1,
    at: _week2.add(const Duration(hours: 9)),
    rank: 12,
  );
  final events = [
    careerDebut,
    weeklyDebut,
    for (var day = 1; day <= 3; day++)
      _event(
        ChartEntitySnapshot(
          entityId: 'song-other-$day',
          title: 'Other $day',
          artistId: 'artist-2',
          artistName: 'Someone Else',
        ),
        scope: ChartMomentScope.allTime,
        weekStart: _week1,
        at: _week1.add(Duration(days: 2 + day, hours: 12)),
        rank: 60 + day,
      ),
  ];

  bool isNewRelease(MomentStory story) =>
      story.variantId.startsWith('new-release-');

  MomentStory? storyOf(ChartsController controller, ChartMomentEvent event) {
    for (final story in controller.momentStories) {
      if (story.item.events.any((e) => e.id == event.id)) return story;
    }
    return null;
  }

  test('approved: the first debut (career) is the new single, on the first '
      'page and after reading every page', () async {
    final loaded = await _load(events, pageSize: 1, approved: true);
    final controller = loaded.controller;

    expect(controller.hasMoreMoments, isTrue);
    expect(storyOf(controller, careerDebut), isNull, reason: 'not loaded');
    final firstPage = storyOf(controller, weeklyDebut)!;
    expect(isNewRelease(firstPage), isFalse);

    while (controller.hasMoreMoments) {
      await controller.loadMoreMoments();
    }

    expect(
      storyOf(controller, careerDebut)!.headline,
      'Madison Beer debuts new single "Dead" on the Career Sonus Hot 100 at '
      '#45.',
    );
    expect(storyOf(controller, weeklyDebut)!.headline, firstPage.headline);
    expect(controller.momentStories.where(isNewRelease), hasLength(1));
    expect(loaded.historyReads, [_start]);
  });

  test('not approved (this build): nothing is read and the feed is '
      'unchanged', () async {
    final off = await _load(events, approved: false);
    final without = await _load(events, approved: false, loaders: false);

    expect(off.classificationReads, 0);
    expect(off.historyReads, isEmpty);
    expect(off.controller.momentStories.where(isNewRelease), isEmpty);
    expect(
      [for (final s in off.controller.momentStories) (s.id, s.headline)],
      [for (final s in without.controller.momentStories) (s.id, s.headline)],
    );
  });

  test('the default approval is on (approved 2026-11-16)', () async {
    final defaults = await _load(events, approved: null);
    final approved = await _load(events, approved: true);
    expect(defaults.historyReads, approved.historyReads);
    expect(
      [for (final s in defaults.controller.momentStories) (s.id, s.headline)],
      [for (final s in approved.controller.momentStories) (s.id, s.headline)],
    );
  });

  test('a Single date or album edition written after the debut: no new '
      'story (rule 1, from the stored write times)', () async {
    final late = DateTime.utc(2026, 11, 20);
    for (final library in [
      _LibraryState(writtenAt: late),
      _LibraryState(isSingle: false, writtenAt: late),
    ]) {
      final loaded = await _load(events, approved: true, library: library);
      expect(
        loaded.controller.momentStories.where(isNewRelease),
        isEmpty,
        reason: 'single: ${library.isSingle}',
      );
    }
    // Written before the debut: told, as a Single and as an album track.
    for (final library in const [
      _LibraryState(),
      _LibraryState(isSingle: false),
    ]) {
      final loaded = await _load(events, approved: true, library: library);
      expect(loaded.controller.momentStories.where(isNewRelease), hasLength(1));
    }
  });

  test('the proof cannot be read: no new story (fails closed)', () async {
    final loaded = await _load(
      events,
      approved: true,
      evidence: (_) async => throw StateError('unreadable'),
    );
    expect(loaded.controller.momentStories.where(isNewRelease), isEmpty);
  });

  test('approved but no recorded start: nothing is read or told', () async {
    final loaded = await _load(events, approved: true, start: false);
    expect(loaded.historyReads, isEmpty);
    expect(loaded.controller.momentStories.where(isNewRelease), isEmpty);
  });

  // User decision 2026-11-16: a stable publication record. Real SQLite, so
  // restarts, edits and racing loads go through the stored row.
  group('publication records', () {
    late AppDatabase database;
    late SqliteNewReleasePublicationRepository store;

    setUp(() {
      sqfliteFfiInit();
      database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      store = SqliteNewReleasePublicationRepository(database);
    });
    tearDown(() => database.close());

    const single =
        'Madison Beer debuts new single "Dead" on the Career Sonus Hot 100 '
        'at #45.';
    const albumTrack =
        '"Dead" by Madison Beer debuts at #45 on the Career Sonus Hot 100 '
        'from the new album Locket.';

    Future<String?> told(_Loaded loaded) async {
      final headline = storyOf(loaded.controller, careerDebut)?.headline;
      await loaded.controller.newReleaseWritesSettled;
      return headline;
    }

    test('a shown story is recorded once, then told from the record after '
        'reloads and restarts', () async {
      final first = await _load(events, approved: true, publications: store);
      expect(await told(first), single);

      final stored = await store.readAll();
      expect(stored.keys, [_dead.entityId]);
      final record = stored[_dead.entityId]!;
      expect(record.headline, single);
      expect(record.eventKey, careerDebut.deduplicationKey);
      expect(record.eventId, careerDebut.id);
      expect(record.storyId, storyOf(first.controller, careerDebut)!.id);
      expect(record.kind, NewReleaseDebutKind.single);
      expect(record.scope, ChartMomentScope.allTime);
      expect(record.rank, 45);
      expect(record.releaseDate, ReleaseDate.of(2026, 11, 7));
      expect(record.publishedAtUtc, DateTime.utc(2026, 11, 26, 12));

      // A reload, then a restart (a new controller over the same rows).
      await first.controller.load();
      expect(await told(first), single);
      final restarted = await _load(
        events,
        approved: true,
        publications: store,
      );
      expect(await told(restarted), single);
      expect(await store.readAll(), stored);
    });

    test('library edits after publication never rewrite it', () async {
      final first = await _load(
        events,
        approved: true,
        publications: store,
        library: const _LibraryState(isSingle: false),
      );
      expect(await told(first), albumTrack);
      final stored = await store.readAll();

      // Each would tell another headline, or none, if it were composed
      // again from the library.
      const edits = [
        _LibraryState(isSingle: false, albumTitle: 'Locket (Renamed)'),
        _LibraryState(isSingle: false, songTitle: 'Dead (Renamed)'),
        _LibraryState(isSingle: false, albumDate: '2019-05-01'),
        _LibraryState(isSingle: false, featured: ['Kehlani']),
        // Switched to a Single, with and without its own new date.
        _LibraryState(),
        _LibraryState(singleDate: null),
        _LibraryState(singleDate: '2026-12-01'),
      ];
      for (final edit in edits) {
        final later = await _load(
          events,
          approved: true,
          publications: store,
          library: edit,
        );
        final story = storyOf(later.controller, careerDebut)!;
        expect(story.headline, albumTrack, reason: '$edit');
        expect(story.body ?? '', isNot(contains('Kehlani')));
        await later.controller.newReleaseWritesSettled;
      }
      expect(await store.readAll(), stored);
    });

    test('paging: recorded only when shown, one record across every '
        'page', () async {
      final paged = await _load(
        events,
        pageSize: 1,
        approved: true,
        publications: store,
      );
      final controller = paged.controller;
      expect(storyOf(controller, careerDebut), isNull, reason: 'not loaded');
      await controller.newReleaseWritesSettled;
      expect(await store.readAll(), isEmpty);

      while (controller.hasMoreMoments) {
        await controller.loadMoreMoments();
        controller.momentStories;
        await controller.newReleaseWritesSettled;
      }
      expect(await told(paged), single);
      expect((await store.readAll()).keys, [_dead.entityId]);

      final restarted = await _load(
        events,
        pageSize: 1,
        approved: true,
        publications: store,
      );
      while (restarted.controller.hasMoreMoments) {
        await restarted.controller.loadMoreMoments();
      }
      expect(await told(restarted), single);
      expect(await store.readAll(), hasLength(1));
    });

    test(
      'two loads racing write one record; the other then tells it',
      () async {
        // Different library states, so each would compose another record.
        final asSingle = await _load(
          events,
          approved: true,
          publications: store,
          settle: false,
        );
        final asAlbumTrack = await _load(
          events,
          approved: true,
          publications: store,
          library: const _LibraryState(isSingle: false),
          settle: false,
        );
        await Future.wait([
          asSingle.controller.load(),
          asAlbumTrack.controller.load(),
        ]);
        final headlines = [
          storyOf(asSingle.controller, careerDebut)!.headline,
          storyOf(asAlbumTrack.controller, careerDebut)!.headline,
        ];
        await asSingle.controller.newReleaseWritesSettled;
        await asAlbumTrack.controller.newReleaseWritesSettled;
        await pumpEventQueue();

        final stored = await store.readAll();
        expect(stored, hasLength(1));
        final kept = stored[_dead.entityId]!.headline;
        expect(headlines, contains(kept));
        expect(storyOf(asSingle.controller, careerDebut)!.headline, kept);
        expect(storyOf(asAlbumTrack.controller, careerDebut)!.headline, kept);
      },
    );

    test('a restore during the load: nothing is stored from what it read; '
        'the next load records it', () async {
      final memory = MemoryNewReleasePublications();
      final interrupted = await _load(
        events,
        approved: true,
        publications: memory,
        duringRead: () async => memory.restoreGeneration++,
      );
      expect(await told(interrupted), single);
      expect(memory.writes, hasLength(1));
      expect(memory.records, isEmpty);
      // Not sent again with the same stale facts.
      interrupted.controller.momentStories;
      await interrupted.controller.newReleaseWritesSettled;
      expect(memory.writes, hasLength(1));

      final next = await _load(events, approved: true, publications: memory);
      expect(await told(next), single);
      expect(memory.records.keys, [_dead.entityId]);
    });

    // User rules 2026-11-16, with the proof read from this database by the
    // real evidence reader.
    group('proof read from the database', () {
      late NewReleaseEvidenceLoader evidence;
      setUp(() {
        evidence = SqliteNewReleaseEvidenceReader(
          database,
          historyOriginUtc: SqliteChartRepository(
            database,
          ).chartHistoryOriginUtc,
          momentsCutoffUtc: SqliteDeletionJournalReader(
            () async => database.database,
          ).momentsCutoff,
        ).read;
      });

      Future<void> historyBegan(DateTime at) async =>
          ChartSchema.resetChartHistoryOrigin(await database.database, at);

      Future<void> played(DateTime at) async {
        final db = await database.database;
        final stamp = at.toUtc().toIso8601String();
        await db.insert(DatabaseTables.playbackSessions, {
          'id': 'session-$stamp',
          'song_id': _dead.entityId,
          'artist_id': 'artist-1',
          'album_id': 'album-1',
          'album_edition_id': 'edition-1',
          'song_title': 'Dead',
          'artist_name': 'Madison Beer',
          'album_title': 'Locket',
          'album_edition_title': 'Locket',
          'started_at': stamp,
          'created_at': stamp,
          'updated_at': stamp,
        });
        await db.insert(DatabaseTables.qualifiedPlays, {
          'id': 'play-$stamp',
          'playback_session_id': 'session-$stamp',
          'song_id': _dead.entityId,
          'artist_id': 'artist-1',
          'album_id': 'album-1',
          'album_edition_id': 'edition-1',
          'qualified_at': stamp,
          'listened_duration_ms': 60000,
          'track_duration_ms': 180000,
          'created_at': stamp,
        });
      }

      Future<_Loaded> load() => _load(
        events,
        approved: true,
        publications: store,
        evidence: evidence,
      );

      test('proven here: told and recorded once', () async {
        await historyBegan(DateTime.utc(2026, 11, 1));
        await played(_week1.add(const Duration(days: 2, hours: 9)));
        expect(await told(await load()), single);
        expect((await store.readAll()).keys, [_dead.entityId]);
      });

      test('first played before the start: no special story, nothing '
          'recorded', () async {
        await historyBegan(DateTime.utc(2026, 11, 1));
        await played(DateTime.utc(2026, 11, 3));
        await played(_week1.add(const Duration(days: 2, hours: 9)));
        final loaded = await load();
        expect(loaded.controller.momentStories.where(isNewRelease), isEmpty);
        await loaded.controller.newReleaseWritesSettled;
        expect(await store.readAll(), isEmpty);
      });

      test('a restored database: the older debuts are not published as '
          'new', () async {
        await played(_week1.add(const Duration(days: 2, hours: 9)));
        // The restore starts this database's chart history again.
        await historyBegan(DateTime.utc(2026, 11, 25, 8));
        final loaded = await load();
        expect(loaded.controller.momentStories.where(isNewRelease), isEmpty);
        await loaded.controller.newReleaseWritesSettled;
        expect(await store.readAll(), isEmpty);
      });

      test('a phone rebuilt from the cloud: the archived career debut is '
          'not breaking news, even when only later plays arrived', () async {
        await historyBegan(DateTime.utc(2026, 11, 24));
        await played(DateTime.utc(2026, 11, 24, 12));
        final loaded = await load();
        expect(loaded.controller.momentStories.where(isNewRelease), isEmpty);
        await loaded.controller.newReleaseWritesSettled;
        expect(await store.readAll(), isEmpty);
      });

      test('a published record is told unchanged after a later restore and '
          'deletion', () async {
        await historyBegan(DateTime.utc(2026, 11, 1));
        await played(_week1.add(const Duration(days: 2, hours: 9)));
        expect(await told(await load()), single);
        final stored = await store.readAll();

        await historyBegan(DateTime.utc(2026, 11, 25, 8));
        final db = await database.database;
        await db.insert(DatabaseTables.libraryDeletionJournal, {
          'id': 'deletion-1',
          'operation': 'userDeletion',
          'target_type': 'song',
          'target_id': 'song-other',
          'committed_at': DateTime.utc(2026, 11, 25, 9).toIso8601String(),
        });
        final later = await load();
        expect(await told(later), single);
        expect(
          storyOf(later.controller, careerDebut)!.newRelease!.recorded,
          isTrue,
        );
        expect(await store.readAll(), stored);
      });
    });
  });
}

ChartMomentEvent _event(
  ChartEntitySnapshot song, {
  required ChartMomentScope scope,
  required DateTime weekStart,
  required DateTime at,
  required int rank,
}) {
  final key = '${scope.name}-debut-${song.entityId}';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: 'play-$key',
    chartType: ChartType.songs,
    scope: scope,
    eventType: ChartMomentEventType.debut,
    entity: song,
    weekStartUtc: weekStart,
    weekEndUtc: weekStart.add(const Duration(days: 7)),
    occurredAt: at,
    createdAt: at,
    currentRank: rank,
    currentPeakRank: rank,
    qualifiedStreamCount: 1,
  );
}

/// Proof for the debuts here (user rules 2026-11-16): the chart history
/// began before the start and "Dead" was first played at the start.
Future<NewReleaseEvidence> _proven(Set<String> songIds) async =>
    NewReleaseEvidence(
      historyOriginUtc: DateTime.utc(2026, 11, 1),
      firstPlayAt: {_dead.entityId: _start},
    );

class _Loaded {
  _Loaded(this.controller);

  final ChartsController controller;
  int classificationReads = 0;
  final List<DateTime> historyReads = [];
}

/// The library as a load reads it; each field is a later edit a test can
/// make.
class _LibraryState {
  const _LibraryState({
    this.isSingle = true,
    this.songTitle = 'Dead',
    this.albumTitle = 'Locket',
    this.singleDate = '2026-11-07',
    this.albumDate = '2026-11-07',
    this.featured = const [],
    this.writtenAt,
  });

  final bool isSingle;
  final String songTitle;
  final String albumTitle;
  final String? singleDate;
  final String albumDate;
  final List<String> featured;

  /// When the Single presentation and the edition were last written; null:
  /// before the debut (2026-11-08).
  final DateTime? writtenAt;
}

Future<_Loaded> _load(
  List<ChartMomentEvent> events, {
  int pageSize = 200,
  required bool? approved,
  bool loaders = true,
  bool start = true,
  NewReleasePublicationStore? publications,
  _LibraryState library = const _LibraryState(),
  Future<void> Function()? duringRead,
  bool settle = true,
  NewReleaseEvidenceLoader? evidence,
}) async {
  late final _Loaded loaded;
  final store = publications ?? MemoryNewReleasePublications();
  final moments = _Moments(events);
  final track = LibraryTrack(
    songId: _dead.entityId,
    title: library.songTitle,
    artistId: 'artist-1',
    artistName: 'Madison Beer',
    albumId: 'album-1',
    albumTitle: 'Locket',
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Locket',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: library.isSingle,
    featuredArtists: library.featured,
    dateAdded: DateTime.utc(2026, 11, 8),
    isAvailable: true,
    filePath: 'C:/Music/dead.mp3',
  );
  final rules = ChartMomentRules(
    devicePolishFromUtc: DateTime.utc(2026, 10, 1),
    newReleaseDebutsFromUtc: start ? _start : null,
  );

  Future<NewReleaseClassifications> classifications() async {
    loaded.classificationReads++;
    await duringRead?.call();
    return const NewReleaseClassifications();
  }

  Future<List<ChartMomentEvent>> history(DateTime fromUtc) async {
    loaded.historyReads.add(fromUtc);
    return [
      for (final event in events)
        if (!event.occurredAt.isBefore(fromUtc) &&
            event.eventType == ChartMomentEventType.debut)
          event,
    ];
  }

  final controller = approved == null
      ? ChartsController(
          allTimeCharts: _EmptyAllTimeCharts(),
          finalization: _NoFinalization(),
          charts: _NoHistory(),
          library: _library(track, library),
          moments: moments,
          now: () => DateTime.utc(2026, 11, 26, 12),
          momentPageSize: pageSize,
          momentRules: () async => rules,
          releaseEditions: () => _editions(library),
          singlePresentations: () => _singles(library),
          newReleaseClassifications: classifications,
          newReleaseDebutHistory: history,
          newReleasePublications: store,
          newReleaseEvidence: evidence ?? _proven,
        )
      : ChartsController(
          allTimeCharts: _EmptyAllTimeCharts(),
          finalization: _NoFinalization(),
          charts: _NoHistory(),
          library: _library(track, library),
          moments: moments,
          now: () => DateTime.utc(2026, 11, 26, 12),
          momentPageSize: pageSize,
          momentRules: () async => rules,
          releaseEditions: () => _editions(library),
          singlePresentations: () => _singles(library),
          newReleaseClassifications: loaders ? classifications : null,
          newReleaseDebutHistory: loaders ? history : null,
          newReleasePublications: loaders ? store : null,
          newReleaseEvidence: loaders ? evidence ?? _proven : null,
          newReleaseDebutsApproved: approved,
        );
  loaded = _Loaded(controller);
  addTearDown(controller.dispose);

  final loading = controller.load();
  if (!settle) return loaded;
  await loading;
  await pumpEventQueue();
  return loaded;
}

FakeChartLibrary _library(LibraryTrack track, _LibraryState library) =>
    FakeChartLibrary(
      tracks: [track],
      albums: [
        LibraryAlbum(
          albumId: 'album-1',
          title: library.albumTitle,
          artistId: 'artist-1',
          artistName: 'Madison Beer',
          trackCount: 1,
          dateAdded: DateTime.utc(2026, 11, 8),
        ),
      ],
    );

Future<List<LibraryReleaseEdition>> _editions(_LibraryState library) async => [
  LibraryReleaseEdition(
    edition: LibraryAlbumEdition(
      editionId: 'edition-1',
      albumId: 'album-1',
      title: 'Locket',
      type: AlbumEditionType.standard,
      isPrimary: true,
      dateAdded: DateTime.utc(2026, 11, 8),
      releaseDate: DateTime.parse('${library.albumDate}T00:00:00Z'),
      releaseDatePrecision: ReleaseDatePrecision.day,
      updatedAt: library.writtenAt ?? DateTime.utc(2026, 11, 8),
    ),
    trackCount: 1,
  ),
];

Future<Map<String, SongSinglePresentation>> _singles(
  _LibraryState library,
) async => {
  _dead.entityId: SongSinglePresentation(
    songId: _dead.entityId,
    releaseDate: ReleaseDate.tryParse(library.singleDate),
    createdAt: DateTime.utc(2026, 11, 8),
    updatedAt: library.writtenAt ?? DateTime.utc(2026, 11, 8),
  ),
};

class _Moments implements ChartMomentRepository {
  _Moments(this.events);

  final List<ChartMomentEvent> events;

  @override
  Future<List<ChartMomentEvent>> getPage({
    ChartMomentPageCursor? before,
    required int limit,
  }) async => momentPageOf(events, before: before, limit: limit);

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

class _EmptyAllTimeCharts implements AllTimeChartService {
  @override
  Future<AllTimeChart> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    ChartViewSize viewSize = ChartViewSize.top100,
  }) async => AllTimeChart(
    chartType: chartType,
    comparisonStartUtc: DateTime.utc(2026, 11, 22),
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
