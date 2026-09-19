import 'package:flutter/foundation.dart';

import '../../application/models/import_batch.dart';
import '../../application/models/import_execution_summary.dart';
import '../../application/services/import_source_picker.dart';
import '../../application/services/import_workflow_service.dart';
import '../../domain/entities/import_source.dart';
import '../../domain/models/import_source_discovery_exception.dart';

enum ImportsControllerStatus {
  idle,
  selectingSource,
  importing,
  completed,
  failed,
}

class ImportsController extends ChangeNotifier {
  ImportsController({
    required ImportWorkflowService workflowService,
    required ImportSourcePicker sourcePicker,
  }) : this._(workflowService: workflowService, sourcePicker: sourcePicker);

  ImportsController._({
    required this._workflowService,
    required this._sourcePicker,
  });

  final ImportWorkflowService _workflowService;
  final ImportSourcePicker _sourcePicker;

  ImportsControllerStatus _status = ImportsControllerStatus.idle;
  ImportBatch? _currentBatch;
  ImportExecutionSummary? _summary;
  Object? _error;
  String? _errorMessage;
  List<ImportSource> _sources = const [];
  bool _isLoadingSources = false;

  ImportsControllerStatus get status => _status;

  ImportBatch? get currentBatch => _currentBatch;

  ImportExecutionSummary? get summary => _summary;

  Object? get error => _error;

  String? get errorMessage => _errorMessage;

  List<ImportSource> get sources => _sources;

  bool get hasSources => _sources.isNotEmpty;

  bool get isLoadingSources => _isLoadingSources;

  bool get isBusy {
    return _status == ImportsControllerStatus.selectingSource ||
        _status == ImportsControllerStatus.importing;
  }

  bool get isSelectingSource {
    return _status == ImportsControllerStatus.selectingSource;
  }

  bool get isImporting {
    return _status == ImportsControllerStatus.importing;
  }

  bool get hasCompleted {
    return _status == ImportsControllerStatus.completed;
  }

  bool get hasError {
    return _status == ImportsControllerStatus.failed;
  }

  double get progress => _currentBatch?.progress ?? 0;

  int get totalCount => _currentBatch?.totalCount ?? 0;

  int get completedCount => _currentBatch?.completedCount ?? 0;

  Future<void> loadSources() async {
    if (_isLoadingSources) {
      return;
    }

    _isLoadingSources = true;
    notifyListeners();

    try {
      _sources = List.unmodifiable(await _workflowService.getSources());
    } finally {
      _isLoadingSources = false;
      notifyListeners();
    }
  }

  Future<bool> importSingleSong() async {
    if (isBusy) {
      return false;
    }

    _beginSelection();

    try {
      final filePath = await _sourcePicker.pickSongFile();

      if (filePath == null) {
        _cancelSelection();
        return false;
      }

      return _execute(
        () => _workflowService.importSingleSong(
          filePath,
          onProgress: _handleProgress,
        ),
      );
    } catch (error) {
      _fail(error);
      return false;
    }
  }

  Future<bool> importStructuredFolder() async {
    if (isBusy) {
      return false;
    }

    _beginSelection();

    try {
      final folderPath = await _sourcePicker.pickStructuredFolder();

      if (folderPath == null) {
        _cancelSelection();
        return false;
      }

      final result = await _execute(
        () => _workflowService.importStructuredFolder(
          folderPath,
          onProgress: _handleProgress,
        ),
      );

      if (result) {
        await loadSources();
      }

      return result;
    } catch (error) {
      _fail(error);
      return false;
    }
  }

  Future<bool> rescanSource(ImportSource source) async {
    if (isBusy) {
      return false;
    }

    final result = await _execute(
      () =>
          _workflowService.rescanSource(source.id, onProgress: _handleProgress),
    );

    if (result) {
      await loadSources();
    }

    return result;
  }

  Future<bool> _execute(
    Future<ImportExecutionSummary> Function() operation,
  ) async {
    _status = ImportsControllerStatus.importing;
    _currentBatch = null;
    _summary = null;
    _error = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final summary = await operation();

      _summary = summary;
      _status = ImportsControllerStatus.completed;
      notifyListeners();

      return true;
    } catch (error) {
      _fail(error);
      return false;
    }
  }

  void _handleProgress(ImportBatch batch) {
    _currentBatch = batch;
    notifyListeners();
  }

  void _beginSelection() {
    _status = ImportsControllerStatus.selectingSource;
    _currentBatch = null;
    _summary = null;
    _error = null;
    _errorMessage = null;
    notifyListeners();
  }

  void _cancelSelection() {
    _status = ImportsControllerStatus.idle;
    notifyListeners();
  }

  void _fail(Object error) {
    _error = error;
    _errorMessage = _messageFor(error);
    _status = ImportsControllerStatus.failed;
    notifyListeners();
  }

  String _messageFor(Object error) {
    if (error is ImportSourceDiscoveryException) {
      final sourcePath = error.path?.trim();

      if (sourcePath == null || sourcePath.isEmpty) {
        return error.message;
      }

      return '${error.message}\n\nProblem path:\n$sourcePath';
    }

    return 'Could not complete the import.';
  }

  void reset() {
    if (isBusy) {
      return;
    }

    _status = ImportsControllerStatus.idle;
    _currentBatch = null;
    _summary = null;
    _error = null;
    _errorMessage = null;
    notifyListeners();
  }
}
