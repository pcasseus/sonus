import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/presentation/controllers/artist_reel_statistics_controller.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';

ArtistLibraryStatisticsSnapshot snapshotWith(int rank) =>
    ArtistLibraryStatisticsSnapshot([
      ArtistLibraryStatistics(
        artist: LibraryArtist(
          artistId: 'ada',
          name: 'Ada',
          albumCount: 1,
          songCount: 1,
          dateAdded: DateTime(2026),
        ),
        rank: rank,
        qualifiedStreams: 10,
      ),
    ]);

void main() {
  test('requests during a load merge into one more load', () async {
    var loads = 0;
    final gates = <Completer<void>>[];
    final controller = ArtistReelStatisticsController(
      load: () async {
        loads++;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        return snapshotWith(loads);
      },
    );
    addTearDown(controller.dispose);

    final first = controller.refresh();
    unawaited(controller.refresh());
    unawaited(controller.refresh());
    await Future<void>.delayed(Duration.zero);
    expect(loads, 1);

    gates[0].complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(loads, 2, reason: 'three requests: the running load and one more');
    gates[1].complete();
    await first;

    expect(controller.hasLoaded, isTrue);
    expect(controller.snapshot['ada']!.rank, 2);
  });

  test('a failed reload keeps the statistics already shown', () async {
    var fail = false;
    final controller = ArtistReelStatisticsController(
      load: () async {
        if (fail) throw StateError('history unreadable');
        return snapshotWith(1);
      },
    );
    addTearDown(controller.dispose);
    await controller.refresh();

    fail = true;
    await controller.refresh();

    expect(controller.hasLoaded, isTrue);
    expect(controller.snapshot['ada']!.rank, 1);
  });

  test('nothing is reported after disposal', () async {
    final gate = Completer<void>();
    var notified = 0;
    final controller = ArtistReelStatisticsController(
      load: () async {
        await gate.future;
        return snapshotWith(1);
      },
    )..addListener(() => notified++);

    final loading = controller.refresh();
    controller.dispose();
    gate.complete();
    await loading;

    expect(notified, 0);
  });
}
