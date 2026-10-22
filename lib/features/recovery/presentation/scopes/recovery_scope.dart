import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:saf/saf.dart';

import '../../../../core/database/app_database.dart';
import '../../../import/application/services/metadata_resolver.dart';
import '../../../import/data/services/file_system_import_candidate_discovery.dart';
import '../../../import/data/services/media_metadata_reader.dart';
import '../../../import/data/services/path_fallback_metadata_reader.dart';
import '../../../import/data/services/saf_import_candidate_discovery.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../sync/application/services/automatic_sync_coordinator.dart';
import '../../application/controllers/backup_restore_controller.dart';
import '../../application/services/recovery_audio_service.dart';
import '../../application/services/recovery_service.dart';
import '../../application/services/recovery_sync_gate.dart';
import '../services/file_picker_recovery_file_picker.dart';

/// Provides [BackupRestoreController] and runs the interrupted-restore
/// check at startup, before cloud sync is allowed to begin.
class RecoveryScope extends StatefulWidget {
  const RecoveryScope({super.key, required this.child, this.service});

  final Widget child;

  /// Overrides the platform service (tests).
  final RecoveryService? service;

  @override
  State<RecoveryScope> createState() => _RecoveryScopeState();
}

class _RecoveryScopeState extends State<RecoveryScope> {
  final Saf _saf = Saf();

  BackupRestoreController? _controller;
  AppDatabase? _database;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final database = context.watch<AppDatabase>();

    if (identical(database, _database)) return;

    _database = database;
    _controller?.dispose();

    final controller = BackupRestoreController(
      service: widget.service ?? _platformService(database),
      onSyncMayResume: _resumeSync,
    );

    _controller = controller;
    unawaited(controller.initialize());
  }

  RecoveryService _platformService(AppDatabase database) {
    final gate = context.read<RecoverySyncGate?>() ?? RecoverySyncGate.application;
    final playback = context.read<PlaybackCoordinator>();

    Future<Directory> support() => getApplicationSupportDirectory();
    Future<Directory> artwork() async =>
        Directory(path.join((await support()).path, 'sonus', 'artwork'));

    return DefaultRecoveryService(
      appDatabase: database,
      gate: gate,
      recoveryDirectory: applicationRecoveryDirectory,
      artworkDirectory: artwork,
      supportDirectory: support,
      picker: FilePickerRecoveryFilePicker(saf: _saf),
      stopPlayback: playback.stop,
      relink: (folder) => RecoveryAudioRelinkService(
        appDatabase: database,
        candidateDiscovery: Platform.isAndroid
            ? SafImportCandidateDiscovery(saf: _saf)
            : const FileSystemImportCandidateDiscovery(),
        metadataResolver: MetadataResolver(
          primaryReader: MediaMetadataReader(
            saf: Platform.isAndroid ? _saf : null,
          ),
          fallbackReader: const PathFallbackMetadataReader(),
        ),
        onSongsBecameUnavailable: playback.removeSongsFromQueue,
      ).relinkFolder(folder),
    );
  }

  void _resumeSync() {
    if (!mounted) return;

    // Sync attempts made before the check were rejected; try again now.
    unawaited(context.read<AutomaticSyncCoordinator?>()?.trigger());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<BackupRestoreController?>.value(
      value: _controller,
      child: widget.child,
    );
  }
}
