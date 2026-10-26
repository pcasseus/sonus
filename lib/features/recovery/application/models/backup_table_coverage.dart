import '../../../../core/database/database_tables.dart';
import '../../../../core/database/schema/sync_schema.dart';

enum BackupTablePolicy { portableData, deviceLocal, internalState }

class BackupTableCoverage {
  const BackupTableCoverage({
    required this.table,
    required this.policy,
    this.requiredInEveryBackup = true,
  });

  final String table;
  final BackupTablePolicy policy;

  /// False for portable tables that older backups do not contain. New
  /// backups always include them; restoring a backup without one leaves
  /// that table's local rows as they are.
  final bool requiredInEveryBackup;

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
    // User-made organization and crop positions. Portable, but backups made
    // before they were included restore without them.
    BackupTableCoverage(
      table: DatabaseTables.albumReleaseClassifications,
      policy: BackupTablePolicy.portableData,
      requiredInEveryBackup: false,
    ),
    BackupTableCoverage(
      table: DatabaseTables.artistProjectAssignments,
      policy: BackupTablePolicy.portableData,
      requiredInEveryBackup: false,
    ),
    BackupTableCoverage(
      table: DatabaseTables.artworkCrops,
      policy: BackupTablePolicy.portableData,
      requiredInEveryBackup: false,
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
      table: DatabaseTables.cloudArchiveState,
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

  /// Portable tables every restorable backup must contain.
  static Set<String> get requiredPortableTableNames => {
    for (final entry in portableTables)
      if (entry.requiredInEveryBackup) entry.table,
  };

  static Set<String> get portableTableNames => {
    for (final entry in portableTables) entry.table,
  };

  /// Whether [names] is a valid set of backed-up tables: every required
  /// table, any optional ones, and nothing else.
  static bool isValidBackupTableSet(Set<String> names) =>
      names.containsAll(requiredPortableTableNames) &&
      portableTableNames.containsAll(names);
}
