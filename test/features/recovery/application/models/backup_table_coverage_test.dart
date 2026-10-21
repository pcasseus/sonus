import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

void main() {
  test('every declared table appears exactly once', () {
    final tables = BackupCoverageContract.tables;
    final names = tables.map((entry) => entry.table).toSet();

    expect(tables.length, 27);
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

    expect(local.length, 4);
    expect(local, contains(DatabaseTables.mediaFileBindings));
    expect(local, contains(DatabaseTables.importSources));
    expect(local, contains(DatabaseTables.importBatches));
    expect(local, contains(DatabaseTables.songImportReviews));
  });

  test('protects sync and ownership state from direct restoration', () {
    final internal = BackupCoverageContract.tables
        .where((entry) => entry.policy == BackupTablePolicy.internalState)
        .map((entry) => entry.table)
        .toSet();

    expect(internal.length, 6);
    expect(internal, contains(DatabaseTables.syncState));
    expect(internal, contains(DatabaseTables.syncOutbox));
    expect(internal, contains(DatabaseTables.localAccountBinding));
    expect(internal, contains(SyncSchema.cloudRevisionBaselinesTable));
    expect(internal, contains(SyncSchema.artistWriteJournalTable));
    expect(internal, contains(SyncSchema.artistDependencyJournalTable));
  });

  test('coverage collections cannot be modified', () {
    expect(
      () => BackupCoverageContract.portableTables.clear(),
      throwsUnsupportedError,
    );
  });
}
