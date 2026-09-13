import 'sync_mutation_context.dart';

typedef SyncMutationAction<T> = Future<T> Function(SyncMutationContext context);

abstract interface class SyncMutationRunner {
  Future<T> run<T>(SyncMutationAction<T> action);
}
