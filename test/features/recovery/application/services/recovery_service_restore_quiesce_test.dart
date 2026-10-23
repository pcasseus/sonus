import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/analytics/presentation/scopes/analytics_scope.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/recovery/application/models/restore_result.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_gate.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_hold_store.dart';
import 'package:sonus_next/features/recovery/application/services/verified_backup_publisher.dart';

import '../../../../support/recovery_fixtures.dart';
import '../../../../support/test_only_backup_publication.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase database;
  late List<String> events;
  late int resumes;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_quiesce_');
    database = fileAppDatabase(root, 'target.db');
    events = [];
    resumes = 0;
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  DefaultRecoveryService service({
    RestoreRunner? runner,
    Future<void> Function()? stopPlayback,
    SuspendAnalytics? suspendAnalytics,
  }) {
    final recovery = Directory(path.join(root.path, 'recovery'));

    return DefaultRecoveryService(
      appDatabase: database,
      gate: RecoverySyncGate(
        holdStore: RecoverySyncHoldStore(directory: () async => recovery),
      ),
      recoveryDirectory: () async => recovery,
      artworkDirectory: () async => Directory(path.join(root.path, 'artwork')),
      supportDirectory: () async => root,
      picker: const _NoPicker(),
      stopPlayback:
          stopPlayback ??
          () async {
            events.add('stop');
          },
      relink: (_) async => throw UnimplementedError(),
      suspendAnalytics: suspendAnalytics,
      publisher: const VerifiedBackupPublisher(
        publication: TestOnlyBackupPublication(),
      ),
      storageProbe: null,
      restoreRunner: runner,
    );
  }

  /// Records suspension and resumption; [drained] stands in for the queue.
  SuspendAnalytics recordingSuspension({Future<void> Function()? drain}) {
    return () {
      events.add('suspend');
      return RestoreQuiescence(
        drained: drain?.call() ?? Future<void>.value(),
        resume: () => resumes++,
      );
    };
  }

  /// A restore that reports [stages] and then throws [error].
  RestoreRunner failingAfter(List<RestoreStage> stages, Object error) {
    return (backupFile, {onProgress}) async {
      events.add('restore');
      for (final stage in stages) {
        onProgress?.call(stage);
      }
      throw error;
    };
  }

  RestoreFailedException rolledBack({required bool verified}) {
    return RestoreFailedException(
      stage: RestoreStage.restoringDatabase,
      cause: StateError('transaction failed'),
      rollbackVerified: verified,
      syncHoldPreserved: !verified,
    );
  }

  final backupFile = File('unused.sonusbackup');

  group('commit boundary', () {
    test(
      'stops playback, then suspends and drains, before restoring',
      () async {
        final drained = Completer<void>();
        final restoring = Completer<void>();

        final pending = service(
          suspendAnalytics: recordingSuspension(drain: () => drained.future),
          runner: (file, {onProgress}) async {
            events.add('restore');
            restoring.complete();
            throw StateError('stop here');
          },
        ).restore(backupFile);

        await pumpEventQueue();
        expect(events, ['stop', 'suspend']);

        drained.complete();
        await restoring.future;
        expect(events, ['stop', 'suspend', 'restore']);

        await expectLater(pending, throwsStateError);
      },
    );

    test('a failure before the database transaction resumes once', () async {
      final error = const FormatException('not a backup');

      await expectLater(
        service(
          suspendAnalytics: recordingSuspension(),
          runner: failingAfter([
            RestoreStage.preparing,
            RestoreStage.verifyingBackup,
          ], error),
        ).restore(backupFile),
        throwsA(same(error)),
      );

      expect(resumes, 1);
    });

    test('a refused restore admission resumes once', () async {
      await expectLater(
        service(
          suspendAnalytics: recordingSuspension(),
          runner: failingAfter([
            RestoreStage.pausingSync,
          ], const LibraryMutationUnavailable('busy')),
        ).restore(backupFile),
        throwsA(isA<LibraryMutationUnavailable>()),
      );

      expect(resumes, 1);
    });

    test('a verified rollback of the transaction resumes once', () async {
      await expectLater(
        service(
          suspendAnalytics: recordingSuspension(),
          runner: failingAfter([
            RestoreStage.restoringDatabase,
          ], rolledBack(verified: true)),
        ).restore(backupFile),
        throwsA(isA<RestoreFailedException>()),
      );

      expect(resumes, 1);
    });

    test('an unverified rollback stays suspended', () async {
      await expectLater(
        service(
          suspendAnalytics: recordingSuspension(),
          runner: failingAfter([
            RestoreStage.restoringDatabase,
          ], rolledBack(verified: false)),
        ).restore(backupFile),
        throwsA(isA<RestoreFailedException>()),
      );

      expect(resumes, 0);
    });

    test('an error after the commit never resumes the old runtime', () async {
      final error = StateError('after commit');

      await expectLater(
        service(
          suspendAnalytics: recordingSuspension(),
          runner: failingAfter([
            RestoreStage.restoringDatabase,
            RestoreStage.assessingSync,
          ], error),
        ).restore(backupFile),
        throwsA(same(error)),
      );

      expect(resumes, 0);
    });

    test('after the commit no error type resumes the old runtime', () async {
      await expectLater(
        service(
          suspendAnalytics: recordingSuspension(),
          runner: failingAfter([
            RestoreStage.restoringDatabase,
            RestoreStage.assessingSync,
          ], rolledBack(verified: true)),
        ).restore(backupFile),
        throwsA(isA<RestoreFailedException>()),
      );

      expect(resumes, 0);
    });

    test('a failed drain resumes once and never restores', () async {
      final error = StateError('drain failed');

      await expectLater(
        service(
          suspendAnalytics: recordingSuspension(
            drain: () => Future<void>.error(error),
          ),
          runner: failingAfter(const [], StateError('unreachable')),
        ).restore(backupFile),
        throwsA(same(error)),
      );

      expect(resumes, 1);
      expect(events, isNot(contains('restore')));
    });

    test('a failed playback stop suspends nothing', () async {
      final error = StateError('stop failed');

      await expectLater(
        service(
          stopPlayback: () async => throw error,
          suspendAnalytics: recordingSuspension(),
          runner: failingAfter(const [], StateError('unreachable')),
        ).restore(backupFile),
        throwsA(same(error)),
      );

      expect(events, isEmpty);
      expect(resumes, 0);
    });

    test('progress still reaches the caller', () async {
      final seen = <RestoreStage>[];

      await expectLater(
        service(
          runner: failingAfter([
            RestoreStage.preparing,
            RestoreStage.restoringDatabase,
          ], rolledBack(verified: true)),
        ).restore(backupFile, onStage: seen.add),
        throwsA(isA<RestoreFailedException>()),
      );

      expect(seen, [RestoreStage.preparing, RestoreStage.restoringDatabase]);
    });
  });

  group('with the real restore and analytics runtime', () {
    late _IdleEngine engine;
    late AnalyticsRuntime runtime;

    setUp(() async {
      engine = _IdleEngine();
      runtime = await AnalyticsRuntime.create(
        appDatabase: database,
        playbackCoordinator: PlaybackCoordinator(engine: engine),
        log: (message, {required level, stackTrace}) {},
      );
    });

    tearDown(() async {
      await runtime.dispose();
      await engine.dispose();
    });

    SuspendAnalytics realSuspension() {
      final controller = runtime.controller;

      return () => RestoreQuiescence(
        drained: controller.suspendForRestore(),
        resume: controller.resumeAfterRestore,
      );
    }

    test('an invalid backup leaves analytics recording', () async {
      final invalid = File(path.join(root.path, 'invalid.sonusbackup'));
      await invalid.writeAsString('not a backup');

      await expectLater(
        service(suspendAnalytics: realSuspension()).restore(invalid),
        throwsA(anything),
      );

      expect(runtime.controller.isSuspended, isFalse);
    });

    test('a committed restore keeps the old runtime suspended', () async {
      final sourceDirectory = Directory(path.join(root.path, 'source'));
      await sourceDirectory.create();
      final source = fileAppDatabase(sourceDirectory, 'source.db');
      final File backup;

      try {
        await seedConnectedLibrary(await source.database, key: 'b');
        backup = await createFixtureBackup(
          source: source,
          directory: sourceDirectory,
        );
      } finally {
        await source.close();
      }

      await service(suspendAnalytics: realSuspension()).restore(backup);

      final songs = await (await database.database).query(DatabaseTables.songs);
      expect(songs.map((row) => row['id']), ['song-b']);
      expect(runtime.controller.isSuspended, isTrue);
    });
  });
}

class _NoPicker implements RecoveryFilePicker {
  const _NoPicker();

  @override
  Future<File?> pickBackupFile() async => null;

  @override
  Future<String?> pickMusicFolder() async => null;
}

class _IdleEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast(sync: true);

  @override
  PlaybackState get currentState => const PlaybackState();

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {}

  @override
  Future<void> appendTrack(PlaybackTrack track) async {}

  @override
  Future<void> removeTrackAt(int index) async {}

  @override
  Future<void> moveTrack({
    required int oldIndex,
    required int newIndex,
  }) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }
}
