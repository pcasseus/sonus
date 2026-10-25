import '../../../../core/database/database_tables.dart';
import '../../../../core/database/schema/sync_schema.dart';

enum BackupTablePolicy { portableData, deviceLocal, internalState }

class BackupTableCoverage {
  const BackupTableCoverage({required this.table, required this.policy});

  final String table;
  final BackupTablePolicy policy;

  bool get isPortable => policy == BackupTablePolicy.portableData;
}

abstract final class BackupCoverageContract {
  static const List<BackupTableCoverage> tables = [
    // Library identities and relationships.
    BackupTableCoverage(
      table: DatabaseTables.artists,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.albums,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.albumEditions,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.albumEditionTracks,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.songs,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.songArtistCredits,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.artworkAssets,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.metadataFieldStates,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.trackLyrics,
      policy: BackupTablePolicy.portableData,
    ),

    // Listening history and analytics.
    BackupTableCoverage(
      table: DatabaseTables.playbackSessions,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.playbackListeningSegments,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.qualifiedPlays,
      policy: BackupTablePolicy.portableData,
    ),

    // Historical charts.
    BackupTableCoverage(
      table: DatabaseTables.chartSnapshots,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.chartEntries,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.chartMomentEvents,
      policy: BackupTablePolicy.portableData,
    ),

    // Playlists.
    BackupTableCoverage(
      table: DatabaseTables.playlists,
      policy: BackupTablePolicy.portableData,
    ),
    BackupTableCoverage(
      table: DatabaseTables.playlistItems,
      policy: BackupTablePolicy.portableData,
    ),

    // Device-specific information.
    BackupTableCoverage(
      table: DatabaseTables.mediaFileBindings,
      policy: BackupTablePolicy.deviceLocal,
    ),
    BackupTableCoverage(
      table: DatabaseTables.importBatches,
      policy: BackupTablePolicy.deviceLocal,
    ),
    BackupTableCoverage(
      table: DatabaseTables.importSources,
      policy: BackupTablePolicy.deviceLocal,
    ),
    BackupTableCoverage(
      table: DatabaseTables.songImportReviews,
      policy: BackupTablePolicy.deviceLocal,
    ),
    // Organization preferences. Device-local for now: adding portable tables
    // would need every older backup to restore without them.
    BackupTableCoverage(
      table: DatabaseTables.albumReleaseClassifications,
      policy: BackupTablePolicy.deviceLocal,
    ),
    BackupTableCoverage(
      table: DatabaseTables.artistProjectAssignments,
      policy: BackupTablePolicy.deviceLocal,
    ),
    // SN-45 crop positions. The cropped artwork itself is a normal,
    // portable artwork asset; only "move or reset the crop" stays here.
    BackupTableCoverage(
      table: DatabaseTables.artworkCrops,
      policy: BackupTablePolicy.deviceLocal,
    ),

    // Never restore as another device's active sync/ownership state.
    BackupTableCoverage(
      table: DatabaseTables.syncState,
      policy: BackupTablePolicy.internalState,
    ),
    BackupTableCoverage(
      table: DatabaseTables.syncOutbox,
      policy: BackupTablePolicy.internalState,
    ),
    BackupTableCoverage(
      table: DatabaseTables.localAccountBinding,
      policy: BackupTablePolicy.internalState,
    ),
    BackupTableCoverage(
      table: SyncSchema.cloudRevisionBaselinesTable,
      policy: BackupTablePolicy.internalState,
    ),
    BackupTableCoverage(
      table: SyncSchema.artistWriteJournalTable,
      policy: BackupTablePolicy.internalState,
    ),
    BackupTableCoverage(
      table: SyncSchema.artistDependencyJournalTable,
      policy: BackupTablePolicy.internalState,
    ),
    BackupTableCoverage(
      table: SyncSchema.inboundDeferredRecordsTable,
      policy: BackupTablePolicy.internalState,
    ),
    BackupTableCoverage(
      table: SyncSchema.outboundConflictsTable,
      policy: BackupTablePolicy.internalState,
    ),
  ];

  static List<BackupTableCoverage> get portableTables =>
      List.unmodifiable(tables.where((entry) => entry.isPortable));
}
