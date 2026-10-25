import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_fingerprint_service.dart';

void main() {
  test('every declared table appears exactly once', () {
    final tables = BackupCoverageContract.tables;
    final names = tables.map((entry) => entry.table).toSet();

    expect(tables.length, 31);
    expect(names.length, tables.length);
    expect(names.every((name) => name.trim().isNotEmpty), isTrue);
  });

  test('preserves the complete portable data categories', () {
    final names = BackupCoverageContract.portableTables
        .map((entry) => entry.table)
        .toSet();

    expect(names.length, 17);

    expect(
      names,
      containsAll([
        DatabaseTables.artists,
        DatabaseTables.albums,
        DatabaseTables.albumEditions,
        DatabaseTables.albumEditionTracks,
        DatabaseTables.songs,
        DatabaseTables.songArtistCredits,
        DatabaseTables.artworkAssets,
        DatabaseTables.metadataFieldStates,
        DatabaseTables.trackLyrics,
        DatabaseTables.playbackSessions,
        DatabaseTables.playbackListeningSegments,
        DatabaseTables.qualifiedPlays,
        DatabaseTables.chartSnapshots,
        DatabaseTables.chartEntries,
        DatabaseTables.chartMomentEvents,
        DatabaseTables.playlists,
        DatabaseTables.playlistItems,
      ]),
    );
  });

  test('does not treat device-local paths as portable data', () {
    final local = BackupCoverageContract.tables
        .where((entry) => entry.policy == BackupTablePolicy.deviceLocal)
        .map((entry) => entry.table)
        .toSet();

    expect(local.length, 6);
    expect(local, contains(DatabaseTables.mediaFileBindings));
    expect(local, contains(DatabaseTables.importSources));
    expect(local, contains(DatabaseTables.importBatches));
    expect(local, contains(DatabaseTables.songImportReviews));
    expect(local, contains(DatabaseTables.albumReleaseClassifications));
    expect(local, contains(DatabaseTables.artistProjectAssignments));
  });

  test('protects sync and ownership state from direct restoration', () {
    final internal = BackupCoverageContract.tables
        .where((entry) => entry.policy == BackupTablePolicy.internalState)
        .map((entry) => entry.table)
        .toSet();

    expect(internal.length, 8);
    expect(internal, contains(DatabaseTables.syncState));
    expect(internal, contains(DatabaseTables.syncOutbox));
    expect(internal, contains(DatabaseTables.localAccountBinding));
    expect(internal, contains(SyncSchema.cloudRevisionBaselinesTable));
    expect(internal, contains(SyncSchema.artistWriteJournalTable));
    expect(internal, contains(SyncSchema.artistDependencyJournalTable));
    expect(internal, contains(SyncSchema.inboundDeferredRecordsTable));
    expect(internal, contains(SyncSchema.outboundConflictsTable));
  });

  test('every internal sync table is watched as sync state', () {
    final internal = BackupCoverageContract.tables
        .where((entry) => entry.policy == BackupTablePolicy.internalState)
        .map((entry) => entry.table)
        .toSet();

    // Restore change detection and the post-restore sync assessment both
    // rely on this list; an internal table missing here goes unnoticed.
    expect(RecoveryFingerprintService.syncStateTables.toSet(), internal);
  });

  test('coverage collections cannot be modified', () {
    expect(
      () => BackupCoverageContract.portableTables.clear(),
      throwsUnsupportedError,
    );
  });
}
