import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';

import '../../domain/models/cloud_archive_record.dart';
import 'cloud_archive_gateway.dart';

enum CloudArchiveApplyOutcome {
  applied,

  /// Something the record refers to (a song, album, artist or artwork) is
  /// not on this device yet; it is applied on a later sync.
  missingDependencies,
}

/// What this device last agreed with the cloud about one record.
class CloudArchiveState {
  const CloudArchiveState({
    required this.fingerprint,
    required this.serverRevision,
    this.pendingApply = false,
    this.cloudDeleted = false,
  });

  /// Fingerprint of the content both sides held when they last agreed.
  final String fingerprint;
  final int serverRevision;

  /// A newer cloud copy is waiting for local dependencies.
  final bool pendingApply;

  /// The record was removed on another device; it stays here, and is only
  /// sent again if it is changed here.
  final bool cloudDeleted;
}

abstract interface class CloudArchiveLocalStore {
  Future<List<CloudArchiveRecord>> collect();

  Future<CloudArchiveApplyOutcome> apply(CloudArchiveRecord record);

  Future<void> duplicatePlaylist({
    required Map<String, Object?> payload,
    required String newId,
    required String newName,
  });

  Future<bool> artworkInCloud(String userId, String artworkId);

  Future<Map<String, CloudArchiveState>> states(String userId);

  Future<void> saveState(
    String userId,
    CloudArchiveKind kind,
    String key,
    CloudArchiveState state,
  );

  Future<CloudArchiveCursor?> cursor(String userId);

  Future<void> saveCursor(String userId, CloudArchiveCursor cursor);
}

/// Counts from one archive pass, for logs and tests.
class CloudArchiveSyncReport {
  int uploaded = 0;
  int downloaded = 0;
  int waitingForDependencies = 0;
  int conflictsKeptBoth = 0;
  int conflictsNewerWon = 0;
  bool skippedUnavailable = false;
}

typedef QueueLibraryUpload =
    Future<void> Function({required String userId, required String artworkId});

/// Keeps user-created and historical records in the cloud archive.
///
/// Push, retry what was waiting, then pull, every sync. Changes are found by comparing each
/// record's content with what this device last agreed with the cloud, so
/// no edit path can be missed. Writes are insert-if-absent or
/// compare-and-set on the server revision; a lost response is recognised
/// on retry and adopted.
///
/// Conflicts:
/// - listening sessions and all-time Moments are immutable: the first copy
///   stands and nothing is overwritten;
/// - a playlist changed on two devices is kept twice (this device's copy
///   is saved as "`name` (this device)"), so no song or order is lost;
/// - lyrics, crops and organization: the most recent edit wins.
/// Removals are recorded in the cloud, keeping the content, and never
/// remove anything on another device.
///
/// A backup restore does not change what this device last agreed with the
/// cloud, so after a restore the restored content is treated as this
/// device's current content; sync stays held for review until then.
class CloudArchiveSyncService {
  CloudArchiveSyncService({
    required this._gateway,
    required this._store,
    required this._queueArtworkUpload,
    String Function()? newId,
    DateTime Function()? now,
    this.pageSize = 200,
  }) : _newId = newId ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final CloudArchiveGateway _gateway;
  final CloudArchiveLocalStore _store;
  final QueueLibraryUpload _queueArtworkUpload;
  final String Function() _newId;
  final DateTime Function() _now;
  final int pageSize;

  Future<CloudArchiveSyncReport> synchronize(String userId) async {
    final report = CloudArchiveSyncReport();

    if (!await _gateway.isAvailable()) {
      report.skippedUnavailable = true;
      developer.log(
        'Cloud archive not available on this server; skipped.',
        name: 'sonus.sync.archive',
      );
      return report;
    }

    await _push(userId, report);
    // Records left waiting by an earlier pass; the pull handles the rest.
    await _retryPending(userId, report);
    await _pull(userId, report);
    return report;
  }

  Future<void> _push(String userId, CloudArchiveSyncReport report) async {
    final states = await _store.states(userId);
    final local = await _store.collect();
    final seen = <String>{};

    for (final record in local) {
      seen.add(record.recordId);
      final state = states[record.recordId];
      if (state != null && state.pendingApply) continue;
      if (state != null && state.fingerprint == record.fingerprint) continue;
      if (state != null && !record.kind.mutable) continue;

      if (!await _dependenciesInCloud(userId, record)) continue;

      final result = state == null
          ? await _gateway.insertIfAbsent(userId: userId, record: record)
          : await _gateway.updateIfRevision(
              userId: userId,
              record: record,
              expectedServerRevision: state.serverRevision,
            );

      if (result.outcome == CloudArchiveWriteOutcome.applied) {
        await _agree(userId, record, result.serverRevision!);
        report.uploaded++;
      } else {
        await _resolve(userId, record, report);
      }
    }

    // Removed here since the last sync: marked removed in the cloud, which
    // keeps the content so it can still be recovered.
    for (final MapEntry(key: recordId, value: state) in states.entries) {
      if (seen.contains(recordId) || state.pendingApply || state.cloudDeleted) {
        continue;
      }
      final separator = recordId.indexOf(':');
      final kind = CloudArchiveKind.fromWire(recordId.substring(0, separator));
      if (kind == null || !kind.mutable) continue;
      final key = recordId.substring(separator + 1);

      final cloud = (await _gateway.fetch(
        userId: userId,
        kind: kind,
        keys: [key],
      )).singleOrNull;
      // Changed elsewhere since: the pull below brings that version here.
      if (cloud == null || cloud.serverRevision != state.serverRevision) {
        continue;
      }

      final removal = CloudArchiveRecord(
        kind: kind,
        key: key,
        payload: cloud.payload,
        isDeleted: true,
        clientUpdatedAt: _now().toUtc(),
      );
      final result = await _gateway.updateIfRevision(
        userId: userId,
        record: removal,
        expectedServerRevision: state.serverRevision,
      );
      if (result.outcome == CloudArchiveWriteOutcome.applied) {
        await _store.saveState(
          userId,
          kind,
          key,
          CloudArchiveState(
            fingerprint: state.fingerprint,
            serverRevision: result.serverRevision!,
            cloudDeleted: true,
          ),
        );
      }
    }
  }

  /// A crop needs its images in the cloud first, or another device could
  /// not show it. Missing images are queued with the library upload.
  Future<bool> _dependenciesInCloud(
    String userId,
    CloudArchiveRecord record,
  ) async {
    if (record.kind != CloudArchiveKind.artworkCrop) return true;
    var ready = true;
    for (final column in ['source_artwork_id', 'output_artwork_id']) {
      final id = record.payload[column];
      if (id is! String) return false;
      if (!await _store.artworkInCloud(userId, id)) {
        await _queueArtworkUpload(userId: userId, artworkId: id);
        ready = false;
      }
    }
    return ready;
  }

  /// The write was refused: the cloud already has a different copy.
  Future<void> _resolve(
    String userId,
    CloudArchiveRecord local,
    CloudArchiveSyncReport report,
  ) async {
    final cloud = (await _gateway.fetch(
      userId: userId,
      kind: local.kind,
      keys: [local.key],
    )).singleOrNull;
    if (cloud == null) return; // Retried next sync.

    if (cloud.fingerprint == local.fingerprint) {
      // The same content, such as our own write whose response was lost.
      await _agree(userId, cloud, cloud.serverRevision!);
      return;
    }

    if (!local.kind.mutable) {
      // Immutable: the first copy stands; nothing here is changed.
      await _agree(userId, cloud, cloud.serverRevision!);
      return;
    }

    if (cloud.isDeleted ||
        (local.kind != CloudArchiveKind.playlist &&
            local.clientUpdatedAt.isAfter(cloud.clientUpdatedAt))) {
      // Edited here after the cloud copy (or brought back after a removal
      // elsewhere): this device's edit wins.
      final retry = await _gateway.updateIfRevision(
        userId: userId,
        record: local,
        expectedServerRevision: cloud.serverRevision!,
      );
      if (retry.outcome == CloudArchiveWriteOutcome.applied) {
        await _agree(userId, local, retry.serverRevision!);
        report.uploaded++;
        report.conflictsNewerWon++;
      }
      return;
    }

    if (local.kind == CloudArchiveKind.playlist) {
      final name = local.payload['name'];
      await _store.duplicatePlaylist(
        payload: local.payload,
        newId: _newId(),
        newName: '${name is String ? name : 'Playlist'} (this device)',
      );
      report.conflictsKeptBoth++;
    } else {
      report.conflictsNewerWon++;
    }
    await _download(userId, cloud, report);
  }

  Future<void> _pull(String userId, CloudArchiveSyncReport report) async {
    var cursor = await _store.cursor(userId);

    while (true) {
      final page = await _gateway.readPage(
        userId: userId,
        after: cursor,
        limit: pageSize,
      );
      if (page.isEmpty) return;

      final states = await _store.states(userId);
      final local = {
        for (final record in await _store.collect()) record.recordId: record,
      };

      for (final cloud in page) {
        final state = states[cloud.recordId];
        final here = local[cloud.recordId];

        final alreadyAgreed =
            state != null &&
            !state.pendingApply &&
            state.fingerprint == cloud.fingerprint;
        final changedHere =
            state != null &&
            here != null &&
            here.fingerprint != state.fingerprint;

        if (!alreadyAgreed && !changedHere) {
          if (here != null && here.fingerprint == cloud.fingerprint) {
            await _agree(userId, cloud, cloud.serverRevision!);
          } else {
            await _download(userId, cloud, report);
          }
        }

        cursor = CloudArchiveCursor(
          serverUpdatedAt: cloud.serverUpdatedAt!,
          recordId: cloud.recordId,
        );
      }

      await _store.saveCursor(userId, cursor!);
      if (page.length < pageSize) return;
    }
  }

  Future<void> _retryPending(
    String userId,
    CloudArchiveSyncReport report,
  ) async {
    final pending = <CloudArchiveKind, List<String>>{};
    for (final MapEntry(key: recordId, value: state) in (await _store.states(
      userId,
    )).entries) {
      if (!state.pendingApply) continue;
      final separator = recordId.indexOf(':');
      final kind = CloudArchiveKind.fromWire(recordId.substring(0, separator));
      if (kind == null) continue;
      pending
          .putIfAbsent(kind, () => [])
          .add(recordId.substring(separator + 1));
    }

    for (final MapEntry(key: kind, value: keys) in pending.entries) {
      for (var start = 0; start < keys.length; start += pageSize) {
        final batch = keys.sublist(
          start,
          start + pageSize > keys.length ? keys.length : start + pageSize,
        );
        for (final cloud in await _gateway.fetch(
          userId: userId,
          kind: kind,
          keys: batch,
        )) {
          await _download(userId, cloud, report);
        }
      }
    }
  }

  /// Applies a cloud copy here. A removal never removes anything here.
  Future<void> _download(
    String userId,
    CloudArchiveRecord cloud,
    CloudArchiveSyncReport report,
  ) async {
    if (cloud.isDeleted) {
      final here = (await _store.collect())
          .where((r) => r.recordId == cloud.recordId)
          .firstOrNull;
      await _store.saveState(
        userId,
        cloud.kind,
        cloud.key,
        CloudArchiveState(
          // Kept here as it is, and only sent again if it changes.
          fingerprint: here?.fingerprint ?? cloud.fingerprint,
          serverRevision: cloud.serverRevision!,
          cloudDeleted: true,
        ),
      );
      return;
    }

    final outcome = await _store.apply(cloud);
    final waiting = outcome == CloudArchiveApplyOutcome.missingDependencies;
    await _store.saveState(
      userId,
      cloud.kind,
      cloud.key,
      CloudArchiveState(
        fingerprint: cloud.fingerprint,
        serverRevision: cloud.serverRevision!,
        pendingApply: waiting,
      ),
    );
    if (waiting) {
      report.waitingForDependencies++;
    } else {
      report.downloaded++;
    }
  }

  Future<void> _agree(
    String userId,
    CloudArchiveRecord record,
    int serverRevision,
  ) => _store.saveState(
    userId,
    record.kind,
    record.key,
    CloudArchiveState(
      fingerprint: record.fingerprint,
      serverRevision: serverRevision,
    ),
  );
}
