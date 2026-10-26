import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_week.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/domain/services/release_chart_eligibility.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  QualifiedPlay play({
    required String id,
    required String songId,
    required String albumId,
    required DateTime qualifiedAt,
    String? artistId,
  }) {
    return QualifiedPlay(
      id: id,
      playbackSessionId: 'session-$id',
      songId: songId,
      artistId: artistId ?? 'artist-$albumId',
      albumId: albumId,
      albumEditionId: 'edition-$albumId',
      qualifiedAt: qualifiedAt,
      listenedDuration: const Duration(seconds: 30),
      trackDuration: const Duration(minutes: 3),
      createdAt: qualifiedAt,
    );
  }

  LibraryTrack track({required String songId, required String albumId}) {
    return LibraryTrack(
      songId: songId,
      title: 'Title $songId',
      artistId: 'artist-$albumId',
      artistName: 'Artist $albumId',
      albumId: albumId,
      albumTitle: 'Album $albumId',
      albumEditionId: 'edition-$albumId',
      albumEditionTitle: 'Album $albumId',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: DateTime.utc(2026, 9, 1),
      isAvailable: true,
    );
  }

  LibraryAlbum album(String albumId) {
    return LibraryAlbum(
      albumId: albumId,
      title: 'Album $albumId',
      artistId: 'artist-$albumId',
      artistName: 'Artist $albumId',
      trackCount: 1,
      dateAdded: DateTime.utc(2026, 9, 1),
    );
  }

  ChartFinalizationService createService({
    required _MutableQualifiedPlayRepository qualifiedPlays,
    required _RecordingChartRepository charts,
    _RecordingMomentRepository? moments,
    DateTime? momentsActivationWeekStartUtc,
    ChartRestoreGeneration? restoreGeneration,
    ReleaseChartEligibility? releaseEligibility,
    ChartArtistAttribution? artistAttribution,
  }) {
    final library = _FakeLibraryQueryRepository(
      tracks: [
        track(songId: 'song-a', albumId: 'album-a'),
        track(songId: 'song-b', albumId: 'album-b'),
      ],
      albums: [album('album-a'), album('album-b')],
    );

    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: qualifiedPlays,
      library: library,
      charts: charts,
      playbackSessions: _PlaybackSessionRepository(qualifiedPlays),
    );

    return ChartFinalizationService(
      builder: builder,
      charts: charts,
      qualifiedPlays: qualifiedPlays,
      moments: moments,
      momentsActivationWeekStartUtc: momentsActivationWeekStartUtc,
      now: () => DateTime.utc(2026, 10, 4, 1),
      restoreGeneration: restoreGeneration,
      releaseEligibility: releaseEligibility,
      artistAttribution: artistAttribution,
    );
  }

  test('SN-45: weekly artist achievements count for the artist each song '
      'belongs to, never for a contributor', () async {
    final week = ChartWeek(
      startUtc: DateTime.utc(2026, 9, 27),
      endUtc: DateTime.utc(2026, 10, 4),
    );
    final moments = _RecordingMomentRepository();
    await createService(
      qualifiedPlays: _MutableQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]),
      charts: _RecordingChartRepository(),
      moments: moments,
      momentsActivationWeekStartUtc: week.startUtc,
      // song-a is a contributor's song on the project "owner" owns.
      artistAttribution: () async => {'song-a': 'owner'},
    ).reconcileCompletedWeek(week);

    final artistEvents = [
      for (final replacement in moments.replacements)
        if (replacement.chartType == ChartType.songs)
          for (final event in replacement.events)
            if (event.eventType.name.startsWith('artist')) event,
    ];
    expect(artistEvents, isNotEmpty);
    expect(
      {for (final event in artistEvents) event.entity.artistId},
      {'owner'},
    );
  });

  group('SN-45: Singles on the release chart', () {
    final week = ChartWeek(
      startUtc: DateTime.utc(2026, 9, 27),
      endUtc: DateTime.utc(2026, 10, 4),
    );

    _MutableQualifiedPlayRepository weekPlays() =>
        _MutableQualifiedPlayRepository([
          play(
            id: '1',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 9, 28, 10),
          ),
          play(
            id: '2',
            songId: 'song-b',
            albumId: 'album-b',
            qualifiedAt: DateTime.utc(2026, 9, 29, 10),
          ),
        ]);

    Set<String> albumsIn(ChartSnapshot? snapshot) => {
      for (final entry in snapshot?.entries ?? const []) entry.entity.entityId,
    };

    test(
      'a newly finalized week leaves a Single out; its song stays',
      () async {
        final charts = _RecordingChartRepository();
        await createService(
          qualifiedPlays: weekPlays(),
          charts: charts,
          releaseEligibility: const _Singles({'album-b'}),
        ).reconcileCompletedWeek(week);

        expect(
          albumsIn(
            await charts.getForWeek(
              chartType: ChartType.albums,
              weekStartUtc: week.startUtc,
            ),
          ),
          {'album-a'},
        );
        final songs = await charts.getForWeek(
          chartType: ChartType.songs,
          weekStartUtc: week.startUtc,
        );
        expect(
          {for (final e in songs!.entries) e.entity.entityId},
          {'song-a', 'song-b'},
        );
      },
    );

    test(
      'a stored week is never rewritten when a release becomes a Single',
      () async {
        final charts = _RecordingChartRepository();
        await createService(
          qualifiedPlays: weekPlays(),
          charts: charts,
        ).reconcileCompletedWeek(week);
        final stored = await charts.getForWeek(
          chartType: ChartType.albums,
          weekStartUtc: week.startUtc,
        );
        expect(albumsIn(stored), {'album-a', 'album-b'});

        await createService(
          qualifiedPlays: weekPlays(),
          charts: charts,
          releaseEligibility: const _Singles({'album-b'}),
        ).reconcileCompletedWeek(week);

        final again = await charts.getForWeek(
          chartType: ChartType.albums,
          weekStartUtc: week.startUtc,
        );
        expect(albumsIn(again), {'album-a', 'album-b'});
        expect(again!.revision, stored!.revision);
      },
    );
  });

  group('restore generation', () {
    final week = ChartWeek(
      startUtc: DateTime.utc(2026, 9, 27),
      endUtc: DateTime.utc(2026, 10, 4),
    );

    _MutableQualifiedPlayRepository weekPlays() {
      return _MutableQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
        play(
          id: '2',
          songId: 'song-b',
          albumId: 'album-b',
          qualifiedAt: DateTime.utc(2026, 9, 29, 10),
        ),
      ]);
    }

    test('an unchanged generation leaves finalization identical', () async {
      final plainCharts = _RecordingChartRepository();
      final plainMoments = _RecordingMomentRepository();
      final guardedCharts = _RecordingChartRepository();
      final guardedMoments = _RecordingMomentRepository();

      final plain = await createService(
        qualifiedPlays: weekPlays(),
        charts: plainCharts,
        moments: plainMoments,
        momentsActivationWeekStartUtc: week.startUtc,
      ).reconcileCompletedWeek(week);

      final guarded = await createService(
        qualifiedPlays: weekPlays(),
        charts: guardedCharts,
        moments: guardedMoments,
        momentsActivationWeekStartUtc: week.startUtc,
        restoreGeneration: () => 7,
      ).reconcileCompletedWeek(week);

      expect(guardedCharts.replaceCalls, plainCharts.replaceCalls);
      expect(
        guardedMoments.replacements.length,
        plainMoments.replacements.length,
      );

      for (var index = 0; index < plain.length; index++) {
        final expected = plain[index];
        final actual = guarded[index];

        expect(actual.revision, expected.revision);
        expect(
          actual.entries.map(
            (entry) => (
              entry.entity.entityId,
              entry.rank,
              entry.qualifiedStreamCount,
              entry.movement,
            ),
          ),
          expected.entries.map(
            (entry) => (
              entry.entity.entityId,
              entry.rank,
              entry.qualifiedStreamCount,
              entry.movement,
            ),
          ),
        );
      }
    });

    test('a generation that moved after capture refuses every write', () async {
      final charts = _RecordingChartRepository();
      final moments = _RecordingMomentRepository();
      var generation = 0;

      final pass = createService(
        qualifiedPlays: weekPlays(),
        charts: charts,
        moments: moments,
        momentsActivationWeekStartUtc: week.startUtc,
        restoreGeneration: () => generation,
      ).reconcileCompletedWeek(week);

      // Captured synchronously when the pass began.
      generation++;

      await expectLater(pass, throwsA(isA<LibraryMutationUnavailable>()));
      expect(charts.replaceCalls, 0);
      expect(moments.replacements, isEmpty);
    });
  });

  test('finalizes songs and albums for completed week', () async {
    final qualifiedPlays = _MutableQualifiedPlayRepository([
      play(
        id: '1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 10),
      ),
      play(
        id: '2',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 29, 10),
      ),
      play(
        id: '3',
        songId: 'song-b',
        albumId: 'album-b',
        qualifiedAt: DateTime.utc(2026, 9, 30, 10),
      ),
    ]);

    final charts = _RecordingChartRepository();

    final service = createService(
      qualifiedPlays: qualifiedPlays,
      charts: charts,
    );

    final snapshots = await service.reconcileCompletedWeek(
      ChartWeek(
        startUtc: DateTime.utc(2026, 9, 27),
        endUtc: DateTime.utc(2026, 10, 4),
      ),
    );

    expect(snapshots, hasLength(2));

    final songs = snapshots.singleWhere(
      (snapshot) => snapshot.chartType == ChartType.songs,
    );

    final albums = snapshots.singleWhere(
      (snapshot) => snapshot.chartType == ChartType.albums,
    );

    expect(songs.isFinalized, isTrue);
    expect(albums.isFinalized, isTrue);

    expect(songs.revision, 1);
    expect(albums.revision, 1);

    expect(songs.entries.first.entity.entityId, 'song-a');
    expect(songs.entries.first.qualifiedStreamCount, 2);

    expect(albums.entries.first.entity.entityId, 'album-a');
    expect(albums.entries.first.qualifiedStreamCount, 2);

    expect(charts.replaceCalls, 2);
  });

  test('unchanged reconciliation is idempotent and does not rewrite', () async {
    final qualifiedPlays = _MutableQualifiedPlayRepository([
      play(
        id: '1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 10),
      ),
    ]);

    final charts = _RecordingChartRepository();

    final service = createService(
      qualifiedPlays: qualifiedPlays,
      charts: charts,
    );

    final week = ChartWeek(
      startUtc: DateTime.utc(2026, 9, 27),
      endUtc: DateTime.utc(2026, 10, 4),
    );

    final first = await service.reconcileCompletedWeek(week);

    expect(charts.replaceCalls, 2);

    final second = await service.reconcileCompletedWeek(week);

    expect(charts.replaceCalls, 2);

    expect(
      second
          .singleWhere((snapshot) => snapshot.chartType == ChartType.songs)
          .revision,
      1,
    );

    expect(
      second
          .singleWhere((snapshot) => snapshot.chartType == ChartType.albums)
          .revision,
      1,
    );

    expect(first.length, second.length);
  });

  test(
    'late qualified play rebuilds finalized week with next revision',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]);

      final charts = _RecordingChartRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
      );

      final week = ChartWeek(
        startUtc: DateTime.utc(2026, 9, 27),
        endUtc: DateTime.utc(2026, 10, 4),
      );

      await service.reconcileCompletedWeek(week);

      qualifiedPlays.plays.add(
        play(
          id: '2',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 30, 10),
        ),
      );

      final rebuilt = await service.reconcileCompletedWeek(week);

      final songs = rebuilt.singleWhere(
        (snapshot) => snapshot.chartType == ChartType.songs,
      );

      final albums = rebuilt.singleWhere(
        (snapshot) => snapshot.chartType == ChartType.albums,
      );

      expect(songs.revision, 2);
      expect(albums.revision, 2);

      expect(songs.entries.single.qualifiedStreamCount, 2);
      expect(albums.entries.single.qualifiedStreamCount, 2);

      expect(charts.replaceCalls, 4);
    },
  );

  test(
    'catch-up finalizes every completed play week oldest to newest and skips live week',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: 'week-1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime(2026, 9, 21, 12).toUtc(),
        ),
        play(
          id: 'week-2',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime(2026, 9, 28, 12).toUtc(),
        ),
        play(
          id: 'live-week',
          songId: 'song-b',
          albumId: 'album-b',
          qualifiedAt: DateTime(2026, 10, 5, 12).toUtc(),
        ),
      ]);

      final charts = _RecordingChartRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
      );

      final snapshots = await service.finalizeCompletedWeeks(
        referenceLocal: DateTime(2026, 10, 5, 18),
      );

      expect(snapshots, hasLength(4));

      expect(snapshots.map((snapshot) => snapshot.chartType).toList(), [
        ChartType.songs,
        ChartType.albums,
        ChartType.songs,
        ChartType.albums,
      ]);

      expect(snapshots[0].weekStartUtc, DateTime(2026, 9, 20).toUtc());

      expect(snapshots[2].weekStartUtc, DateTime(2026, 9, 27).toUtc());

      expect(snapshots.every((snapshot) => snapshot.isFinalized), isTrue);

      expect(
        snapshots.any(
          (snapshot) => snapshot.weekStartUtc == DateTime(2026, 10, 4).toUtc(),
        ),
        isFalse,
      );

      final secondWeekSongs = snapshots[2];

      expect(secondWeekSongs.entries.single.previousFinalRank, 1);

      expect(secondWeekSongs.entries.single.weeksOnChart, 2);

      expect(charts.replaceCalls, 4);
    },
  );
  test(
    'eligible finalized week reconciles canonical Moments for both charts',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]);

      final charts = _RecordingChartRepository();
      final moments = _RecordingMomentRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
        moments: moments,
        momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
      );

      await service.reconcileCompletedWeek(
        ChartWeek(
          startUtc: DateTime.utc(2026, 9, 27),
          endUtc: DateTime.utc(2026, 10, 4),
        ),
      );

      expect(moments.replacements, hasLength(2));

      expect(
        moments.replacements
            .map((replacement) => replacement.chartType)
            .toList(),
        [ChartType.songs, ChartType.albums],
      );

      for (final replacement in moments.replacements) {
        expect(replacement.weekStartUtc, DateTime.utc(2026, 9, 27));
        expect(replacement.events, isNotEmpty);

        expect(
          replacement.events.every(
            (event) => event.scope == ChartMomentScope.finalized,
          ),
          isTrue,
        );

        expect(
          replacement.events.every((event) => event.sourceId != null),
          isTrue,
        );
      }
    },
  );

  test(
    'unchanged chart still reconciles finalized Moments for self-healing',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]);

      final charts = _RecordingChartRepository();
      final moments = _RecordingMomentRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
        moments: moments,
        momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
      );

      final week = ChartWeek(
        startUtc: DateTime.utc(2026, 9, 27),
        endUtc: DateTime.utc(2026, 10, 4),
      );

      await service.reconcileCompletedWeek(week);

      expect(charts.replaceCalls, 2);
      expect(moments.replacements, hasLength(2));

      await service.reconcileCompletedWeek(week);

      // Canonical chart snapshots are unchanged.
      expect(charts.replaceCalls, 2);

      // FINAL Moment slices are deliberately rebuilt anyway.
      expect(moments.replacements, hasLength(4));

      expect(
        moments.replacements[0].events.map((event) => event.id).toList(),
        moments.replacements[2].events.map((event) => event.id).toList(),
      );

      expect(
        moments.replacements[1].events.map((event) => event.id).toList(),
        moments.replacements[3].events.map((event) => event.id).toList(),
      );
    },
  );

  test('pre-activation finalized weeks do not backfill Moments', () async {
    final qualifiedPlays = _MutableQualifiedPlayRepository([
      play(
        id: 'old',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 21, 10),
      ),
    ]);

    final charts = _RecordingChartRepository();
    final moments = _RecordingMomentRepository();

    final service = createService(
      qualifiedPlays: qualifiedPlays,
      charts: charts,
      moments: moments,
      momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
    );

    await service.reconcileCompletedWeek(
      ChartWeek(
        startUtc: DateTime.utc(2026, 9, 20),
        endUtc: DateTime.utc(2026, 9, 27),
      ),
    );

    expect(charts.replaceCalls, 2);
    expect(moments.replacements, isEmpty);
  });

  test(
    'late chart revision replaces the same finalized Moment slices',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]);

      final charts = _RecordingChartRepository();
      final moments = _RecordingMomentRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
        moments: moments,
        momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
      );

      final week = ChartWeek(
        startUtc: DateTime.utc(2026, 9, 27),
        endUtc: DateTime.utc(2026, 10, 4),
      );

      final first = await service.reconcileCompletedWeek(week);

      qualifiedPlays.plays.add(
        play(
          id: '2',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 30, 10),
        ),
      );

      final second = await service.reconcileCompletedWeek(week);

      expect(
        first
            .singleWhere((snapshot) => snapshot.chartType == ChartType.songs)
            .revision,
        1,
      );

      expect(
        second
            .singleWhere((snapshot) => snapshot.chartType == ChartType.songs)
            .revision,
        2,
      );

      expect(charts.replaceCalls, 4);
      expect(moments.replacements, hasLength(4));

      expect(
        moments.replacements.every(
          (replacement) =>
              replacement.weekStartUtc == DateTime.utc(2026, 9, 27),
        ),
        isTrue,
      );
    },
  );

  test(
    'catch-up finalizes old charts but starts Moments at activation week',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: 'week-1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime(2026, 9, 21, 12).toUtc(),
        ),
        play(
          id: 'week-2',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime(2026, 9, 28, 12).toUtc(),
        ),
      ]);

      final charts = _RecordingChartRepository();
      final moments = _RecordingMomentRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
        moments: moments,
        momentsActivationWeekStartUtc: DateTime(2026, 9, 27).toUtc(),
      );

      await service.finalizeCompletedWeeks(
        referenceLocal: DateTime(2026, 10, 5, 18),
      );

      // Both historical weeks still get canonical song + album snapshots.
      expect(charts.replaceCalls, 4);

      // Only the activation week receives FINAL Moment reconstruction.
      expect(moments.replacements, hasLength(2));

      expect(
        moments.replacements.every(
          (replacement) =>
              replacement.weekStartUtc == DateTime(2026, 9, 27).toUtc(),
        ),
        isTrue,
      );
    },
  );
  test(
    'eligible finalized week includes longevity and lifetime stream milestones',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository(
        List.generate(
          10,
          (index) => play(
            id: 'play-$index',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 9, 28, 10, index),
          ),
        ),
      );

      final charts = _RecordingChartRepository();
      final moments = _RecordingMomentRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
        moments: moments,
        momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
      );

      await service.reconcileCompletedWeek(
        ChartWeek(
          startUtc: DateTime.utc(2026, 9, 27),
          endUtc: DateTime.utc(2026, 10, 4),
        ),
      );

      final songs = moments.replacements.singleWhere(
        (replacement) => replacement.chartType == ChartType.songs,
      );

      expect(
        songs.events.any(
          (event) =>
              event.eventType == ChartMomentEventType.totalWeeksMilestone &&
              event.milestoneValue == 1,
        ),
        isTrue,
      );

      expect(
        songs.events.any(
          (event) =>
              event.eventType ==
                  ChartMomentEventType.consecutiveWeeksMilestone &&
              event.milestoneValue == 1,
        ),
        isTrue,
      );

      expect(
        songs.events.any(
          (event) =>
              event.eventType == ChartMomentEventType.lifetimeStreamMilestone &&
              event.milestoneValue == 10,
        ),
        isTrue,
      );
    },
  );

  test(
    'activation week uses pre-week lifetime streams as milestone baseline',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        for (var index = 0; index < 9; index++)
          play(
            id: 'old-$index',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 9, 20, 10, index),
          ),
        play(
          id: 'current',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]);

      final charts = _RecordingChartRepository();
      final moments = _RecordingMomentRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
        moments: moments,
        momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
      );

      await service.reconcileCompletedWeek(
        ChartWeek(
          startUtc: DateTime.utc(2026, 9, 27),
          endUtc: DateTime.utc(2026, 10, 4),
        ),
      );

      final songs = moments.replacements.singleWhere(
        (replacement) => replacement.chartType == ChartType.songs,
      );

      final streamMilestones = songs.events
          .where(
            (event) =>
                event.eventType == ChartMomentEventType.lifetimeStreamMilestone,
          )
          .map((event) => event.milestoneValue)
          .toList();

      expect(streamMilestones, [10]);
    },
  );

  test('second finalized week emits two-week longevity milestones', () async {
    final qualifiedPlays = _MutableQualifiedPlayRepository([
      play(
        id: 'week-1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 10),
      ),
      play(
        id: 'week-2',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 10, 5, 10),
      ),
    ]);

    final charts = _RecordingChartRepository();
    final moments = _RecordingMomentRepository();

    final service = createService(
      qualifiedPlays: qualifiedPlays,
      charts: charts,
      moments: moments,
      momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
    );

    await service.reconcileCompletedWeek(
      ChartWeek(
        startUtc: DateTime.utc(2026, 9, 27),
        endUtc: DateTime.utc(2026, 10, 4),
      ),
    );

    await service.reconcileCompletedWeek(
      ChartWeek(
        startUtc: DateTime.utc(2026, 10, 4),
        endUtc: DateTime.utc(2026, 10, 11),
      ),
    );

    final secondWeekSongs = moments.replacements.lastWhere(
      (replacement) =>
          replacement.chartType == ChartType.songs &&
          replacement.weekStartUtc == DateTime.utc(2026, 10, 4),
    );

    expect(
      secondWeekSongs.events.any(
        (event) =>
            event.eventType == ChartMomentEventType.totalWeeksMilestone &&
            event.milestoneValue == 2,
      ),
      isTrue,
    );

    expect(
      secondWeekSongs.events.any(
        (event) =>
            event.eventType == ChartMomentEventType.consecutiveWeeksMilestone &&
            event.milestoneValue == 2,
      ),
      isTrue,
    );
  });
  test(
    'finalized week includes first artist threshold and career-best achievements',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: 'first',
          songId: 'song-a',
          albumId: 'album-a',
          artistId: 'artist-shared',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]);

      final charts = _RecordingChartRepository();
      final moments = _RecordingMomentRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
        moments: moments,
        momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
      );

      await service.reconcileCompletedWeek(
        ChartWeek(
          startUtc: DateTime.utc(2026, 9, 27),
          endUtc: DateTime.utc(2026, 10, 4),
        ),
      );

      final songs = moments.replacements.singleWhere(
        (replacement) => replacement.chartType == ChartType.songs,
      );

      final albums = moments.replacements.singleWhere(
        (replacement) => replacement.chartType == ChartType.albums,
      );

      expect(
        songs.events.any(
          (event) =>
              event.eventType ==
                  ChartMomentEventType.artistFirstThresholdSong &&
              event.threshold == 100 &&
              event.milestoneValue == 1,
        ),
        isTrue,
      );

      expect(
        songs.events.any(
          (event) =>
              event.eventType == ChartMomentEventType.artistHighestChartingSong,
        ),
        isTrue,
      );

      expect(
        albums.events.any(
          (event) =>
              event.eventType ==
                  ChartMomentEventType.artistFirstThresholdAlbum &&
              event.milestoneValue == 1,
        ),
        isTrue,
      );

      expect(
        albums.events.any(
          (event) =>
              event.eventType ==
              ChartMomentEventType.artistHighestChartingAlbum,
        ),
        isTrue,
      );
    },
  );

  test(
    'second distinct song by same artist emits nth catalog accomplishment',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: 'week-1',
          songId: 'song-a',
          albumId: 'album-a',
          artistId: 'artist-shared',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
        play(
          id: 'week-2',
          songId: 'song-b',
          albumId: 'album-b',
          artistId: 'artist-shared',
          qualifiedAt: DateTime.utc(2026, 10, 5, 10),
        ),
      ]);

      final charts = _RecordingChartRepository();
      final moments = _RecordingMomentRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
        moments: moments,
        momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
      );

      await service.reconcileCompletedWeek(
        ChartWeek(
          startUtc: DateTime.utc(2026, 9, 27),
          endUtc: DateTime.utc(2026, 10, 4),
        ),
      );

      await service.reconcileCompletedWeek(
        ChartWeek(
          startUtc: DateTime.utc(2026, 10, 4),
          endUtc: DateTime.utc(2026, 10, 11),
        ),
      );

      final secondWeekSongs = moments.replacements.lastWhere(
        (replacement) =>
            replacement.chartType == ChartType.songs &&
            replacement.weekStartUtc == DateTime.utc(2026, 10, 4),
      );

      expect(
        secondWeekSongs.events.any(
          (event) =>
              event.eventType == ChartMomentEventType.artistNthThresholdSong &&
              event.threshold == 100 &&
              event.milestoneValue == 2,
        ),
        isTrue,
      );
    },
  );

  test(
    'multiple same-week songs by one artist advance ordinals once and emit one career best',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: 'a-1',
          songId: 'song-a',
          albumId: 'album-a',
          artistId: 'artist-shared',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
        play(
          id: 'a-2',
          songId: 'song-a',
          albumId: 'album-a',
          artistId: 'artist-shared',
          qualifiedAt: DateTime.utc(2026, 9, 28, 11),
        ),
        play(
          id: 'b-1',
          songId: 'song-b',
          albumId: 'album-b',
          artistId: 'artist-shared',
          qualifiedAt: DateTime.utc(2026, 9, 28, 12),
        ),
      ]);

      final charts = _RecordingChartRepository();
      final moments = _RecordingMomentRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
        moments: moments,
        momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
      );

      await service.reconcileCompletedWeek(
        ChartWeek(
          startUtc: DateTime.utc(2026, 9, 27),
          endUtc: DateTime.utc(2026, 10, 4),
        ),
      );

      final songs = moments.replacements.singleWhere(
        (replacement) => replacement.chartType == ChartType.songs,
      );

      final firstTop100 = songs.events
          .where(
            (event) =>
                event.eventType ==
                    ChartMomentEventType.artistFirstThresholdSong &&
                event.threshold == 100,
          )
          .toList();

      final nthTop100 = songs.events
          .where(
            (event) =>
                event.eventType ==
                    ChartMomentEventType.artistNthThresholdSong &&
                event.threshold == 100,
          )
          .toList();

      final careerBest = songs.events
          .where(
            (event) =>
                event.eventType ==
                ChartMomentEventType.artistHighestChartingSong,
          )
          .toList();

      final simultaneousTop100 = songs.events
          .where(
            (event) =>
                event.eventType ==
                    ChartMomentEventType.artistSimultaneousThresholdSongs &&
                event.threshold == 100,
          )
          .toList();

      expect(firstTop100, hasLength(1));
      expect(firstTop100.single.milestoneValue, 1);

      expect(nthTop100, hasLength(1));
      expect(nthTop100.single.milestoneValue, 2);

      expect(careerBest, hasLength(1));
      expect(careerBest.single.entity.entityId, 'song-a');

      expect(simultaneousTop100, hasLength(1));
      expect(simultaneousTop100.single.milestoneValue, 2);
      expect(simultaneousTop100.single.entity.entityId, 'song-a');
      expect(simultaneousTop100.single.relatedEntity?.entityId, 'song-b');
    },
  );

  test('artist achievement Moments self-heal with stable identities', () async {
    final qualifiedPlays = _MutableQualifiedPlayRepository([
      play(
        id: '1',
        songId: 'song-a',
        albumId: 'album-a',
        artistId: 'artist-shared',
        qualifiedAt: DateTime.utc(2026, 9, 28, 10),
      ),
    ]);

    final charts = _RecordingChartRepository();
    final moments = _RecordingMomentRepository();

    final service = createService(
      qualifiedPlays: qualifiedPlays,
      charts: charts,
      moments: moments,
      momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 27),
    );

    final week = ChartWeek(
      startUtc: DateTime.utc(2026, 9, 27),
      endUtc: DateTime.utc(2026, 10, 4),
    );

    await service.reconcileCompletedWeek(week);
    await service.reconcileCompletedWeek(week);

    final firstSongs = moments.replacements[0];
    final rebuiltSongs = moments.replacements[2];

    final firstArtistIds = firstSongs.events
        .where(
          (event) =>
              event.eventType ==
                  ChartMomentEventType.artistFirstThresholdSong ||
              event.eventType == ChartMomentEventType.artistHighestChartingSong,
        )
        .map((event) => event.id)
        .toList();

    final rebuiltArtistIds = rebuiltSongs.events
        .where(
          (event) =>
              event.eventType ==
                  ChartMomentEventType.artistFirstThresholdSong ||
              event.eventType == ChartMomentEventType.artistHighestChartingSong,
        )
        .map((event) => event.id)
        .toList();

    expect(firstArtistIds, isNotEmpty);
    expect(firstArtistIds, rebuiltArtistIds);
  });
  test('previous completed week resolves from local reference date', () async {
    final qualifiedPlays = _MutableQualifiedPlayRepository([
      play(
        id: '1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 22, 10),
      ),
    ]);

    final charts = _RecordingChartRepository();

    final service = createService(
      qualifiedPlays: qualifiedPlays,
      charts: charts,
    );

    final snapshots = await service.finalizePreviousCompletedWeek(
      referenceLocal: DateTime(2026, 9, 28, 9),
    );

    final songs = snapshots.singleWhere(
      (snapshot) => snapshot.chartType == ChartType.songs,
    );

    expect(songs.weekStartUtc, DateTime(2026, 9, 20).toUtc());

    expect(songs.weekEndUtc, DateTime(2026, 9, 27).toUtc());
  });
}

class _MutableQualifiedPlayRepository implements QualifiedPlayRepository {
  _MutableQualifiedPlayRepository(List<QualifiedPlay> plays)
    : plays = List<QualifiedPlay>.from(plays);

  final List<QualifiedPlay> plays;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    return plays
        .where((play) {
          final qualifiedAt = play.qualifiedAt.toUtc();

          if (qualifiedAtOrAfter != null &&
              qualifiedAt.isBefore(qualifiedAtOrAfter.toUtc())) {
            return false;
          }

          if (qualifiedBefore != null &&
              !qualifiedAt.isBefore(qualifiedBefore.toUtc())) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  @override
  Future<void> create(QualifiedPlay play) {
    throw UnimplementedError();
  }

  @override
  Future<QualifiedPlay?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(String playbackSessionId) {
    throw UnimplementedError();
  }

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(QualifiedPlay play) {
    throw UnimplementedError();
  }
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({required this.tracks, required this.albums});

  final List<LibraryTrack> tracks;
  final List<LibraryAlbum> albums;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks;
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return albums;
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) {
    throw UnimplementedError();
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryArtist>> getArtists() {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) {
    throw UnimplementedError();
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) {
    throw UnimplementedError();
  }
}

class _RecordingChartRepository implements ChartRepository {
  final List<ChartSnapshot> _snapshots = [];

  int replaceCalls = 0;

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) async {
    replaceCalls++;

    _snapshots.removeWhere(
      (existing) =>
          existing.chartType == snapshot.chartType &&
          existing.weekStartUtc.toUtc() == snapshot.weekStartUtc.toUtc(),
    );

    _snapshots.add(snapshot);
  }

  @override
  Future<ChartSnapshot?> getById(String id) async {
    for (final snapshot in _snapshots) {
      if (snapshot.id == id) {
        return snapshot;
      }
    }

    return null;
  }

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) async {
    for (final snapshot in _snapshots) {
      if (snapshot.chartType == chartType &&
          snapshot.weekStartUtc.toUtc() == weekStartUtc.toUtc()) {
        return snapshot;
      }
    }

    return null;
  }

  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async {
    final results =
        _snapshots
            .where(
              (snapshot) =>
                  snapshot.chartType == chartType && snapshot.isFinalized,
            )
            .toList(growable: false)
          ..sort((a, b) => b.weekStartUtc.compareTo(a.weekStartUtc));

    if (limit == null || results.length <= limit) {
      return List<ChartSnapshot>.unmodifiable(results);
    }

    return List<ChartSnapshot>.unmodifiable(results.take(limit));
  }
}

class _FinalizedReplacement {
  const _FinalizedReplacement({
    required this.chartType,
    required this.weekStartUtc,
    required this.events,
  });

  final ChartType chartType;
  final DateTime weekStartUtc;
  final List<ChartMomentEvent> events;
}

class _RecordingMomentRepository implements ChartMomentRepository {
  final List<_FinalizedReplacement> replacements = [];

  @override
  Future<void> replaceFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  }) async {
    replacements.add(
      _FinalizedReplacement(
        chartType: chartType,
        weekStartUtc: weekStartUtc.toUtc(),
        events: List<ChartMomentEvent>.unmodifiable(events),
      ),
    );
  }

  @override
  Future<void> saveAll(Iterable<ChartMomentEvent> events) async {}

  @override
  Future<ChartMomentEvent?> getById(String id) async => null;

  @override
  Future<List<ChartMomentEvent>> getRecent({int? limit}) async => const [];
}

class _PlaybackSessionRepository implements PlaybackSessionRepository {
  _PlaybackSessionRepository(this.qualifiedPlays);

  final _MutableQualifiedPlayRepository qualifiedPlays;

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async {
    final requested = ids.toSet();

    return qualifiedPlays.plays
        .where((play) => requested.contains(play.playbackSessionId))
        .map(
          (play) => PlaybackSession(
            id: play.playbackSessionId,
            songId: play.songId,
            artistId: play.artistId,
            albumId: play.albumId,
            albumEditionId: play.albumEditionId,
            songTitle: 'Title ${play.songId}',
            artistName: 'Artist ${play.albumId}',
            albumTitle: 'Album ${play.albumId}',
            albumEditionTitle: 'Album ${play.albumId}',
            startedAt: play.qualifiedAt,
            endedAt: play.qualifiedAt.add(const Duration(minutes: 3)),
            listenedDuration: const Duration(minutes: 3),
            trackDuration: const Duration(minutes: 3),
            finalPosition: const Duration(minutes: 3),
            createdAt: play.qualifiedAt,
            updatedAt: play.qualifiedAt.add(const Duration(minutes: 3)),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> create(PlaybackSession session) {
    throw UnimplementedError();
  }

  @override
  Future<PlaybackSession?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getOpen() {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(PlaybackSession session) {
    throw UnimplementedError();
  }
}

class _Singles implements ReleaseChartEligibility {
  const _Singles(this.ids);

  final Set<String> ids;

  @override
  Future<Set<String>> excludedAlbumIds() async => ids;
}
