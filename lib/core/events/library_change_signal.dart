// ignore_for_file: prefer_initializing_formals

import 'dart:async';

/// What changed, at the level screens refresh on.
enum LibraryChangeKind {
  /// Songs, albums, editions, credits, artwork or organization were edited.
  libraryEdited,

  /// An import finished.
  importCompleted,

  /// A qualified play was recorded, so rankings and listening stats moved.
  listeningRecorded,
}

/// App-wide notice that persisted library or listening data changed, so
/// screens holding their own copies can reload.
///
/// Deliberately coarse and only sent after a change is committed: never for
/// playback progress, only for data screens read. Screens subscribe through
/// [LibraryChangeRefresher], which batches bursts into one reload.
class LibraryChangeSignal {
  LibraryChangeSignal();

  /// The app's signal. Emitters and scopes use it unless given another.
  static final LibraryChangeSignal shared = LibraryChangeSignal();

  final StreamController<LibraryChangeKind> _changes =
      StreamController<LibraryChangeKind>.broadcast(sync: true);

  Stream<LibraryChangeKind> get changes => _changes.stream;

  void notify(LibraryChangeKind kind) {
    if (!_changes.isClosed) {
      _changes.add(kind);
    }
  }
}

/// Calls [onChange] once after a burst of relevant changes settles.
///
/// Lifecycle-safe: [dispose] cancels the subscription and any pending call.
class LibraryChangeRefresher {
  LibraryChangeRefresher({
    required LibraryChangeSignal signal,
    required Set<LibraryChangeKind> kinds,
    required void Function() onChange,
    Duration settle = const Duration(milliseconds: 300),
  }) : _onChange = onChange,
       _settle = settle {
    _subscription = signal.changes
        .where(kinds.contains)
        .listen((_) => _schedule());
  }

  final void Function() _onChange;
  final Duration _settle;
  late final StreamSubscription<LibraryChangeKind> _subscription;
  Timer? _pending;

  void _schedule() {
    _pending?.cancel();
    _pending = Timer(_settle, _onChange);
  }

  void dispose() {
    _pending?.cancel();
    unawaited(_subscription.cancel());
  }
}
